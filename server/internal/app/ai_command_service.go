package app

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"slices"
	"strings"
	"time"

	"nexdo-server-golang/internal/models"

	"github.com/golang-jwt/jwt/v5"
)

type aiCommandService struct {
	app        *Application
	httpClient *http.Client
}

type aiCommandProgressReporter func(aiCommandStreamStatusPayload)

type aiCommandConfirmationClaims struct {
	Intent        string   `json:"intent"`
	OperationType string   `json:"operation_type"`
	Action        string   `json:"action"`
	TargetType    string   `json:"target_type"`
	TargetIDs     []string `json:"target_ids"`
	ProposalHash  string   `json:"proposal_hash"`
	StepCount     int      `json:"step_count"`
	jwt.RegisteredClaims
}

func newAICommandService(app *Application) aiCommandService {
	return aiCommandService{
		app: app,
		httpClient: &http.Client{
			Timeout: app.cfg.AIServiceTimeout,
		},
	}
}

func (s aiCommandService) resolve(userID, input string) (aiCommandResolveResponse, error) {
	return s.resolveWithProgress(userID, input, nil)
}

func (s aiCommandService) resolveWithProgress(userID, input string, report aiCommandProgressReporter) (aiCommandResolveResponse, error) {
	user, err := s.app.requireUser(userID)
	if err != nil {
		return aiCommandResolveResponse{}, err
	}
	timezone := strings.TrimSpace(user.Timezone)
	if timezone == "" {
		timezone = "Asia/Shanghai"
	}
	now := nowISO()

	s.reportProgress(report, "parsing", "正在解析你的指令")

	classification, err := s.classify(aiCommandClassifyRequest{
		UserInput: input,
		Timezone:  timezone,
		Now:       now,
	})
	if err != nil {
		return aiCommandResolveResponse{}, err
	}

	s.reportProgress(report, "loading_context", "正在加载相关提醒与上下文")

	context, summary, err := s.loadContext(userID, classification.Intent)
	if err != nil {
		return aiCommandResolveResponse{}, err
	}

	s.reportProgress(report, "planning", "正在生成执行计划")

	proposal, err := s.propose(aiCommandProposeRequest{
		UserInput:      input,
		Classification: classification,
		Timezone:       timezone,
		Now:            now,
		Context:        context,
	})
	if err != nil {
		return aiCommandResolveResponse{}, err
	}

	response := aiCommandResolveResponse{
		Input:          input,
		Mode:           proposal.Status,
		Classification: classification,
		ContextSummary: summary,
		Result:         proposal,
	}

	if proposal.RequiresConfirmation && proposal.Proposal != nil {
		proposal, err = s.attachConfirmationPreview(userID, proposal)
		if err != nil {
			return aiCommandResolveResponse{}, err
		}
		response.Result = proposal
		confirmation, err := s.issueConfirmationToken(userID, proposal)
		if err != nil {
			return aiCommandResolveResponse{}, err
		}
		response.Confirmation = &confirmation
		s.reportProgress(report, "waiting_confirmation", "已生成待确认方案")
	} else {
		s.reportProgress(report, "completed", "解析完成")
	}

	return response, nil
}

func (s aiCommandService) reportProgress(report aiCommandProgressReporter, stage, message string) {
	if report == nil {
		return
	}
	report(aiCommandStreamStatusPayload{
		Stage:   stage,
		Message: message,
	})
}

func (s aiCommandService) verifyConfirmationToken(token string) (aiCommandVerifyResponse, error) {
	typed, record, err := s.validateConfirmationToken(token)
	if err != nil {
		return aiCommandVerifyResponse{}, err
	}
	expiresAt := ""
	if record.ExpiresAt != "" {
		expiresAt = record.ExpiresAt
	}
	return aiCommandVerifyResponse{
		Valid:     true,
		ExpiresAt: expiresAt,
		Claims: aiCommandConfirmationClaimsView{
			UserID:        typed.Subject,
			Intent:        typed.Intent,
			OperationType: typed.OperationType,
			Action:        typed.Action,
			TargetType:    typed.TargetType,
			TargetIDs:     typed.TargetIDs,
			ProposalHash:  typed.ProposalHash,
			StepCount:     typed.StepCount,
		},
	}, nil
}

func (s aiCommandService) executeConfirmationToken(userID, token string) (aiCommandExecuteResponse, error) {
	claims, record, err := s.validateConfirmationToken(token)
	if err != nil {
		return aiCommandExecuteResponse{}, err
	}
	if claims.Subject != userID || record.UserID != userID {
		return aiCommandExecuteResponse{}, unauthorized("confirmation token 不属于当前用户")
	}

	result, err := s.executePlan(userID, record)
	if err != nil {
		return aiCommandExecuteResponse{}, err
	}

	now := nowISO()
	record.ConsumedAt = &now
	record.UpdatedAt = now
	if err := s.app.db.Save(&record).Error; err != nil {
		return aiCommandExecuteResponse{}, err
	}

	return aiCommandExecuteResponse{
		Executed: true,
		Action:   claims.Action,
		Result:   result,
		Claims: aiCommandConfirmationClaimsView{
			UserID:        claims.Subject,
			Intent:        claims.Intent,
			OperationType: claims.OperationType,
			Action:        claims.Action,
			TargetType:    claims.TargetType,
			TargetIDs:     claims.TargetIDs,
			ProposalHash:  claims.ProposalHash,
			StepCount:     claims.StepCount,
		},
	}, nil
}

func (s aiCommandService) classify(req aiCommandClassifyRequest) (aiCommandClassificationResult, error) {
	var resp aiCommandClassifyResponse
	if err := s.postJSON("/api/commands/classify", req, &resp); err != nil {
		return aiCommandClassificationResult{}, err
	}
	return resp.Classification, nil
}

func (s aiCommandService) propose(req aiCommandProposeRequest) (aiCommandProposalResult, error) {
	var resp aiCommandProposeResponse
	if err := s.postJSON("/api/commands/propose", req, &resp); err != nil {
		return aiCommandProposalResult{}, err
	}
	return resp.Proposal, nil
}

func (s aiCommandService) postJSON(path string, requestBody any, out any) error {
	baseURL := strings.TrimRight(s.app.cfg.AIServiceBaseURL, "/")
	body, err := json.Marshal(requestBody)
	if err != nil {
		return internal(err.Error())
	}
	req, err := http.NewRequest(http.MethodPost, baseURL+path, bytes.NewReader(body))
	if err != nil {
		return internal(err.Error())
	}
	req.Header.Set("Content-Type", "application/json")
	startedAt := time.Now()
	log.Printf("[AIService] request_start path=%s body=%s", path, string(body))

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return internal("AI service request failed: " + err.Error())
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return internal(err.Error())
	}
	log.Printf(
		"[AIService] request_done path=%s status=%d elapsed_ms=%d body=%s",
		path,
		resp.StatusCode,
		time.Since(startedAt).Milliseconds(),
		strings.TrimSpace(string(respBody)),
	)

	if resp.StatusCode >= 400 {
		return internal(fmt.Sprintf("AI service returned %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody))))
	}
	if err := json.Unmarshal(respBody, out); err != nil {
		return internal("AI service response decode failed: " + err.Error())
	}
	return nil
}

func (s aiCommandService) loadContext(userID, intent string) (aiCommandContextPayload, aiCommandContextSummary, error) {
	switch intent {
	case "reminder.query", "reminder.create", "reminder.update", "reminder.delete", "reminder.complete", "reminder.uncomplete":
		return s.loadReminderContext(userID)
	case "quick_note.convert", "quick_note.query":
		return s.loadQuickNoteContext(userID)
	case "list.query":
		return s.loadListContext(userID)
	default:
		return newAICommandContextPayload(), aiCommandContextSummary{}, nil
	}
}

func newAICommandContextPayload() aiCommandContextPayload {
	return aiCommandContextPayload{
		Reminders:  []aiCommandReminderCandidate{},
		QuickNotes: []aiCommandQuickNoteCandidate{},
		Lists:      []aiCommandResourceCandidate{},
		Groups:     []aiCommandResourceCandidate{},
		Tags:       []aiCommandResourceCandidate{},
	}
}

func (s aiCommandService) loadReminderContext(userID string) (aiCommandContextPayload, aiCommandContextSummary, error) {
	reminders, err := reminderRepository{db: s.app.db}.list(userID, emptyQueryProvider{})
	if err != nil {
		return aiCommandContextPayload{}, aiCommandContextSummary{}, err
	}
	lists, err := newResourceService(s.app).listLists(userID)
	if err != nil {
		return aiCommandContextPayload{}, aiCommandContextSummary{}, err
	}
	groups, err := newResourceService(s.app).listGroups(userID)
	if err != nil {
		return aiCommandContextPayload{}, aiCommandContextSummary{}, err
	}
	tags, err := newResourceService(s.app).listTags(userID)
	if err != nil {
		return aiCommandContextPayload{}, aiCommandContextSummary{}, err
	}

	listNames := map[string]string{}
	for _, item := range lists {
		listNames[item.ID] = item.Name
	}
	groupNames := map[string]string{}
	for _, item := range groups {
		groupNames[item.ID] = item.Name
	}
	tagNamesByReminderID, err := s.loadReminderTagNames(reminders, tags)
	if err != nil {
		return aiCommandContextPayload{}, aiCommandContextSummary{}, err
	}

	result := newAICommandContextPayload()
	result.Reminders = make([]aiCommandReminderCandidate, 0, len(reminders))
	result.Lists = make([]aiCommandResourceCandidate, 0, len(lists))
	result.Groups = make([]aiCommandResourceCandidate, 0, len(groups))
	result.Tags = make([]aiCommandResourceCandidate, 0, len(tags))
	for _, item := range reminders {
		var dueAt *string
		if strings.TrimSpace(item.DueAt) != "" {
			value := item.DueAt
			dueAt = &value
		}
		var note *string
		if strings.TrimSpace(item.Note) != "" {
			value := item.Note
			note = &value
		}
		var listName *string
		if name := strings.TrimSpace(listNames[item.ListID]); name != "" {
			listName = &name
		}
		var groupName *string
		if name := strings.TrimSpace(groupNames[item.GroupID]); name != "" {
			groupName = &name
		}
		result.Reminders = append(result.Reminders, aiCommandReminderCandidate{
			ID:        item.ID,
			Title:     item.Title,
			DueAt:     dueAt,
			Note:      note,
			Completed: item.IsCompleted,
			ListName:  listName,
			GroupName: groupName,
			Tags:      tagNamesByReminderID[item.ID],
			Aliases:   buildReminderAliases(item.Title),
		})
	}
	for _, item := range lists {
		result.Lists = append(result.Lists, aiCommandResourceCandidate{ID: item.ID, Name: item.Name})
	}
	for _, item := range groups {
		result.Groups = append(result.Groups, aiCommandResourceCandidate{ID: item.ID, Name: item.Name})
	}
	for _, item := range tags {
		result.Tags = append(result.Tags, aiCommandResourceCandidate{ID: item.ID, Name: item.Name})
	}
	return result, aiCommandContextSummary{
		RemindersLoaded: len(result.Reminders),
		ListsLoaded:     len(result.Lists),
		GroupsLoaded:    len(result.Groups),
		TagsLoaded:      len(result.Tags),
	}, nil
}

func (s aiCommandService) loadQuickNoteContext(userID string) (aiCommandContextPayload, aiCommandContextSummary, error) {
	items, err := quickNoteRepository{}.list(s.app, userID)
	if err != nil {
		return aiCommandContextPayload{}, aiCommandContextSummary{}, err
	}
	result := newAICommandContextPayload()
	result.QuickNotes = make([]aiCommandQuickNoteCandidate, 0, len(items))
	for _, item := range items {
		createdAt := item.CreatedAt
		result.QuickNotes = append(result.QuickNotes, aiCommandQuickNoteCandidate{
			ID:        item.ID,
			Content:   item.Content,
			CreatedAt: &createdAt,
		})
	}
	return result, aiCommandContextSummary{
		QuickNotesLoaded: len(result.QuickNotes),
	}, nil
}

func (s aiCommandService) loadListContext(userID string) (aiCommandContextPayload, aiCommandContextSummary, error) {
	lists, err := newResourceService(s.app).listLists(userID)
	if err != nil {
		return aiCommandContextPayload{}, aiCommandContextSummary{}, err
	}
	groups, err := newResourceService(s.app).listGroups(userID)
	if err != nil {
		return aiCommandContextPayload{}, aiCommandContextSummary{}, err
	}
	tags, err := newResourceService(s.app).listTags(userID)
	if err != nil {
		return aiCommandContextPayload{}, aiCommandContextSummary{}, err
	}
	result := newAICommandContextPayload()
	result.Lists = make([]aiCommandResourceCandidate, 0, len(lists))
	result.Groups = make([]aiCommandResourceCandidate, 0, len(groups))
	result.Tags = make([]aiCommandResourceCandidate, 0, len(tags))
	for _, item := range lists {
		result.Lists = append(result.Lists, aiCommandResourceCandidate{ID: item.ID, Name: item.Name})
	}
	for _, item := range groups {
		result.Groups = append(result.Groups, aiCommandResourceCandidate{ID: item.ID, Name: item.Name})
	}
	for _, item := range tags {
		result.Tags = append(result.Tags, aiCommandResourceCandidate{ID: item.ID, Name: item.Name})
	}
	return result, aiCommandContextSummary{
		ListsLoaded:  len(result.Lists),
		GroupsLoaded: len(result.Groups),
		TagsLoaded:   len(result.Tags),
	}, nil
}

func (s aiCommandService) loadReminderTagNames(reminders []models.Reminder, tags []models.Tag) (map[string][]string, error) {
	ids := make([]string, 0, len(reminders))
	for _, reminder := range reminders {
		ids = append(ids, reminder.ID)
	}
	tagNameByID := map[string]string{}
	for _, tag := range tags {
		tagNameByID[tag.ID] = tag.Name
	}
	tagViewsByReminderID, err := s.app.reminderTagsByIDs(ids)
	if err != nil {
		return nil, err
	}
	result := map[string][]string{}
	for reminderID, tagItems := range tagViewsByReminderID {
		values := make([]string, 0, len(tagItems))
		for _, tag := range tagItems {
			if name := strings.TrimSpace(tagNameByID[tag.ID]); name != "" {
				values = append(values, name)
			} else if strings.TrimSpace(tag.Name) != "" {
				values = append(values, tag.Name)
			}
		}
		result[reminderID] = values
	}
	return result, nil
}

func buildReminderAliases(title string) []string {
	normalized := strings.TrimSpace(strings.ToLower(title))
	if normalized == "" {
		return nil
	}

	aliasSet := map[string]struct{}{
		title: {},
	}

	add := func(values ...string) {
		for _, value := range values {
			value = strings.TrimSpace(value)
			if value == "" {
				continue
			}
			aliasSet[value] = struct{}{}
		}
	}

	// 通用去修饰版本，降低字面差异影响。
	replacements := []string{
		"提醒", "", "事项", "", "任务", "", "一下", "", "一趟", "",
	}
	simplified := strings.NewReplacer(replacements...).Replace(title)
	add(simplified)

	// 业务常见口语同义词。
	if strings.Contains(title, "公司") || strings.Contains(title, "上班") {
		add("上班", "去公司", "回公司", "到公司", "公司")
	}
	if strings.Contains(title, "下班") || strings.Contains(title, "回家") {
		add("下班", "回家", "回去", "回家里")
	}
	if strings.Contains(title, "会议") || strings.Contains(title, "开会") {
		add("会议", "开会", "开个会")
	}
	if strings.Contains(title, "沟通") || strings.Contains(title, "联系") {
		add("沟通", "联系", "对接")
	}
	if strings.Contains(title, "医院") || strings.Contains(title, "看病") {
		add("去医院", "看病", "就诊", "医院")
	}
	if strings.Contains(title, "吃饭") || strings.Contains(title, "午饭") || strings.Contains(title, "晚饭") {
		add("吃饭", "用餐", "吃个饭")
	}
	if strings.Contains(title, "快递") {
		add("拿快递", "取快递", "快递")
	}

	aliases := make([]string, 0, len(aliasSet))
	for value := range aliasSet {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		aliases = append(aliases, value)
	}
	slices.Sort(aliases)
	return aliases
}

func (s aiCommandService) attachConfirmationPreview(userID string, proposal aiCommandProposalResult) (aiCommandProposalResult, error) {
	plan := proposal.Plan
	if len(plan) == 0 && proposal.Proposal != nil {
		plan = []aiCommandPlanStep{{
			Step:       1,
			Summary:    proposal.Summary,
			Action:     proposal.Proposal.Action,
			TargetType: proposal.Proposal.TargetType,
			TargetIDs:  proposal.Proposal.TargetIDs,
			Patch:      proposal.Proposal.Patch,
			Reason:     proposal.Proposal.Reason,
			RiskLevel:  proposal.Proposal.RiskLevel,
		}}
	}
	if len(plan) == 0 {
		return proposal, nil
	}
	previewedPlan := make([]aiCommandPlanStep, 0, len(plan))
	for _, step := range plan {
		previewItems, err := s.buildStepPreviewItems(userID, step)
		if err != nil {
			return proposal, err
		}
		step.PreviewItems = previewItems
		previewedPlan = append(previewedPlan, step)
	}
	proposal.Plan = previewedPlan
	return proposal, nil
}

func (s aiCommandService) buildStepPreviewItems(userID string, step aiCommandPlanStep) ([]aiCommandPreviewItem, error) {
	if step.TargetType != "reminder" && step.Action != "create_reminder" {
		return nil, nil
	}
	lookups, err := s.loadReminderPreviewLookups(userID)
	if err != nil {
		return nil, err
	}
	switch step.Action {
	case "create_reminder":
		payload, err := s.buildCreateReminderPayload(userID, step)
		if err != nil {
			return nil, err
		}
		created := reminderPayloadPreview(payload)
		return []aiCommandPreviewItem{{
			TargetID: "new",
			Title:    created.Title,
			Action:   step.Action,
			After:    buildReminderPreviewSnapshot(created, lookups, payload.TagIDs),
		}}, nil
	case "update_reminder":
		items := make([]aiCommandPreviewItem, 0, len(step.TargetIDs))
		for _, reminderID := range step.TargetIDs {
			current, err := reminderRepository{db: s.app.db}.get(userID, reminderID)
			if err != nil {
				return nil, err
			}
			currentTagIDs, err := s.app.reminderTagIDs(reminderID)
			if err != nil {
				return nil, err
			}
			payload, err := s.buildUpdateReminderPayloadForTarget(step, reminderID)
			if err != nil {
				return nil, err
			}
			next, nextTagIDs := applyUpdateReminderPreview(current, currentTagIDs, payload)
			items = append(items, aiCommandPreviewItem{
				TargetID: reminderID,
				Title:    current.Title,
				Action:   step.Action,
				Before:   buildReminderPreviewSnapshot(current, lookups, currentTagIDs),
				After:    buildReminderPreviewSnapshot(next, lookups, nextTagIDs),
			})
		}
		return items, nil
	case "delete_reminder":
		items := make([]aiCommandPreviewItem, 0, len(step.TargetIDs))
		for _, reminderID := range step.TargetIDs {
			current, err := reminderRepository{db: s.app.db}.get(userID, reminderID)
			if err != nil {
				return nil, err
			}
			currentTagIDs, err := s.app.reminderTagIDs(reminderID)
			if err != nil {
				return nil, err
			}
			items = append(items, aiCommandPreviewItem{
				TargetID: reminderID,
				Title:    current.Title,
				Action:   step.Action,
				Before:   buildReminderPreviewSnapshot(current, lookups, currentTagIDs),
				After: map[string]string{
					"状态": "已删除",
				},
			})
		}
		return items, nil
	case "complete_reminder", "uncomplete_reminder":
		items := make([]aiCommandPreviewItem, 0, len(step.TargetIDs))
		targetCompleted := step.Action == "complete_reminder"
		for _, reminderID := range step.TargetIDs {
			current, err := reminderRepository{db: s.app.db}.get(userID, reminderID)
			if err != nil {
				return nil, err
			}
			currentTagIDs, err := s.app.reminderTagIDs(reminderID)
			if err != nil {
				return nil, err
			}
			next := current
			next.IsCompleted = targetCompleted
			after := buildReminderPreviewSnapshot(next, lookups, currentTagIDs)
			if targetCompleted && current.RepeatRule != "none" {
				after["结果"] = "完成当前实例后生成下一次提醒"
			}
			items = append(items, aiCommandPreviewItem{
				TargetID: reminderID,
				Title:    current.Title,
				Action:   step.Action,
				Before:   buildReminderPreviewSnapshot(current, lookups, currentTagIDs),
				After:    after,
			})
		}
		return items, nil
	default:
		return nil, nil
	}
}

type aiCommandReminderPreviewLookups struct {
	listNames  map[string]string
	groupNames map[string]string
	tagNames   map[string]string
}

func (s aiCommandService) loadReminderPreviewLookups(userID string) (aiCommandReminderPreviewLookups, error) {
	lists, err := newResourceService(s.app).listLists(userID)
	if err != nil {
		return aiCommandReminderPreviewLookups{}, err
	}
	groups, err := newResourceService(s.app).listGroups(userID)
	if err != nil {
		return aiCommandReminderPreviewLookups{}, err
	}
	tags, err := newResourceService(s.app).listTags(userID)
	if err != nil {
		return aiCommandReminderPreviewLookups{}, err
	}
	lookups := aiCommandReminderPreviewLookups{
		listNames:  make(map[string]string, len(lists)),
		groupNames: make(map[string]string, len(groups)),
		tagNames:   make(map[string]string, len(tags)),
	}
	for _, item := range lists {
		lookups.listNames[item.ID] = item.Name
	}
	for _, item := range groups {
		lookups.groupNames[item.ID] = item.Name
	}
	for _, item := range tags {
		lookups.tagNames[item.ID] = item.Name
	}
	return lookups, nil
}

func reminderPayloadPreview(payload reminderPayload) models.Reminder {
	repeatRule := "none"
	if payload.RepeatRule != nil && strings.TrimSpace(*payload.RepeatRule) != "" {
		repeatRule = strings.TrimSpace(*payload.RepeatRule)
	}
	return models.Reminder{
		Title:               payload.Title,
		Note:                valueOrDefault(payload.Note, ""),
		DueAt:               payload.DueAt,
		RepeatUntilAt:       payload.RepeatUntilAt,
		RemindBeforeMinutes: valueOrDefault(payload.RemindBeforeMinutes, 0),
		ListID:              payload.ListID,
		GroupID:             payload.GroupID,
		NotificationEnabled: boolOrDefault(payload.NotificationEnabled, true),
		RepeatRule:          repeatRule,
		IsCompleted:         false,
	}
}

func applyUpdateReminderPreview(current models.Reminder, currentTagIDs []string, payload updateReminderPayload) (models.Reminder, []string) {
	next := current
	nextTagIDs := append([]string{}, currentTagIDs...)
	if payload.Title != nil {
		next.Title = *payload.Title
	}
	if payload.Note != nil {
		next.Note = *payload.Note
	}
	if payload.DueAt != nil {
		next.DueAt = *payload.DueAt
	}
	if payload.RepeatUntilAt.Set {
		if payload.RepeatUntilAt.Valid {
			value := strings.TrimSpace(payload.RepeatUntilAt.Value)
			next.RepeatUntilAt = &value
		} else {
			next.RepeatUntilAt = nil
		}
	}
	if payload.RemindBeforeMinutes != nil {
		next.RemindBeforeMinutes = *payload.RemindBeforeMinutes
	}
	if payload.ListID != nil {
		next.ListID = *payload.ListID
	}
	if payload.GroupID != nil {
		next.GroupID = *payload.GroupID
	}
	if payload.NotificationEnabled != nil {
		next.NotificationEnabled = *payload.NotificationEnabled
	}
	if payload.RepeatRule != nil {
		next.RepeatRule = *payload.RepeatRule
	}
	if payload.IsCompleted != nil {
		next.IsCompleted = *payload.IsCompleted
	}
	if payload.TagIDs != nil {
		nextTagIDs = append([]string{}, payload.TagIDs...)
	}
	return next, nextTagIDs
}

func buildReminderPreviewSnapshot(item models.Reminder, lookups aiCommandReminderPreviewLookups, tagIDs []string) map[string]string {
	snapshot := map[string]string{
		"标题": item.Title,
		"时间": item.DueAt,
		"状态": map[bool]string{true: "已完成", false: "未完成"}[item.IsCompleted],
		"重复": normalizeRepeatRule(item.RepeatRule),
	}
	if strings.TrimSpace(item.Note) != "" {
		snapshot["备注"] = item.Note
	}
	if item.RepeatUntilAt != nil && strings.TrimSpace(*item.RepeatUntilAt) != "" {
		snapshot["循环截止"] = strings.TrimSpace(*item.RepeatUntilAt)
	}
	snapshot["提前提醒"] = fmt.Sprintf("%d 分钟", item.RemindBeforeMinutes)
	snapshot["通知"] = map[bool]string{true: "开启", false: "关闭"}[item.NotificationEnabled]
	if name := strings.TrimSpace(lookups.listNames[item.ListID]); name != "" {
		snapshot["清单"] = name
	}
	if name := strings.TrimSpace(lookups.groupNames[item.GroupID]); name != "" {
		snapshot["分组"] = name
	}
	if len(tagIDs) > 0 {
		tagNames := make([]string, 0, len(tagIDs))
		for _, tagID := range tagIDs {
			if name := strings.TrimSpace(lookups.tagNames[tagID]); name != "" {
				tagNames = append(tagNames, name)
			}
		}
		if len(tagNames) > 0 {
			snapshot["标签"] = strings.Join(tagNames, "、")
		}
	}
	return snapshot
}

func (s aiCommandService) issueConfirmationToken(userID string, proposal aiCommandProposalResult) (aiCommandConfirmationPayload, error) {
	if proposal.Proposal == nil {
		return aiCommandConfirmationPayload{}, badRequest("proposal 不存在")
	}
	plan := proposal.Plan
	if len(plan) == 0 && proposal.Proposal != nil {
		plan = []aiCommandPlanStep{{
			Step:       1,
			Summary:    proposal.Summary,
			Action:     proposal.Proposal.Action,
			TargetType: proposal.Proposal.TargetType,
			TargetIDs:  proposal.Proposal.TargetIDs,
			Patch:      proposal.Proposal.Patch,
			Reason:     proposal.Proposal.Reason,
			RiskLevel:  proposal.Proposal.RiskLevel,
		}}
	}
	proposalJSON, err := json.Marshal(plan)
	if err != nil {
		return aiCommandConfirmationPayload{}, internal(err.Error())
	}
	proposalHashBytes := sha256.Sum256(proposalJSON)
	proposalHash := hex.EncodeToString(proposalHashBytes[:])
	now := time.Now().UTC()
	expiresAt := now.Add(s.app.cfg.AIConfirmTTL)
	tokenID := base64.RawURLEncoding.EncodeToString(proposalHashBytes[:12])
	action := "multi_action_plan"
	targetType := "none"
	targetIDs := []string{}
	if len(plan) == 1 {
		action = plan[0].Action
		targetType = plan[0].TargetType
		targetIDs = plan[0].TargetIDs
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, aiCommandConfirmationClaims{
		Intent:        proposal.Intent,
		OperationType: proposal.OperationType,
		Action:        action,
		TargetType:    targetType,
		TargetIDs:     targetIDs,
		ProposalHash:  proposalHash,
		StepCount:     len(plan),
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			ID:        tokenID,
		},
	})
	signed, err := token.SignedString([]byte(s.confirmationSecret()))
	if err != nil {
		return aiCommandConfirmationPayload{}, internal(err.Error())
	}
	targetIDsJSON, err := json.Marshal(targetIDs)
	if err != nil {
		return aiCommandConfirmationPayload{}, internal(err.Error())
	}
	patchPayload := map[string]any{}
	if proposal.Proposal != nil {
		patchPayload = proposal.Proposal.Patch
	}
	patchJSON, err := json.Marshal(patchPayload)
	if err != nil {
		return aiCommandConfirmationPayload{}, internal(err.Error())
	}
	planJSON, err := json.Marshal(plan)
	if err != nil {
		return aiCommandConfirmationPayload{}, internal(err.Error())
	}
	recordNow := now.Format(time.RFC3339)
	record := models.AICommandConfirmation{
		ID:            newID(),
		UserID:        userID,
		TokenID:       tokenID,
		Intent:        proposal.Intent,
		OperationType: proposal.OperationType,
		Action:        action,
		TargetType:    targetType,
		TargetIDsJSON: string(targetIDsJSON),
		PatchJSON:     string(patchJSON),
		PlanJSON:      string(planJSON),
		ProposalHash:  proposalHash,
		ExpiresAt:     expiresAt.Format(time.RFC3339),
		CreatedAt:     recordNow,
		UpdatedAt:     recordNow,
	}
	if err := s.app.db.Create(&record).Error; err != nil {
		return aiCommandConfirmationPayload{}, err
	}
	return aiCommandConfirmationPayload{
		Token:     signed,
		ExpiresAt: expiresAt.Format(time.RFC3339),
	}, nil
}

func (s aiCommandService) validateConfirmationToken(token string) (*aiCommandConfirmationClaims, models.AICommandConfirmation, error) {
	parsed, err := jwt.ParseWithClaims(token, &aiCommandConfirmationClaims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(s.confirmationSecret()), nil
	})
	if err != nil {
		return nil, models.AICommandConfirmation{}, badRequest("confirmation token 无效")
	}
	typed, ok := parsed.Claims.(*aiCommandConfirmationClaims)
	if !ok || !parsed.Valid {
		return nil, models.AICommandConfirmation{}, badRequest("confirmation token 无效")
	}
	var record models.AICommandConfirmation
	if err := s.app.db.Where("token_id = ?", typed.ID).First(&record).Error; err != nil {
		return nil, models.AICommandConfirmation{}, badRequest("confirmation token 不存在")
	}
	if record.ConsumedAt != nil {
		return nil, models.AICommandConfirmation{}, conflict(40903, "confirmation token 已使用")
	}
	expiresAt, err := parseRFC3339Time(record.ExpiresAt)
	if err != nil || expiresAt.Before(time.Now().UTC()) {
		return nil, models.AICommandConfirmation{}, badRequest("confirmation token 已过期")
	}
	if record.ProposalHash != typed.ProposalHash {
		return nil, models.AICommandConfirmation{}, badRequest("confirmation token 校验失败")
	}
	return typed, record, nil
}

func (s aiCommandService) executePlan(userID string, record models.AICommandConfirmation) ([]any, error) {
	plan, err := s.readPlan(record)
	if err != nil {
		return nil, err
	}
	log.Printf("[AIService] execute_plan user_id=%s steps=%d token_id=%s", userID, len(plan), record.TokenID)
	results := make([]any, 0, len(plan))
	for _, step := range plan {
		result, err := s.executeStep(userID, step)
		if err != nil {
			return nil, err
		}
		results = append(results, result)
	}
	return results, nil
}

func (s aiCommandService) executeStep(userID string, step aiCommandPlanStep) (any, error) {
	log.Printf(
		"[AIService] execute_step user_id=%s step=%d action=%s target_type=%s target_ids=%v patch=%v",
		userID,
		step.Step,
		step.Action,
		step.TargetType,
		step.TargetIDs,
		step.Patch,
	)
	switch step.Action {
	case "delete_reminder":
		if len(step.TargetIDs) == 0 {
			return nil, badRequest("delete_reminder 目标不能为空")
		}
		deletedIDs := make([]string, 0, len(step.TargetIDs))
		for _, reminderID := range step.TargetIDs {
			if err := newReminderService(s.app).delete(userID, reminderID); err != nil {
				return nil, err
			}
			deletedIDs = append(deletedIDs, reminderID)
		}
		return map[string]any{"deleted": true, "reminder_ids": deletedIDs, "step": step.Step}, nil
	case "complete_reminder":
		if len(step.TargetIDs) == 0 {
			return nil, badRequest("complete_reminder 目标不能为空")
		}
		items := make([]any, 0, len(step.TargetIDs))
		for _, reminderID := range step.TargetIDs {
			item, err := newReminderService(s.app).complete(userID, reminderID)
			if err != nil {
				return nil, err
			}
			items = append(items, item)
		}
		return items, nil
	case "uncomplete_reminder":
		if len(step.TargetIDs) == 0 {
			return nil, badRequest("uncomplete_reminder 目标不能为空")
		}
		items := make([]any, 0, len(step.TargetIDs))
		for _, reminderID := range step.TargetIDs {
			item, err := newReminderService(s.app).uncomplete(userID, reminderID)
			if err != nil {
				return nil, err
			}
			items = append(items, item)
		}
		return items, nil
	case "create_reminder":
		payload, err := s.buildCreateReminderPayload(userID, step)
		if err != nil {
			return nil, err
		}
		return newReminderService(s.app).create(userID, payload)
	case "update_reminder":
		if len(step.TargetIDs) > 1 {
			items := make([]any, 0, len(step.TargetIDs))
			for _, reminderID := range step.TargetIDs {
				payload, err := s.buildUpdateReminderPayloadForTarget(step, reminderID)
				if err != nil {
					return nil, err
				}
				item, err := newReminderService(s.app).patch(userID, reminderID, payload)
				if err != nil {
					return nil, err
				}
				items = append(items, item)
			}
			return items, nil
		}
		if len(step.TargetIDs) != 1 {
			return nil, badRequest("update_reminder 目标数量异常")
		}
		payload, err := s.buildUpdateReminderPayload(step)
		if err != nil {
			return nil, err
		}
		return newReminderService(s.app).patch(userID, step.TargetIDs[0], payload)
	default:
		return nil, badRequest("当前 action 暂不支持执行")
	}
}

func (s aiCommandService) readPlan(record models.AICommandConfirmation) ([]aiCommandPlanStep, error) {
	if strings.TrimSpace(record.PlanJSON) == "" {
		return nil, badRequest("confirmation plan 为空")
	}
	var plan []aiCommandPlanStep
	if err := json.Unmarshal([]byte(record.PlanJSON), &plan); err != nil {
		return nil, badRequest("confirmation plan 无法解析")
	}
	if len(plan) == 0 {
		return nil, badRequest("confirmation plan 为空")
	}
	return plan, nil
}

func (s aiCommandService) buildUpdateReminderPayload(step aiCommandPlanStep) (updateReminderPayload, error) {
	var payload updateReminderPayload
	normalizedPatch := normalizeAICommandPatch(step.Patch)
	patchJSON, err := json.Marshal(normalizedPatch)
	if err != nil {
		return updateReminderPayload{}, badRequest("update_reminder patch 无法编码")
	}
	if len(normalizedPatch) == 0 {
		return updateReminderPayload{}, badRequest("update_reminder patch 为空")
	}
	if err := json.Unmarshal(patchJSON, &payload); err != nil {
		return updateReminderPayload{}, badRequest("update_reminder patch 无法解析")
	}
	return payload, nil
}

func (s aiCommandService) buildUpdateReminderPayloadForTarget(step aiCommandPlanStep, reminderID string) (updateReminderPayload, error) {
	if len(step.Patch) == 0 {
		return updateReminderPayload{}, badRequest("update_reminder patch 为空")
	}
	patch := cloneAICommandPatch(step.Patch)
	if dueAtByID, ok := step.Patch["dueAtById"].(map[string]any); ok {
		value, exists := dueAtByID[reminderID]
		if !exists {
			return updateReminderPayload{}, badRequest("update_reminder 缺少目标时间")
		}
		patch["dueAt"] = value
		delete(patch, "dueAtById")
	}
	return s.buildUpdateReminderPayload(aiCommandPlanStep{
		Step:       step.Step,
		Summary:    step.Summary,
		Action:     step.Action,
		TargetType: step.TargetType,
		TargetIDs:  []string{reminderID},
		Patch:      patch,
		Reason:     step.Reason,
		RiskLevel:  step.RiskLevel,
	})
}

func (s aiCommandService) buildCreateReminderPayload(userID string, step aiCommandPlanStep) (reminderPayload, error) {
	normalizedPatch := normalizeAICommandPatch(step.Patch)
	patchJSON, err := json.Marshal(normalizedPatch)
	if err != nil {
		return reminderPayload{}, badRequest("create_reminder patch 无法编码")
	}
	var payload reminderPayload
	if err := json.Unmarshal(patchJSON, &payload); err != nil {
		return reminderPayload{}, badRequest("create_reminder patch 无法解析")
	}
	if strings.TrimSpace(payload.ListID) == "" || strings.TrimSpace(payload.GroupID) == "" {
		defaultListID, defaultGroupID, err := s.loadDefaultReminderContainerIDs(userID)
		if err != nil {
			return reminderPayload{}, err
		}
		if strings.TrimSpace(payload.ListID) == "" {
			payload.ListID = defaultListID
		}
		if strings.TrimSpace(payload.GroupID) == "" {
			payload.GroupID = defaultGroupID
		}
	}
	return payload, nil
}

func normalizeAICommandPatch(patch map[string]any) map[string]any {
	if len(patch) == 0 {
		return patch
	}
	normalized := make(map[string]any, len(patch))
	for key, value := range patch {
		switch key {
		case "dueAt", "time", "scheduledAt", "datetime":
			normalized["due_at"] = value
		case "repeat", "recurrence":
			normalized["repeat_rule"] = normalizeAICommandRepeatRuleValue(value)
		case "repeatUntilAt":
			normalized["repeat_until_at"] = value
		case "remindBeforeMinutes":
			normalized["remind_before_minutes"] = value
		case "listId":
			normalized["list_id"] = value
		case "groupId":
			normalized["group_id"] = value
		case "tagIds":
			normalized["tag_ids"] = value
		case "notificationEnabled":
			normalized["notification_enabled"] = value
		case "repeatRule":
			normalized["repeat_rule"] = normalizeAICommandRepeatRuleValue(value)
		case "isCompleted":
			normalized["is_completed"] = value
		default:
			normalized[key] = value
		}
	}
	log.Printf("[AIService] normalize_patch input=%v output=%v", patch, normalized)
	return normalized
}

func normalizeAICommandRepeatRuleValue(value any) any {
	raw := strings.TrimSpace(fmt.Sprint(value))
	switch raw {
	case "", "不重复", "none", "None", "no_repeat":
		return "none"
	case "每天", "每日", "daily", "every_day", "everyday":
		return "daily"
	case "每周", "weekly", "every_week":
		return "weekly"
	case "每月", "monthly", "every_month":
		return "monthly"
	case "每年", "每年一次", "yearly", "every_year":
		return "yearly"
	case "工作日", "每个工作日", "workday", "weekdays":
		return "workday"
	case "休息日", "非工作日", "周末", "non_workday", "weekends":
		return "non_workday"
	default:
		return value
	}
}

func cloneAICommandPatch(patch map[string]any) map[string]any {
	cloned := make(map[string]any, len(patch))
	for key, value := range patch {
		cloned[key] = value
	}
	return cloned
}

func (s aiCommandService) loadDefaultReminderContainerIDs(userID string) (string, string, error) {
	lists, err := newResourceService(s.app).listLists(userID)
	if err != nil {
		return "", "", err
	}
	groups, err := newResourceService(s.app).listGroups(userID)
	if err != nil {
		return "", "", err
	}
	if len(lists) == 0 || len(groups) == 0 {
		return "", "", badRequest("缺少默认清单或分组，无法创建提醒")
	}
	return lists[0].ID, groups[0].ID, nil
}

func (s aiCommandService) confirmationSecret() string {
	return s.app.cfg.JWTAccessSecret + ":ai-confirm"
}

type emptyQueryProvider struct{}

func (emptyQueryProvider) Query(string) string        { return "" }
func (emptyQueryProvider) QueryArray(string) []string { return nil }
