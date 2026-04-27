package app

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
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
