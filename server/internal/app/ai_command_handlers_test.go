package app

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"nexdo-server-golang/internal/config"
)

func TestResolveAICommandRequiresConfirmationForWrite(t *testing.T) {
	t.Parallel()

	var reminderID string
	mockAI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/commands/classify":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"classification": map[string]any{
					"intent":                "reminder.delete",
					"operationType":         "write_requires_confirmation",
					"confidence":            0.97,
					"summary":               "用户要删除一个提醒",
					"missingSlots":          []string{},
					"entities":              map[string]any{"title": "产品会议"},
					"nextStep":              "load_context",
					"clarificationQuestion": nil,
				},
			})
		case "/api/commands/propose":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"proposal": map[string]any{
					"status":                "confirmation_required",
					"intent":                "reminder.delete",
					"operationType":         "write_requires_confirmation",
					"requiresConfirmation":  true,
					"summary":               "准备删除提醒",
					"userMessage":           "请确认是否删除该提醒",
					"missingSlots":          []string{},
					"answer":                nil,
					"clarificationQuestion": nil,
					"confirmationMessage":   "确认删除提醒「产品会议」吗？",
					"proposal": map[string]any{
						"action":     "delete_reminder",
						"targetType": "reminder",
						"targetIds":  []string{reminderID},
						"patch":      map[string]any{},
						"reason":     "标题唯一匹配",
						"riskLevel":  "medium",
					},
					"candidates": []any{},
				},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer mockAI.Close()

	app := newTestAppWithAIBaseURL(t, mockAI.URL)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"产品会议",
		"due_at":"2026-04-28T15:00:00+08:00",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`"
	}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create reminder status = %d, body = %s", createRec.Code, createRec.Body.String())
	}
	var created struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)
	reminderID = created.Data.ID

	rec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/resolve", token, `{"input":"把产品会议提醒删掉"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("resolve status = %d, body = %s", rec.Code, rec.Body.String())
	}

	var payload struct {
		Data aiCommandResolveResponse `json:"data"`
	}
	decodeBody(t, rec.Body.Bytes(), &payload)

	if payload.Data.Mode != "confirmation_required" {
		t.Fatalf("expected confirmation_required, got %+v", payload.Data)
	}
	if payload.Data.Confirmation == nil || strings.TrimSpace(payload.Data.Confirmation.Token) == "" {
		t.Fatalf("expected confirmation token, got %+v", payload.Data.Confirmation)
	}
	if payload.Data.Result.Proposal == nil || payload.Data.Result.Proposal.Action != "delete_reminder" {
		t.Fatalf("expected delete proposal, got %+v", payload.Data.Result.Proposal)
	}
	if len(payload.Data.Result.Plan) != 1 {
		t.Fatalf("expected synthetic confirmation plan, got %+v", payload.Data.Result.Plan)
	}
	if len(payload.Data.Result.Plan[0].PreviewItems) != 1 {
		t.Fatalf("expected one preview item, got %+v", payload.Data.Result.Plan[0].PreviewItems)
	}
	if payload.Data.Result.Plan[0].PreviewItems[0].Before["标题"] != "产品会议" {
		t.Fatalf("unexpected preview before payload: %+v", payload.Data.Result.Plan[0].PreviewItems[0])
	}
	if payload.Data.Result.Plan[0].PreviewItems[0].After["状态"] != "已删除" {
		t.Fatalf("unexpected preview after payload: %+v", payload.Data.Result.Plan[0].PreviewItems[0])
	}
	if payload.Data.ContextSummary.RemindersLoaded == 0 {
		t.Fatalf("expected reminders to be loaded, got %+v", payload.Data.ContextSummary)
	}

	verifyRec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/confirmations/verify", token, `{"token":"`+payload.Data.Confirmation.Token+`"}`)
	if verifyRec.Code != http.StatusOK {
		t.Fatalf("verify status = %d, body = %s", verifyRec.Code, verifyRec.Body.String())
	}

	var verifyPayload struct {
		Data aiCommandVerifyResponse `json:"data"`
	}
	decodeBody(t, verifyRec.Body.Bytes(), &verifyPayload)
	if !verifyPayload.Data.Valid {
		t.Fatalf("expected valid confirmation token, got %+v", verifyPayload.Data)
	}
	if verifyPayload.Data.Claims.Action != "delete_reminder" {
		t.Fatalf("unexpected confirmation claims: %+v", verifyPayload.Data.Claims)
	}

	executeRec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/confirmations/execute", token, `{"token":"`+payload.Data.Confirmation.Token+`"}`)
	if executeRec.Code != http.StatusOK {
		t.Fatalf("execute status = %d, body = %s", executeRec.Code, executeRec.Body.String())
	}

	var executePayload struct {
		Data aiCommandExecuteResponse `json:"data"`
	}
	decodeBody(t, executeRec.Body.Bytes(), &executePayload)
	if !executePayload.Data.Executed || executePayload.Data.Action != "delete_reminder" {
		t.Fatalf("unexpected execute payload: %+v", executePayload.Data)
	}

	getDeletedRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders/"+reminderID, token, "")
	if getDeletedRec.Code != http.StatusNotFound {
		t.Fatalf("expected reminder to be deleted, got %d body=%s", getDeletedRec.Code, getDeletedRec.Body.String())
	}

	replayRec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/confirmations/execute", token, `{"token":"`+payload.Data.Confirmation.Token+`"}`)
	if replayRec.Code != http.StatusConflict {
		t.Fatalf("expected replay conflict, got %d body=%s", replayRec.Code, replayRec.Body.String())
	}
}

func TestResolveAICommandReturnsReadOnlyAnswer(t *testing.T) {
	t.Parallel()

	mockAI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/commands/classify":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"classification": map[string]any{
					"intent":                "reminder.query",
					"operationType":         "read_only",
					"confidence":            0.98,
					"summary":               "查询今天提醒",
					"missingSlots":          []string{},
					"entities":              map[string]any{"date": "今天"},
					"nextStep":              "load_context",
					"clarificationQuestion": nil,
				},
			})
		case "/api/commands/propose":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"proposal": map[string]any{
					"status":                "read_only_answer",
					"intent":                "reminder.query",
					"operationType":         "read_only",
					"requiresConfirmation":  false,
					"summary":               "今天有 1 条提醒",
					"userMessage":           "今天有 1 条提醒：产品会议（15:00）",
					"missingSlots":          []string{},
					"answer":                "今天有 1 条提醒：产品会议（15:00）",
					"clarificationQuestion": nil,
					"confirmationMessage":   nil,
					"proposal": map[string]any{
						"action":     "query_reminders",
						"targetType": "reminder",
						"targetIds":  []string{"rmd_123"},
						"patch":      map[string]any{},
						"reason":     "只读查询",
						"riskLevel":  "low",
					},
					"candidates": []any{},
				},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer mockAI.Close()

	app := newTestAppWithAIBaseURL(t, mockAI.URL)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"产品会议",
		"due_at":"2026-04-27T15:00:00+08:00",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`"
	}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create reminder status = %d, body = %s", createRec.Code, createRec.Body.String())
	}

	rec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/resolve", token, `{"input":"今天有哪些提醒？"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("resolve status = %d, body = %s", rec.Code, rec.Body.String())
	}

	var payload struct {
		Data aiCommandResolveResponse `json:"data"`
	}
	decodeBody(t, rec.Body.Bytes(), &payload)

	if payload.Data.Mode != "read_only_answer" {
		t.Fatalf("expected read_only_answer, got %+v", payload.Data)
	}
	if payload.Data.Confirmation != nil {
		t.Fatalf("expected no confirmation token, got %+v", payload.Data.Confirmation)
	}
	if payload.Data.Result.Answer == nil || !strings.Contains(*payload.Data.Result.Answer, "产品会议") {
		t.Fatalf("expected read-only answer, got %+v", payload.Data.Result)
	}
}

func TestExecuteAIConfirmationUpdatesReminder(t *testing.T) {
	t.Parallel()

	var reminderID string
	mockAI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/commands/classify":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"classification": map[string]any{
					"intent":                "reminder.update",
					"operationType":         "write_requires_confirmation",
					"confidence":            0.96,
					"summary":               "用户要修改提醒时间",
					"missingSlots":          []string{},
					"entities":              map[string]any{"title": "产品会议", "due_at": "明天下午四点"},
					"nextStep":              "load_context",
					"clarificationQuestion": nil,
				},
			})
		case "/api/commands/propose":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"proposal": map[string]any{
					"status":                "confirmation_required",
					"intent":                "reminder.update",
					"operationType":         "write_requires_confirmation",
					"requiresConfirmation":  true,
					"summary":               "准备修改提醒时间",
					"userMessage":           "请确认是否将提醒改到 16:00",
					"missingSlots":          []string{},
					"answer":                nil,
					"clarificationQuestion": nil,
					"confirmationMessage":   "确认将提醒改到 2026-04-28T16:00:00+08:00 吗？",
					"proposal": map[string]any{
						"action":     "update_reminder",
						"targetType": "reminder",
						"targetIds":  []string{reminderID},
						"patch": map[string]any{
							"due_at": "2026-04-28T16:00:00+08:00",
						},
						"reason":    "匹配到唯一提醒并修改时间",
						"riskLevel": "medium",
					},
					"candidates": []any{},
				},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer mockAI.Close()

	app := newTestAppWithAIBaseURL(t, mockAI.URL)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"产品会议",
		"due_at":"2026-04-28T15:00:00+08:00",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`"
	}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create reminder status = %d, body = %s", createRec.Code, createRec.Body.String())
	}
	var created struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)
	reminderID = created.Data.ID

	rec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/resolve", token, `{"input":"把产品会议提醒改到明天下午四点"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("resolve status = %d, body = %s", rec.Code, rec.Body.String())
	}

	var payload struct {
		Data aiCommandResolveResponse `json:"data"`
	}
	decodeBody(t, rec.Body.Bytes(), &payload)
	if len(payload.Data.Result.Plan) != 1 || len(payload.Data.Result.Plan[0].PreviewItems) != 1 {
		t.Fatalf("expected update preview items, got %+v", payload.Data.Result.Plan)
	}
	preview := payload.Data.Result.Plan[0].PreviewItems[0]
	if preview.Before["时间"] != "2026-04-28T15:00:00+08:00" {
		t.Fatalf("unexpected update preview before: %+v", preview)
	}
	if preview.After["时间"] != "2026-04-28T16:00:00+08:00" {
		t.Fatalf("unexpected update preview after: %+v", preview)
	}

	executeRec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/confirmations/execute", token, `{"token":"`+payload.Data.Confirmation.Token+`"}`)
	if executeRec.Code != http.StatusOK {
		t.Fatalf("execute status = %d, body = %s", executeRec.Code, executeRec.Body.String())
	}

	getRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders/"+reminderID, token, "")
	if getRec.Code != http.StatusOK {
		t.Fatalf("get reminder status = %d, body = %s", getRec.Code, getRec.Body.String())
	}
	var getPayload struct {
		Data struct {
			DueAt string `json:"due_at"`
		} `json:"data"`
	}
	decodeBody(t, getRec.Body.Bytes(), &getPayload)
	if getPayload.Data.DueAt != "2026-04-28T16:00:00+08:00" {
		t.Fatalf("expected reminder due_at updated, got %+v", getPayload.Data)
	}
}

func TestExecuteAIConfirmationCreatesReminderWithAliasPatchFields(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name       string
		patchField string
	}{
		{name: "scheduledAt alias", patchField: "scheduledAt"},
		{name: "datetime alias", patchField: "datetime"},
		{name: "time alias", patchField: "time"},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			var listID string
			var groupID string
			mockAI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				switch r.URL.Path {
				case "/api/commands/classify":
					_ = json.NewEncoder(w).Encode(map[string]any{
						"ok": true,
						"classification": map[string]any{
							"intent":                "reminder.create",
							"operationType":         "write_requires_confirmation",
							"confidence":            0.97,
							"summary":               "用户要创建提醒",
							"missingSlots":          []string{},
							"entities":              map[string]any{"title": "产品会议"},
							"nextStep":              "load_context",
							"clarificationQuestion": nil,
						},
					})
				case "/api/commands/propose":
					_ = json.NewEncoder(w).Encode(map[string]any{
						"ok": true,
						"proposal": map[string]any{
							"status":                "confirmation_required",
							"intent":                "reminder.create",
							"operationType":         "write_requires_confirmation",
							"requiresConfirmation":  true,
							"summary":               "准备创建提醒",
							"userMessage":           "请确认是否创建提醒",
							"missingSlots":          []string{},
							"answer":                nil,
							"clarificationQuestion": nil,
							"confirmationMessage":   "确认创建提醒吗？",
							"proposal": map[string]any{
								"action":     "create_reminder",
								"targetType": "reminder",
								"targetIds":  []string{},
								"patch": map[string]any{
									"title":       "产品会议",
									tc.patchField: "2026-04-28T09:00:00+08:00",
									"listId":      listID,
									"groupId":     groupID,
								},
								"reason":    "测试时间字段别名兼容",
								"riskLevel": "low",
							},
							"candidates": []any{},
						},
					})
				default:
					http.NotFound(w, r)
				}
			}))
			defer mockAI.Close()

			app := newTestAppWithAIBaseURL(t, mockAI.URL)
			token := registerTestUser(t, app)
			listID, groupID = firstListAndGroupIDs(t, app, token)

			resolveRec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/resolve", token, `{"input":"明天早上九点提醒我开产品会议"}`)
			if resolveRec.Code != http.StatusOK {
				t.Fatalf("resolve status = %d, body = %s", resolveRec.Code, resolveRec.Body.String())
			}
			var resolvePayload struct {
				Data aiCommandResolveResponse `json:"data"`
			}
			decodeBody(t, resolveRec.Body.Bytes(), &resolvePayload)

			executeRec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/confirmations/execute", token, `{"token":"`+resolvePayload.Data.Confirmation.Token+`"}`)
			if executeRec.Code != http.StatusOK {
				t.Fatalf("execute status = %d, body = %s", executeRec.Code, executeRec.Body.String())
			}

			listRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders", token, "")
			if listRec.Code != http.StatusOK {
				t.Fatalf("list status = %d, body = %s", listRec.Code, listRec.Body.String())
			}
			var listPayload struct {
				Data []struct {
					Title   string `json:"title"`
					DueAt   string `json:"due_at"`
					ListID  string `json:"list_id"`
					GroupID string `json:"group_id"`
				} `json:"data"`
			}
			decodeBody(t, listRec.Body.Bytes(), &listPayload)
			if len(listPayload.Data) != 1 {
				t.Fatalf("expected 1 reminder, got %+v", listPayload.Data)
			}
			if listPayload.Data[0].DueAt != "2026-04-28T09:00:00+08:00" {
				t.Fatalf("expected due_at normalized, got %+v", listPayload.Data[0])
			}
			if listPayload.Data[0].ListID != listID || listPayload.Data[0].GroupID != groupID {
				t.Fatalf("expected list/group ids preserved, got %+v", listPayload.Data[0])
			}
		})
	}
}

func TestExecuteAIConfirmationBatchUpdatesRemindersWithDueAtByID(t *testing.T) {
	t.Parallel()

	var reminderIDs []string
	mockAI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/commands/classify":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"classification": map[string]any{
					"intent":                "reminder.update",
					"operationType":         "write_requires_confirmation",
					"confidence":            0.96,
					"summary":               "用户要批量顺延提醒",
					"missingSlots":          []string{},
					"entities":              map[string]any{"scope": "明天全部提醒", "targetDate": "后天"},
					"nextStep":              "load_context",
					"clarificationQuestion": nil,
				},
			})
		case "/api/commands/propose":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"proposal": map[string]any{
					"status":                "confirmation_required",
					"intent":                "reminder.update",
					"operationType":         "write_requires_confirmation",
					"requiresConfirmation":  true,
					"summary":               "准备批量顺延提醒",
					"userMessage":           "请确认批量顺延",
					"missingSlots":          []string{},
					"answer":                nil,
					"clarificationQuestion": nil,
					"confirmationMessage":   "确认将提醒移到后天吗？",
					"proposal": map[string]any{
						"action":     "update_reminder",
						"targetType": "reminder",
						"targetIds":  reminderIDs,
						"patch": map[string]any{
							"dueAtById": map[string]any{
								reminderIDs[0]: "2026-04-29T09:00:00+08:00",
								reminderIDs[1]: "2026-04-29T14:00:00+08:00",
								reminderIDs[2]: "2026-04-29T21:00:00+08:00",
							},
							"sourceDate":   "2026-04-28",
							"targetDate":   "2026-04-29",
							"preserveTime": true,
						},
						"reason":    "测试批量更新时间",
						"riskLevel": "medium",
					},
					"plan": []map[string]any{
						{
							"step":       1,
							"summary":    "批量顺延提醒",
							"action":     "update_reminder",
							"targetType": "reminder",
							"targetIds":  reminderIDs,
							"patch": map[string]any{
								"dueAtById": map[string]any{
									reminderIDs[0]: "2026-04-29T09:00:00+08:00",
									reminderIDs[1]: "2026-04-29T14:00:00+08:00",
									reminderIDs[2]: "2026-04-29T21:00:00+08:00",
								},
								"sourceDate":   "2026-04-28",
								"targetDate":   "2026-04-29",
								"preserveTime": true,
							},
							"reason":    "测试批量更新时间",
							"riskLevel": "medium",
						},
					},
					"candidates": []any{},
				},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer mockAI.Close()

	app := newTestAppWithAIBaseURL(t, mockAI.URL)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	for _, item := range []struct {
		title string
		dueAt string
	}{
		{title: "产品会议", dueAt: "2026-04-28T09:00:00+08:00"},
		{title: "客户沟通", dueAt: "2026-04-28T14:00:00+08:00"},
		{title: "约会", dueAt: "2026-04-28T21:00:00+08:00"},
	} {
		rec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
			"title":"`+item.title+`",
			"due_at":"`+item.dueAt+`",
			"list_id":"`+listID+`",
			"group_id":"`+groupID+`"
		}`)
		if rec.Code != http.StatusCreated {
			t.Fatalf("create reminder status = %d, body = %s", rec.Code, rec.Body.String())
		}
		var payload struct {
			Data struct {
				ID string `json:"id"`
			} `json:"data"`
		}
		decodeBody(t, rec.Body.Bytes(), &payload)
		reminderIDs = append(reminderIDs, payload.Data.ID)
	}

	resolveRec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/resolve", token, `{"input":"把明天所有的行程移到后天，明天我要休息"}`)
	if resolveRec.Code != http.StatusOK {
		t.Fatalf("resolve status = %d, body = %s", resolveRec.Code, resolveRec.Body.String())
	}
	var resolvePayload struct {
		Data aiCommandResolveResponse `json:"data"`
	}
	decodeBody(t, resolveRec.Body.Bytes(), &resolvePayload)

	executeRec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/confirmations/execute", token, `{"token":"`+resolvePayload.Data.Confirmation.Token+`"}`)
	if executeRec.Code != http.StatusOK {
		t.Fatalf("execute status = %d, body = %s", executeRec.Code, executeRec.Body.String())
	}

	listRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders", token, "")
	if listRec.Code != http.StatusOK {
		t.Fatalf("list status = %d, body = %s", listRec.Code, listRec.Body.String())
	}
	var listPayload struct {
		Data []struct {
			ID    string `json:"id"`
			DueAt string `json:"due_at"`
		} `json:"data"`
	}
	decodeBody(t, listRec.Body.Bytes(), &listPayload)
	gotDueAtByID := map[string]string{}
	for _, item := range listPayload.Data {
		gotDueAtByID[item.ID] = item.DueAt
	}
	expected := map[string]string{
		reminderIDs[0]: "2026-04-29T09:00:00+08:00",
		reminderIDs[1]: "2026-04-29T14:00:00+08:00",
		reminderIDs[2]: "2026-04-29T21:00:00+08:00",
	}
	for id, dueAt := range expected {
		if gotDueAtByID[id] != dueAt {
			t.Fatalf("expected reminder %s due_at=%s, got %s", id, dueAt, gotDueAtByID[id])
		}
	}
}

func TestExecuteAIConfirmationRunsMultiActionPlan(t *testing.T) {
	t.Parallel()

	var firstReminderID string
	var secondReminderID string
	var listID string
	var groupID string

	mockAI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/commands/classify":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"classification": map[string]any{
					"intent":                "reminder.delete",
					"operationType":         "write_requires_confirmation",
					"confidence":            0.95,
					"summary":               "用户要执行复合提醒操作",
					"missingSlots":          []string{},
					"entities":              map[string]any{"date": "今天", "title": "约会"},
					"nextStep":              "load_context",
					"clarificationQuestion": nil,
				},
			})
		case "/api/commands/propose":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"proposal": map[string]any{
					"status":                "confirmation_required",
					"intent":                "reminder.delete",
					"operationType":         "write_requires_confirmation",
					"requiresConfirmation":  true,
					"summary":               "准备删除今天所有提醒，并新增约会提醒",
					"userMessage":           "请确认先删除今天所有提醒，再新增晚上九点的约会提醒。",
					"missingSlots":          []string{},
					"answer":                nil,
					"clarificationQuestion": nil,
					"confirmationMessage":   "确认删除 2 条今天的提醒，并新增一条 21:00 的约会提醒吗？",
					"proposal": map[string]any{
						"action":     "delete_reminder",
						"targetType": "reminder",
						"targetIds":  []string{firstReminderID, secondReminderID},
						"patch":      map[string]any{},
						"reason":     "第一步先清理今天所有提醒",
						"riskLevel":  "high",
					},
					"plan": []map[string]any{
						{
							"step":       1,
							"summary":    "删除今天所有提醒",
							"action":     "delete_reminder",
							"targetType": "reminder",
							"targetIds":  []string{firstReminderID, secondReminderID},
							"patch":      map[string]any{},
							"reason":     "用户要求取消今天所有提醒",
							"riskLevel":  "high",
						},
						{
							"step":       2,
							"summary":    "新增晚上九点的约会提醒",
							"action":     "create_reminder",
							"targetType": "reminder",
							"targetIds":  []string{},
							"patch": map[string]any{
								"title":    "约会",
								"due_at":   "2026-04-27T21:00:00+08:00",
								"list_id":  listID,
								"group_id": groupID,
							},
							"reason":    "用户要求新增一条今晚九点的约会提醒",
							"riskLevel": "medium",
						},
					},
					"candidates": []any{},
				},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer mockAI.Close()

	app := newTestAppWithAIBaseURL(t, mockAI.URL)
	token := registerTestUser(t, app)
	listID, groupID = firstListAndGroupIDs(t, app, token)

	createFirstRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"今天一号提醒",
		"due_at":"2026-04-27T10:00:00+08:00",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`"
	}`)
	if createFirstRec.Code != http.StatusCreated {
		t.Fatalf("create first reminder status = %d, body = %s", createFirstRec.Code, createFirstRec.Body.String())
	}
	var firstCreated struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, createFirstRec.Body.Bytes(), &firstCreated)
	firstReminderID = firstCreated.Data.ID

	createSecondRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"今天二号提醒",
		"due_at":"2026-04-27T14:00:00+08:00",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`"
	}`)
	if createSecondRec.Code != http.StatusCreated {
		t.Fatalf("create second reminder status = %d, body = %s", createSecondRec.Code, createSecondRec.Body.String())
	}
	var secondCreated struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, createSecondRec.Body.Bytes(), &secondCreated)
	secondReminderID = secondCreated.Data.ID

	resolveRec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/resolve", token, `{"input":"取消今天所有提醒，并添加晚上九点的约会提醒"}`)
	if resolveRec.Code != http.StatusOK {
		t.Fatalf("resolve status = %d, body = %s", resolveRec.Code, resolveRec.Body.String())
	}
	var resolvePayload struct {
		Data aiCommandResolveResponse `json:"data"`
	}
	decodeBody(t, resolveRec.Body.Bytes(), &resolvePayload)
	if len(resolvePayload.Data.Result.Plan) != 2 {
		t.Fatalf("expected 2-step plan, got %+v", resolvePayload.Data.Result.Plan)
	}

	executeRec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/confirmations/execute", token, `{"token":"`+resolvePayload.Data.Confirmation.Token+`"}`)
	if executeRec.Code != http.StatusOK {
		t.Fatalf("execute status = %d, body = %s", executeRec.Code, executeRec.Body.String())
	}
	var executePayload struct {
		Data aiCommandExecuteResponse `json:"data"`
	}
	decodeBody(t, executeRec.Body.Bytes(), &executePayload)
	if !executePayload.Data.Executed || len(executePayload.Data.Result) != 2 {
		t.Fatalf("unexpected execute payload: %+v", executePayload.Data)
	}

	getDeletedFirstRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders/"+firstReminderID, token, "")
	if getDeletedFirstRec.Code != http.StatusNotFound {
		t.Fatalf("expected first reminder deleted, got %d body=%s", getDeletedFirstRec.Code, getDeletedFirstRec.Body.String())
	}
	getDeletedSecondRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders/"+secondReminderID, token, "")
	if getDeletedSecondRec.Code != http.StatusNotFound {
		t.Fatalf("expected second reminder deleted, got %d body=%s", getDeletedSecondRec.Code, getDeletedSecondRec.Body.String())
	}

	listRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders", token, "")
	if listRec.Code != http.StatusOK {
		t.Fatalf("list reminders status = %d, body = %s", listRec.Code, listRec.Body.String())
	}
	var listPayload struct {
		Data []struct {
			Title string `json:"title"`
			DueAt string `json:"due_at"`
		} `json:"data"`
	}
	decodeBody(t, listRec.Body.Bytes(), &listPayload)
	if len(listPayload.Data) != 1 {
		t.Fatalf("expected exactly 1 remaining reminder, got %+v", listPayload.Data)
	}
	if listPayload.Data[0].Title != "约会" || listPayload.Data[0].DueAt != "2026-04-27T21:00:00+08:00" {
		t.Fatalf("unexpected created reminder: %+v", listPayload.Data[0])
	}
}

func TestResolveAICommandStreamEmitsOrderedEvents(t *testing.T) {
	t.Parallel()

	mockAI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/commands/classify":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"classification": map[string]any{
					"intent":                "reminder.create",
					"operationType":         "write_requires_confirmation",
					"confidence":            0.98,
					"summary":               "用户要创建提醒",
					"missingSlots":          []string{},
					"entities":              map[string]any{"title": "产品会议", "time": "明天早上九点"},
					"nextStep":              "load_context",
					"clarificationQuestion": nil,
				},
			})
		case "/api/commands/propose":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"ok": true,
				"proposal": map[string]any{
					"status":                "confirmation_required",
					"intent":                "reminder.create",
					"operationType":         "write_requires_confirmation",
					"requiresConfirmation":  true,
					"summary":               "准备创建提醒",
					"userMessage":           "请确认是否创建提醒",
					"missingSlots":          []string{},
					"answer":                nil,
					"clarificationQuestion": nil,
					"confirmationMessage":   "确认创建提醒吗？",
					"proposal": map[string]any{
						"action":     "create_reminder",
						"targetType": "reminder",
						"targetIds":  []string{},
						"patch": map[string]any{
							"title":    "产品会议",
							"due_at":   "2026-04-28T09:00:00+08:00",
							"list_id":  "list_1",
							"group_id": "group_1",
						},
						"reason":    "测试 SSE 事件链路",
						"riskLevel": "low",
					},
					"candidates": []any{},
				},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer mockAI.Close()

	app := newTestAppWithAIBaseURL(t, mockAI.URL)
	token := registerTestUser(t, app)

	rec := performJSON(t, app, http.MethodPost, "/api/v1/ai/commands/resolve/stream", token, `{"input":"明天早上九点提醒我开产品会议"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("stream status = %d, body = %s", rec.Code, rec.Body.String())
	}
	if contentType := rec.Header().Get("Content-Type"); !strings.Contains(contentType, "text/event-stream") {
		t.Fatalf("expected text/event-stream, got %q", contentType)
	}

	events := decodeSSEEvents(t, rec.Body.String())
	if len(events) < 6 {
		t.Fatalf("expected at least 6 events, got %+v", events)
	}

	gotNames := make([]string, 0, len(events))
	for _, event := range events {
		gotNames = append(gotNames, event.Name)
	}
	wantNames := []string{"status", "status", "status", "status", "status", "result", "done"}
	if !slices.Equal(gotNames, wantNames) {
		t.Fatalf("unexpected event order: got=%v want=%v body=%s", gotNames, wantNames, rec.Body.String())
	}

	wantStages := []string{"accepted", "parsing", "loading_context", "planning", "waiting_confirmation"}
	gotStages := []string{
		events[0].Data["stage"].(string),
		events[1].Data["stage"].(string),
		events[2].Data["stage"].(string),
		events[3].Data["stage"].(string),
		events[4].Data["stage"].(string),
	}
	if !slices.Equal(gotStages, wantStages) {
		t.Fatalf("unexpected stages: got=%v want=%v", gotStages, wantStages)
	}

	resultData := events[5].Data
	if resultData["mode"] != "confirmation_required" {
		t.Fatalf("expected confirmation_required, got %+v", resultData)
	}
	confirmation, ok := resultData["confirmation"].(map[string]any)
	if !ok || strings.TrimSpace(confirmation["token"].(string)) == "" {
		t.Fatalf("expected confirmation token, got %+v", resultData["confirmation"])
	}
	doneStage := events[6].Data["stage"]
	if doneStage != "done" {
		t.Fatalf("expected done event, got %+v", events[6])
	}
}

type sseEvent struct {
	Name string
	Data map[string]any
}

func decodeSSEEvents(t *testing.T, raw string) []sseEvent {
	t.Helper()

	chunks := strings.Split(strings.TrimSpace(raw), "\n\n")
	events := make([]sseEvent, 0, len(chunks))
	for _, chunk := range chunks {
		lines := strings.Split(strings.TrimSpace(chunk), "\n")
		event := sseEvent{}
		for _, line := range lines {
			if strings.HasPrefix(line, "event: ") {
				event.Name = strings.TrimSpace(strings.TrimPrefix(line, "event: "))
				continue
			}
			if strings.HasPrefix(line, "data: ") {
				if err := json.Unmarshal([]byte(strings.TrimPrefix(line, "data: ")), &event.Data); err != nil {
					t.Fatalf("decode sse data: %v raw=%s", err, line)
				}
			}
		}
		events = append(events, event)
	}
	return events
}

func newTestAppWithAIBaseURL(t *testing.T, aiBaseURL string) *Application {
	t.Helper()

	dbFile := filepath.Join(t.TempDir(), "test.db")
	audioDir := filepath.Join(t.TempDir(), "audio")
	app, err := New(config.Config{
		Addr:              ":0",
		DatabaseURL:       "sqlite://" + dbFile,
		AIServiceBaseURL:  aiBaseURL,
		AIServiceTimeout:  5 * time.Second,
		AIConfirmTTL:      10 * time.Minute,
		AudioStorageDir:   audioDir,
		EnableAutoMigrate: true,
		JWTAccessSecret:   "test-access-secret",
		JWTRefreshSecret:  "test-refresh-secret",
		AccessTokenTTL:    time.Hour,
		RefreshTokenTTL:   24 * time.Hour,
	})
	if err != nil {
		t.Fatalf("new app: %v", err)
	}
	return app
}
