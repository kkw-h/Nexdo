package app

import (
	"net/http"
	"strings"
	"testing"
)

func TestReminderCreateFormValidationCases(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	ownerToken := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, ownerToken)

	otherSession := registerTestSessionFor(t, app, "reminder-form-other@example.com", "reminder-form-other")
	foreignListID := createListForTest(t, app, otherSession.AccessToken, "foreign-list")
	foreignGroupID := createGroupForTest(t, app, otherSession.AccessToken, "foreign-group")
	foreignTagID := createTagForTest(t, app, otherSession.AccessToken, "foreign-tag")

	cases := []struct {
		name         string
		body         string
		expectedCode int
		contains     string
	}{
		{
			name:         "missing title",
			body:         `{"due_at":"2026-04-18T09:00:00Z","list_id":"` + listID + `","group_id":"` + groupID + `"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "title 必填",
		},
		{
			name:         "blank title",
			body:         `{"title":"   ","due_at":"2026-04-18T09:00:00Z","list_id":"` + listID + `","group_id":"` + groupID + `"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "title 必填",
		},
		{
			name:         "missing due_at",
			body:         `{"title":"提醒","list_id":"` + listID + `","group_id":"` + groupID + `"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "due_at 必须是 RFC3339 时间戳",
		},
		{
			name:         "invalid due_at",
			body:         `{"title":"提醒","due_at":"tomorrow","list_id":"` + listID + `","group_id":"` + groupID + `"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "due_at 必须是 RFC3339 时间戳",
		},
		{
			name:         "missing list_id",
			body:         `{"title":"提醒","due_at":"2026-04-18T09:00:00Z","group_id":"` + groupID + `"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "list_id 和 group_id 必填",
		},
		{
			name:         "missing group_id",
			body:         `{"title":"提醒","due_at":"2026-04-18T09:00:00Z","list_id":"` + listID + `"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "list_id 和 group_id 必填",
		},
		{
			name:         "invalid repeat_rule",
			body:         `{"title":"提醒","due_at":"2026-04-18T09:00:00Z","list_id":"` + listID + `","group_id":"` + groupID + `","repeat_rule":"every_hour"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "repeat_rule 不合法",
		},
		{
			name:         "invalid repeat_until_at",
			body:         `{"title":"提醒","due_at":"2026-04-18T09:00:00Z","repeat_until_at":"bad-time","list_id":"` + listID + `","group_id":"` + groupID + `"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "repeat_until_at 必须是 RFC3339 时间戳",
		},
		{
			name:         "repeat_until_before_due_at",
			body:         `{"title":"提醒","due_at":"2026-04-18T09:00:00Z","repeat_until_at":"2026-04-17T09:00:00Z","repeat_rule":"daily","list_id":"` + listID + `","group_id":"` + groupID + `"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "repeat_until_at 不能早于 due_at",
		},
		{
			name:         "negative remind_before_minutes",
			body:         `{"title":"提醒","due_at":"2026-04-18T09:00:00Z","remind_before_minutes":-1,"list_id":"` + listID + `","group_id":"` + groupID + `"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "remind_before_minutes 不能小于 0",
		},
		{
			name:         "foreign list",
			body:         `{"title":"提醒","due_at":"2026-04-18T09:00:00Z","list_id":"` + foreignListID + `","group_id":"` + groupID + `"}`,
			expectedCode: http.StatusNotFound,
			contains:     "资源不存在",
		},
		{
			name:         "foreign group",
			body:         `{"title":"提醒","due_at":"2026-04-18T09:00:00Z","list_id":"` + listID + `","group_id":"` + foreignGroupID + `"}`,
			expectedCode: http.StatusNotFound,
			contains:     "资源不存在",
		},
		{
			name:         "foreign tag",
			body:         `{"title":"提醒","due_at":"2026-04-18T09:00:00Z","list_id":"` + listID + `","group_id":"` + groupID + `","tag_ids":["` + foreignTagID + `"]}`,
			expectedCode: http.StatusNotFound,
			contains:     "标签不存在",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", ownerToken, tc.body)
			if rec.Code != tc.expectedCode {
				t.Fatalf("expected %d, got %d: %s", tc.expectedCode, rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), tc.contains) {
				t.Fatalf("expected response to contain %q, body=%s", tc.contains, rec.Body.String())
			}
		})
	}
}

func TestReminderCreateFormFieldPersistenceAndDefaults(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)
	firstTagID := createTagForTest(t, app, token, "form-tag-1")
	secondTagID := createTagForTest(t, app, token, "form-tag-2")

	fullRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"完整提醒",
		"note":"包含备注",
		"due_at":"2026-04-18T09:00:00Z",
		"repeat_until_at":"2026-05-18T09:00:00Z",
		"remind_before_minutes":30,
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`",
		"tag_ids":["`+firstTagID+`","`+secondTagID+`"],
		"notification_enabled":false,
		"repeat_rule":"monthly"
	}`)
	if fullRec.Code != http.StatusCreated {
		t.Fatalf("full create status = %d, body = %s", fullRec.Code, fullRec.Body.String())
	}
	var full struct {
		Data struct {
			Title               string `json:"title"`
			Note                string `json:"note"`
			DueAt               string `json:"due_at"`
			RepeatUntilAt       string `json:"repeat_until_at"`
			RemindBeforeMinutes int    `json:"remind_before_minutes"`
			ListID              string `json:"list_id"`
			GroupID             string `json:"group_id"`
			NotificationEnabled bool   `json:"notification_enabled"`
			RepeatRule          string `json:"repeat_rule"`
			Tags                []struct {
				ID string `json:"id"`
			} `json:"tags"`
		} `json:"data"`
	}
	decodeBody(t, fullRec.Body.Bytes(), &full)
	if full.Data.Title != "完整提醒" || full.Data.Note != "包含备注" || full.Data.DueAt != "2026-04-18T09:00:00Z" {
		t.Fatalf("unexpected full create payload: %+v", full.Data)
	}
	if full.Data.RepeatUntilAt != "2026-05-18T09:00:00Z" || full.Data.RemindBeforeMinutes != 30 {
		t.Fatalf("unexpected schedule fields: %+v", full.Data)
	}
	if full.Data.ListID != listID || full.Data.GroupID != groupID {
		t.Fatalf("unexpected resource ids: %+v", full.Data)
	}
	if full.Data.NotificationEnabled {
		t.Fatalf("expected notification_enabled=false, got %+v", full.Data)
	}
	if full.Data.RepeatRule != "monthly" {
		t.Fatalf("expected repeat_rule=monthly, got %+v", full.Data)
	}
	if len(full.Data.Tags) != 2 {
		t.Fatalf("expected 2 tags, got %+v", full.Data.Tags)
	}

	defaultRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"默认提醒",
		"due_at":"2026-04-19T09:00:00Z",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`"
	}`)
	if defaultRec.Code != http.StatusCreated {
		t.Fatalf("default create status = %d, body = %s", defaultRec.Code, defaultRec.Body.String())
	}
	var defaults struct {
		Data struct {
			Note                string `json:"note"`
			RepeatUntilAt       any    `json:"repeat_until_at"`
			RemindBeforeMinutes int    `json:"remind_before_minutes"`
			NotificationEnabled bool   `json:"notification_enabled"`
			RepeatRule          string `json:"repeat_rule"`
			Tags                []any  `json:"tags"`
		} `json:"data"`
	}
	decodeBody(t, defaultRec.Body.Bytes(), &defaults)
	if defaults.Data.Note != "" {
		t.Fatalf("expected default note to be empty, got %+v", defaults.Data)
	}
	if defaults.Data.RepeatUntilAt != nil || defaults.Data.RemindBeforeMinutes != 0 {
		t.Fatalf("expected default schedule fields, got %+v", defaults.Data)
	}
	if !defaults.Data.NotificationEnabled {
		t.Fatalf("expected notification_enabled default true, got %+v", defaults.Data)
	}
	if defaults.Data.RepeatRule != "none" {
		t.Fatalf("expected repeat_rule default none, got %+v", defaults.Data)
	}
	if len(defaults.Data.Tags) != 0 {
		t.Fatalf("expected default tags empty, got %+v", defaults.Data.Tags)
	}
}

func TestReminderPatchFormFieldCases(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	ownerToken := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, ownerToken)
	newListID := createListForTest(t, app, ownerToken, "patch-list")
	newGroupID := createGroupForTest(t, app, ownerToken, "patch-group")
	firstTagID := createTagForTest(t, app, ownerToken, "patch-tag-1")
	secondTagID := createTagForTest(t, app, ownerToken, "patch-tag-2")

	otherSession := registerTestSessionFor(t, app, "patch-form-other@example.com", "patch-form-other")
	foreignListID := createListForTest(t, app, otherSession.AccessToken, "foreign-list")
	foreignGroupID := createGroupForTest(t, app, otherSession.AccessToken, "foreign-group")
	foreignTagID := createTagForTest(t, app, otherSession.AccessToken, "foreign-tag")

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", ownerToken, `{
		"title":"原始提醒",
		"note":"原始备注",
		"due_at":"2026-04-18T09:00:00Z",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`",
		"tag_ids":["`+firstTagID+`"]
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

	fullPatchRec := performJSON(t, app, http.MethodPatch, "/api/v1/reminders/"+created.Data.ID, ownerToken, `{
		"title":"更新提醒",
		"note":"更新备注",
		"due_at":"2026-04-20T10:00:00Z",
		"repeat_until_at":"2026-05-20T10:00:00Z",
		"remind_before_minutes":45,
		"list_id":"`+newListID+`",
		"group_id":"`+newGroupID+`",
		"tag_ids":["`+secondTagID+`"],
		"notification_enabled":false,
		"repeat_rule":"yearly"
	}`)
	if fullPatchRec.Code != http.StatusOK {
		t.Fatalf("full patch status = %d, body = %s", fullPatchRec.Code, fullPatchRec.Body.String())
	}
	var patched struct {
		Data struct {
			Title               string `json:"title"`
			Note                string `json:"note"`
			DueAt               string `json:"due_at"`
			RepeatUntilAt       string `json:"repeat_until_at"`
			RemindBeforeMinutes int    `json:"remind_before_minutes"`
			ListID              string `json:"list_id"`
			GroupID             string `json:"group_id"`
			NotificationEnabled bool   `json:"notification_enabled"`
			RepeatRule          string `json:"repeat_rule"`
			Tags                []struct {
				ID string `json:"id"`
			} `json:"tags"`
		} `json:"data"`
	}
	decodeBody(t, fullPatchRec.Body.Bytes(), &patched)
	if patched.Data.Title != "更新提醒" || patched.Data.Note != "更新备注" || patched.Data.DueAt != "2026-04-20T10:00:00Z" {
		t.Fatalf("unexpected patched reminder: %+v", patched.Data)
	}
	if patched.Data.RepeatUntilAt != "2026-05-20T10:00:00Z" || patched.Data.RemindBeforeMinutes != 45 {
		t.Fatalf("unexpected patched schedule fields: %+v", patched.Data)
	}
	if patched.Data.ListID != newListID || patched.Data.GroupID != newGroupID {
		t.Fatalf("unexpected patched resources: %+v", patched.Data)
	}
	if patched.Data.NotificationEnabled {
		t.Fatalf("expected notification_enabled=false, got %+v", patched.Data)
	}
	if patched.Data.RepeatRule != "yearly" {
		t.Fatalf("expected repeat_rule=yearly, got %+v", patched.Data)
	}
	if len(patched.Data.Tags) != 1 || patched.Data.Tags[0].ID != secondTagID {
		t.Fatalf("unexpected patched tags: %+v", patched.Data.Tags)
	}

	clearTagsRec := performJSON(t, app, http.MethodPatch, "/api/v1/reminders/"+created.Data.ID, ownerToken, `{"tag_ids":[]}`)
	if clearTagsRec.Code != http.StatusOK {
		t.Fatalf("clear tags status = %d, body = %s", clearTagsRec.Code, clearTagsRec.Body.String())
	}
	var cleared struct {
		Data struct {
			Tags []any `json:"tags"`
		} `json:"data"`
	}
	decodeBody(t, clearTagsRec.Body.Bytes(), &cleared)
	if len(cleared.Data.Tags) != 0 {
		t.Fatalf("expected tags to be cleared, got %+v", cleared.Data.Tags)
	}

	clearRepeatUntilRec := performJSON(t, app, http.MethodPatch, "/api/v1/reminders/"+created.Data.ID, ownerToken, `{"repeat_until_at":null,"remind_before_minutes":0}`)
	if clearRepeatUntilRec.Code != http.StatusOK {
		t.Fatalf("clear repeat_until_at status = %d, body = %s", clearRepeatUntilRec.Code, clearRepeatUntilRec.Body.String())
	}
	var clearedSchedule struct {
		Data struct {
			RepeatUntilAt       any `json:"repeat_until_at"`
			RemindBeforeMinutes int `json:"remind_before_minutes"`
		} `json:"data"`
	}
	decodeBody(t, clearRepeatUntilRec.Body.Bytes(), &clearedSchedule)
	if clearedSchedule.Data.RepeatUntilAt != nil || clearedSchedule.Data.RemindBeforeMinutes != 0 {
		t.Fatalf("expected cleared schedule fields, got %+v", clearedSchedule.Data)
	}

	invalidCases := []struct {
		name         string
		body         string
		expectedCode int
		contains     string
	}{
		{
			name:         "invalid due_at",
			body:         `{"due_at":"bad-time"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "due_at 必须是 RFC3339 时间戳",
		},
		{
			name:         "invalid repeat_rule",
			body:         `{"repeat_rule":"every_hour"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "repeat_rule 不合法",
		},
		{
			name:         "invalid repeat_until_at",
			body:         `{"repeat_until_at":"bad-time"}`,
			expectedCode: http.StatusBadRequest,
			contains:     "repeat_until_at 必须是 RFC3339 时间戳",
		},
		{
			name:         "negative remind_before_minutes",
			body:         `{"remind_before_minutes":-1}`,
			expectedCode: http.StatusBadRequest,
			contains:     "remind_before_minutes 不能小于 0",
		},
		{
			name:         "foreign list",
			body:         `{"list_id":"` + foreignListID + `"}`,
			expectedCode: http.StatusNotFound,
			contains:     "资源不存在",
		},
		{
			name:         "foreign group",
			body:         `{"group_id":"` + foreignGroupID + `"}`,
			expectedCode: http.StatusNotFound,
			contains:     "资源不存在",
		},
		{
			name:         "foreign tag",
			body:         `{"tag_ids":["` + foreignTagID + `"]}`,
			expectedCode: http.StatusNotFound,
			contains:     "标签不存在",
		},
	}

	for _, tc := range invalidCases {
		t.Run(tc.name, func(t *testing.T) {
			rec := performJSON(t, app, http.MethodPatch, "/api/v1/reminders/"+created.Data.ID, ownerToken, tc.body)
			if rec.Code != tc.expectedCode {
				t.Fatalf("expected %d, got %d: %s", tc.expectedCode, rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), tc.contains) {
				t.Fatalf("expected response to contain %q, body=%s", tc.contains, rec.Body.String())
			}
		})
	}
}

func createListForTest(t *testing.T, app *Application, token, name string) string {
	t.Helper()

	rec := performJSON(t, app, http.MethodPost, "/api/v1/lists", token, `{"name":"`+name+`","color_value":1}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create list status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var payload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, rec.Body.Bytes(), &payload)
	return payload.Data.ID
}

func createGroupForTest(t *testing.T, app *Application, token, name string) string {
	t.Helper()

	rec := performJSON(t, app, http.MethodPost, "/api/v1/groups", token, `{"name":"`+name+`","icon_code_point":1}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create group status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var payload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, rec.Body.Bytes(), &payload)
	return payload.Data.ID
}
