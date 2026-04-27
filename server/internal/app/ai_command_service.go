package app

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"nexdo-server-golang/internal/models"

	"github.com/golang-jwt/jwt/v5"
)

type aiCommandService struct {
	app        *Application
	httpClient *http.Client
}

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
	user, err := s.app.requireUser(userID)
	if err != nil {
		return aiCommandResolveResponse{}, err
	}
	timezone := strings.TrimSpace(user.Timezone)
	if timezone == "" {
		timezone = "Asia/Shanghai"
	}
	now := nowISO()

	classification, err := s.classify(aiCommandClassifyRequest{
		UserInput: input,
		Timezone:  timezone,
		Now:       now,
	})
	if err != nil {
		return aiCommandResolveResponse{}, err
	}

	context, summary, err := s.loadContext(userID, classification.Intent)
	if err != nil {
		return aiCommandResolveResponse{}, err
	}

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
		confirmation, err := s.issueConfirmationToken(userID, proposal)
		if err != nil {
			return aiCommandResolveResponse{}, err
		}
		response.Confirmation = &confirmation
	}

	return response, nil
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

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return internal("AI service request failed: " + err.Error())
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return internal(err.Error())
	}

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
		return aiCommandContextPayload{}, aiCommandContextSummary{}, nil
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

	result := aiCommandContextPayload{
		Reminders: make([]aiCommandReminderCandidate, 0, len(reminders)),
		Lists:     make([]aiCommandResourceCandidate, 0, len(lists)),
		Groups:    make([]aiCommandResourceCandidate, 0, len(groups)),
		Tags:      make([]aiCommandResourceCandidate, 0, len(tags)),
	}
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
	result := aiCommandContextPayload{
		QuickNotes: make([]aiCommandQuickNoteCandidate, 0, len(items)),
	}
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
	result := aiCommandContextPayload{
		Lists:  make([]aiCommandResourceCandidate, 0, len(lists)),
		Groups: make([]aiCommandResourceCandidate, 0, len(groups)),
		Tags:   make([]aiCommandResourceCandidate, 0, len(tags)),
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
		payload, err := s.buildCreateReminderPayload(step)
		if err != nil {
			return nil, err
		}
		return newReminderService(s.app).create(userID, payload)
	case "update_reminder":
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
	patchJSON, err := json.Marshal(step.Patch)
	if err != nil {
		return updateReminderPayload{}, badRequest("update_reminder patch 无法编码")
	}
	if len(step.Patch) == 0 {
		return updateReminderPayload{}, badRequest("update_reminder patch 为空")
	}
	if err := json.Unmarshal(patchJSON, &payload); err != nil {
		return updateReminderPayload{}, badRequest("update_reminder patch 无法解析")
	}
	return payload, nil
}

func (s aiCommandService) buildCreateReminderPayload(step aiCommandPlanStep) (reminderPayload, error) {
	patchJSON, err := json.Marshal(step.Patch)
	if err != nil {
		return reminderPayload{}, badRequest("create_reminder patch 无法编码")
	}
	var payload reminderPayload
	if err := json.Unmarshal(patchJSON, &payload); err != nil {
		return reminderPayload{}, badRequest("create_reminder patch 无法解析")
	}
	return payload, nil
}

func (s aiCommandService) confirmationSecret() string {
	return s.app.cfg.JWTAccessSecret + ":ai-confirm"
}

type emptyQueryProvider struct{}

func (emptyQueryProvider) Query(string) string        { return "" }
func (emptyQueryProvider) QueryArray(string) []string { return nil }
