package app

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"nexdo-server-golang/internal/config"
	"nexdo-server-golang/internal/models"

	"github.com/gin-gonic/gin"
)

func TestRecurringReminderCompleteRollsOverAndWritesLog(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	createBody := `{"title":"每日站会","due_at":"2026-04-18T09:00:00Z","list_id":"` + listID + `","group_id":"` + groupID + `","repeat_rule":"daily"}`
	createRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, createBody)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create reminder status = %d, body = %s", createRec.Code, createRec.Body.String())
	}

	var created struct {
		Data struct {
			ID     string `json:"id"`
			DueAt  string `json:"due_at"`
			Title  string `json:"title"`
			Repeat string `json:"repeat_rule"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)

	completeRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders/"+created.Data.ID+"/complete", token, "")
	if completeRec.Code != http.StatusOK {
		t.Fatalf("complete reminder status = %d, body = %s", completeRec.Code, completeRec.Body.String())
	}

	var completed struct {
		Data struct {
			ID         string `json:"id"`
			DueAt      string `json:"due_at"`
			RepeatRule string `json:"repeat_rule"`
			Title      string `json:"title"`
		} `json:"data"`
	}
	decodeBody(t, completeRec.Body.Bytes(), &completed)

	if completed.Data.ID == created.Data.ID {
		t.Fatal("expected rollover to create a new reminder id")
	}
	if completed.Data.DueAt != "2026-04-19T09:00:00Z" {
		t.Fatalf("unexpected next due_at: %s", completed.Data.DueAt)
	}
	if completed.Data.RepeatRule != "daily" {
		t.Fatalf("expected repeat_rule=daily, got %s", completed.Data.RepeatRule)
	}

	originalRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders/"+created.Data.ID, token, "")
	if originalRec.Code != http.StatusOK {
		t.Fatalf("get original reminder status = %d, body = %s", originalRec.Code, originalRec.Body.String())
	}
	var original struct {
		Data struct {
			IsCompleted bool   `json:"is_completed"`
			RepeatRule  string `json:"repeat_rule"`
		} `json:"data"`
	}
	decodeBody(t, originalRec.Body.Bytes(), &original)
	if !original.Data.IsCompleted {
		t.Fatal("expected original reminder to be completed")
	}
	if original.Data.RepeatRule != "none" {
		t.Fatalf("expected original repeat_rule=none, got %s", original.Data.RepeatRule)
	}

	logRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders/"+created.Data.ID+"/completion-logs", token, "")
	if logRec.Code != http.StatusOK {
		t.Fatalf("completion logs status = %d, body = %s", logRec.Code, logRec.Body.String())
	}
	var logs struct {
		Data []struct {
			OriginalDueAt string `json:"original_due_at"`
			NextDueAt     string `json:"next_due_at"`
		} `json:"data"`
	}
	decodeBody(t, logRec.Body.Bytes(), &logs)
	if len(logs.Data) != 1 {
		t.Fatalf("expected 1 completion log, got %d", len(logs.Data))
	}
	if logs.Data[0].OriginalDueAt != "2026-04-18T09:00:00Z" || logs.Data[0].NextDueAt != "2026-04-19T09:00:00Z" {
		t.Fatalf("unexpected completion log: %+v", logs.Data[0])
	}
}

func TestRecurringReminderCompletePreservesOffsetForDaily(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{"title":"本地时区日循环","due_at":"2026-04-18T09:00:00+08:00","list_id":"`+listID+`","group_id":"`+groupID+`","repeat_rule":"daily"}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create reminder status = %d, body = %s", createRec.Code, createRec.Body.String())
	}

	var created struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)

	completeRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders/"+created.Data.ID+"/complete", token, "")
	if completeRec.Code != http.StatusOK {
		t.Fatalf("complete reminder status = %d, body = %s", completeRec.Code, completeRec.Body.String())
	}

	var completed struct {
		Data struct {
			DueAt      string `json:"due_at"`
			RepeatRule string `json:"repeat_rule"`
		} `json:"data"`
	}
	decodeBody(t, completeRec.Body.Bytes(), &completed)

	if completed.Data.DueAt != "2026-04-19T09:00:00+08:00" {
		t.Fatalf("expected next due_at to preserve +08:00 wall clock, got %s", completed.Data.DueAt)
	}
	if completed.Data.RepeatRule != "daily" {
		t.Fatalf("expected repeat_rule=daily, got %s", completed.Data.RepeatRule)
	}
}

func TestRecurringReminderCompletePreservesOffsetForChinaCalendarRules(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	cases := []struct {
		name        string
		rule        string
		dueAt       string
		expectedDue string
	}{
		{name: "workday", rule: "workday", dueAt: "2026-04-03T09:00:00+08:00", expectedDue: "2026-04-07T09:00:00+08:00"},
		{name: "non_workday", rule: "non_workday", dueAt: "2026-04-03T09:00:00+08:00", expectedDue: "2026-04-04T09:00:00+08:00"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			createRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{"title":"本地时区循环-`+tc.rule+`","due_at":"`+tc.dueAt+`","list_id":"`+listID+`","group_id":"`+groupID+`","repeat_rule":"`+tc.rule+`"}`)
			if createRec.Code != http.StatusCreated {
				t.Fatalf("create reminder status = %d, body = %s", createRec.Code, createRec.Body.String())
			}

			var created struct {
				Data struct {
					ID string `json:"id"`
				} `json:"data"`
			}
			decodeBody(t, createRec.Body.Bytes(), &created)

			completeRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders/"+created.Data.ID+"/complete", token, "")
			if completeRec.Code != http.StatusOK {
				t.Fatalf("complete reminder status = %d, body = %s", completeRec.Code, completeRec.Body.String())
			}

			var completed struct {
				Data struct {
					DueAt      string `json:"due_at"`
					RepeatRule string `json:"repeat_rule"`
				} `json:"data"`
			}
			decodeBody(t, completeRec.Body.Bytes(), &completed)

			if completed.Data.DueAt != tc.expectedDue {
				t.Fatalf("expected next due_at %s, got %s", tc.expectedDue, completed.Data.DueAt)
			}
			if completed.Data.RepeatRule != tc.rule {
				t.Fatalf("expected repeat_rule=%s, got %s", tc.rule, completed.Data.RepeatRule)
			}
		})
	}
}

func TestRecurringReminderStopsAtRepeatUntilAt(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"截止日循环",
		"due_at":"2026-04-18T09:00:00+08:00",
		"repeat_until_at":"2026-04-18T18:00:00+08:00",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`",
		"repeat_rule":"daily"
	}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create reminder status = %d, body = %s", createRec.Code, createRec.Body.String())
	}

	var created struct {
		Data struct {
			ID            string `json:"id"`
			RepeatRule    string `json:"repeat_rule"`
			IsCompleted   bool   `json:"is_completed"`
			RepeatUntilAt string `json:"repeat_until_at"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)

	completeRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders/"+created.Data.ID+"/complete", token, "")
	if completeRec.Code != http.StatusOK {
		t.Fatalf("complete reminder status = %d, body = %s", completeRec.Code, completeRec.Body.String())
	}

	var completed struct {
		Data struct {
			ID            string `json:"id"`
			IsCompleted   bool   `json:"is_completed"`
			RepeatRule    string `json:"repeat_rule"`
			RepeatUntilAt string `json:"repeat_until_at"`
		} `json:"data"`
	}
	decodeBody(t, completeRec.Body.Bytes(), &completed)

	if completed.Data.ID != created.Data.ID {
		t.Fatalf("expected no rollover after cutoff, got new id %s", completed.Data.ID)
	}
	if !completed.Data.IsCompleted || completed.Data.RepeatRule != "none" {
		t.Fatalf("expected current reminder to be completed without rollover, got %+v", completed.Data)
	}
	if completed.Data.RepeatUntilAt != "2026-04-18T18:00:00+08:00" {
		t.Fatalf("expected repeat_until_at preserved, got %+v", completed.Data)
	}

	logRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders/"+created.Data.ID+"/completion-logs", token, "")
	if logRec.Code != http.StatusOK {
		t.Fatalf("completion logs status = %d, body = %s", logRec.Code, logRec.Body.String())
	}
	var logs struct {
		Data []any `json:"data"`
	}
	decodeBody(t, logRec.Body.Bytes(), &logs)
	if len(logs.Data) != 0 {
		t.Fatalf("expected no rollover logs after cutoff, got %+v", logs.Data)
	}
}

func TestRecurringReminderCompleteRollsOverForAllRules(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	cases := []struct {
		name        string
		rule        string
		dueAt       string
		expectedDue string
	}{
		{name: "daily", rule: "daily", dueAt: "2026-04-18T09:00:00Z", expectedDue: "2026-04-19T09:00:00Z"},
		{name: "weekly", rule: "weekly", dueAt: "2026-04-18T09:00:00Z", expectedDue: "2026-04-25T09:00:00Z"},
		{name: "monthly", rule: "monthly", dueAt: "2026-04-18T09:00:00Z", expectedDue: "2026-05-18T09:00:00Z"},
		{name: "yearly", rule: "yearly", dueAt: "2026-04-18T09:00:00Z", expectedDue: "2027-04-18T09:00:00Z"},
		{name: "workday", rule: "workday", dueAt: "2026-04-03T09:00:00Z", expectedDue: "2026-04-07T09:00:00Z"},
		{name: "non_workday", rule: "non_workday", dueAt: "2026-04-03T09:00:00Z", expectedDue: "2026-04-04T09:00:00Z"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			createRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{"title":"循环提醒-`+tc.rule+`","due_at":"`+tc.dueAt+`","list_id":"`+listID+`","group_id":"`+groupID+`","repeat_rule":"`+tc.rule+`"}`)
			if createRec.Code != http.StatusCreated {
				t.Fatalf("create reminder status = %d, body = %s", createRec.Code, createRec.Body.String())
			}

			var created struct {
				Data struct {
					ID string `json:"id"`
				} `json:"data"`
			}
			decodeBody(t, createRec.Body.Bytes(), &created)

			completeRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders/"+created.Data.ID+"/complete", token, "")
			if completeRec.Code != http.StatusOK {
				t.Fatalf("complete reminder status = %d, body = %s", completeRec.Code, completeRec.Body.String())
			}

			var completed struct {
				Data struct {
					ID         string `json:"id"`
					DueAt      string `json:"due_at"`
					RepeatRule string `json:"repeat_rule"`
				} `json:"data"`
			}
			decodeBody(t, completeRec.Body.Bytes(), &completed)

			if completed.Data.ID == created.Data.ID {
				t.Fatal("expected rollover to create a new reminder id")
			}
			if completed.Data.DueAt != tc.expectedDue {
				t.Fatalf("expected next due_at %s, got %s", tc.expectedDue, completed.Data.DueAt)
			}
			if completed.Data.RepeatRule != tc.rule {
				t.Fatalf("expected repeat_rule %s, got %s", tc.rule, completed.Data.RepeatRule)
			}

			originalRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders/"+created.Data.ID, token, "")
			if originalRec.Code != http.StatusOK {
				t.Fatalf("get original reminder status = %d, body = %s", originalRec.Code, originalRec.Body.String())
			}
			var original struct {
				Data struct {
					IsCompleted bool   `json:"is_completed"`
					RepeatRule  string `json:"repeat_rule"`
				} `json:"data"`
			}
			decodeBody(t, originalRec.Body.Bytes(), &original)
			if !original.Data.IsCompleted || original.Data.RepeatRule != "none" {
				t.Fatalf("unexpected original reminder after rollover: %+v", original.Data)
			}
		})
	}
}

func TestSyncBootstrapUsesRequestHostAndCursor(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	if err := writer.WriteField("content", "录音闪念"); err != nil {
		t.Fatalf("write content: %v", err)
	}
	header := make(textproto.MIMEHeader)
	header.Set("Content-Disposition", `form-data; name="audio"; filename="memo.webm"`)
	header.Set("Content-Type", "audio/webm")
	part, err := writer.CreatePart(header)
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	if _, err := part.Write([]byte("fake-audio")); err != nil {
		t.Fatalf("write audio: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close writer: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/quick-notes", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Host = "api.nexdo.test"
	rec := httptest.NewRecorder()
	app.Router().ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create quick note status = %d, body = %s", rec.Code, rec.Body.String())
	}

	before := time.Now().UTC()
	bootstrapReq := httptest.NewRequest(http.MethodGet, "/api/v1/sync/bootstrap", nil)
	bootstrapReq.Header.Set("Authorization", "Bearer "+token)
	bootstrapReq.Host = "api.nexdo.test"
	bootstrapRec := httptest.NewRecorder()
	app.Router().ServeHTTP(bootstrapRec, bootstrapReq)
	if bootstrapRec.Code != http.StatusOK {
		t.Fatalf("bootstrap status = %d, body = %s", bootstrapRec.Code, bootstrapRec.Body.String())
	}
	after := time.Now().UTC()

	var bootstrap struct {
		Data struct {
			ServerTime string `json:"server_time"`
			QuickNotes []struct {
				AudioURL *string `json:"audio_url"`
			} `json:"quick_notes"`
		} `json:"data"`
	}
	decodeBody(t, bootstrapRec.Body.Bytes(), &bootstrap)

	if len(bootstrap.Data.QuickNotes) != 1 || bootstrap.Data.QuickNotes[0].AudioURL == nil {
		t.Fatalf("expected one quick note with audio_url, got %+v", bootstrap.Data.QuickNotes)
	}
	if !strings.Contains(*bootstrap.Data.QuickNotes[0].AudioURL, "http://api.nexdo.test/api/v1/quick-notes/") {
		t.Fatalf("unexpected audio_url: %s", *bootstrap.Data.QuickNotes[0].AudioURL)
	}
	serverTime, err := time.Parse(time.RFC3339Nano, bootstrap.Data.ServerTime)
	if err != nil {
		t.Fatalf("parse server_time: %v", err)
	}
	if serverTime.Before(before.Add(-1*time.Second)) || serverTime.After(after.Add(1*time.Second)) {
		t.Fatalf("server_time out of expected range: %s", bootstrap.Data.ServerTime)
	}
}

func TestDocsUIAccessible(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/docs/ui", nil)
	req.Host = "api.nexdo.test"
	rec := httptest.NewRecorder()

	app.Router().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("docs ui status = %d, body = %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Header().Get("Content-Type"), "text/html") {
		t.Fatalf("unexpected content-type: %s", rec.Header().Get("Content-Type"))
	}
	body := rec.Body.String()
	if !strings.Contains(body, "Nexdo API Docs") || !strings.Contains(body, "/api/v1/docs") {
		t.Fatalf("unexpected docs ui body: %s", body)
	}
}

func TestInvalidRepeatRuleRejected(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	createBody := `{"title":"非法循环","due_at":"2026-04-18T09:00:00Z","list_id":"` + listID + `","group_id":"` + groupID + `","repeat_rule":"every_hour"}`
	rec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, createBody)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "repeat_rule 不合法") {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}

func TestAuthDevicesAndResourcesFlow(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)

	deviceProbeRec := performJSONWithDevice(t, app, http.MethodGet, "/api/v1/me", token, "", "test-device-1", "Test iPhone", "iOS")
	if deviceProbeRec.Code != http.StatusOK {
		t.Fatalf("device probe status = %d, body = %s", deviceProbeRec.Code, deviceProbeRec.Body.String())
	}

	devicesRec := performJSONWithDevice(t, app, http.MethodGet, "/api/v1/me/devices", token, "", "test-device-1", "Test iPhone", "iOS")
	if devicesRec.Code != http.StatusOK {
		t.Fatalf("devices status = %d, body = %s", devicesRec.Code, devicesRec.Body.String())
	}
	var devicesPayload struct {
		Data struct {
			Devices []struct {
				ID        string `json:"id"`
				IPAddress string `json:"ip_address"`
			} `json:"devices"`
			CurrentDeviceID string `json:"current_device_id"`
		} `json:"data"`
	}
	decodeBody(t, devicesRec.Body.Bytes(), &devicesPayload)
	if len(devicesPayload.Data.Devices) != 1 {
		t.Fatalf("expected one device, got %+v", devicesPayload.Data.Devices)
	}
	if devicesPayload.Data.CurrentDeviceID == "" {
		t.Fatal("expected current device id")
	}
	if devicesPayload.Data.Devices[0].IPAddress == "" {
		t.Fatal("expected device ip address")
	}

	listRec := performJSON(t, app, http.MethodPost, "/api/v1/lists", token, `{"name":"工作","color_value":1,"sort_order":1}`)
	groupRec := performJSON(t, app, http.MethodPost, "/api/v1/groups", token, `{"name":"项目","icon_code_point":12,"sort_order":1}`)
	tagRec := performJSON(t, app, http.MethodPost, "/api/v1/tags", token, `{"name":"重要-新","color_value":2}`)
	if listRec.Code != http.StatusCreated || groupRec.Code != http.StatusCreated || tagRec.Code != http.StatusCreated {
		t.Fatalf("resource create failed: %d %d %d", listRec.Code, groupRec.Code, tagRec.Code)
	}

	var listPayload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	var groupPayload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	var tagPayload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, listRec.Body.Bytes(), &listPayload)
	decodeBody(t, groupRec.Body.Bytes(), &groupPayload)
	decodeBody(t, tagRec.Body.Bytes(), &tagPayload)

	listPatch := performJSON(t, app, http.MethodPatch, "/api/v1/lists/"+listPayload.Data.ID, token, `{"name":"工作-更新"}`)
	groupPatch := performJSON(t, app, http.MethodPatch, "/api/v1/groups/"+groupPayload.Data.ID, token, `{"name":"项目-更新"}`)
	tagPatch := performJSON(t, app, http.MethodPatch, "/api/v1/tags/"+tagPayload.Data.ID, token, `{"name":"重要-更新"}`)
	if listPatch.Code != http.StatusOK || groupPatch.Code != http.StatusOK || tagPatch.Code != http.StatusOK {
		t.Fatalf("resource patch failed: %d %d %d", listPatch.Code, groupPatch.Code, tagPatch.Code)
	}

	deleteTag := performJSON(t, app, http.MethodDelete, "/api/v1/tags/"+tagPayload.Data.ID, token, "")
	deleteGroup := performJSON(t, app, http.MethodDelete, "/api/v1/groups/"+groupPayload.Data.ID, token, "")
	deleteList := performJSON(t, app, http.MethodDelete, "/api/v1/lists/"+listPayload.Data.ID, token, "")
	if deleteTag.Code != http.StatusOK || deleteGroup.Code != http.StatusOK || deleteList.Code != http.StatusOK {
		t.Fatalf("resource delete failed: %d %d %d", deleteTag.Code, deleteGroup.Code, deleteList.Code)
	}

	deleteDevice := performJSON(t, app, http.MethodDelete, "/api/v1/me/devices/"+devicesPayload.Data.Devices[0].ID, token, "")
	if deleteDevice.Code != http.StatusOK {
		t.Fatalf("delete device status = %d, body = %s", deleteDevice.Code, deleteDevice.Body.String())
	}
}

func TestAuthProfilePasswordLoginRefreshFlow(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	session := registerTestSession(t, app)

	updateRec := performJSON(t, app, http.MethodPatch, "/api/v1/me", session.AccessToken, `{
		"nickname":"worker2-updated",
		"avatar_url":"https://cdn.nexdo.test/avatar.png",
		"timezone":"UTC",
		"locale":"en-US"
	}`)
	if updateRec.Code != http.StatusOK {
		t.Fatalf("update profile status = %d, body = %s", updateRec.Code, updateRec.Body.String())
	}
	var updated struct {
		Data struct {
			Nickname  string `json:"nickname"`
			AvatarURL string `json:"avatar_url"`
			Timezone  string `json:"timezone"`
			Locale    string `json:"locale"`
		} `json:"data"`
	}
	decodeBody(t, updateRec.Body.Bytes(), &updated)
	if updated.Data.Nickname != "worker2-updated" || updated.Data.AvatarURL != "https://cdn.nexdo.test/avatar.png" || updated.Data.Timezone != "UTC" || updated.Data.Locale != "en-US" {
		t.Fatalf("unexpected updated profile: %+v", updated.Data)
	}

	invalidAvatarRec := performJSON(t, app, http.MethodPatch, "/api/v1/me", session.AccessToken, `{
		"avatar_url":"ftp://cdn.nexdo.test/avatar.png"
	}`)
	if invalidAvatarRec.Code != http.StatusBadRequest || !strings.Contains(invalidAvatarRec.Body.String(), "avatar_url") {
		t.Fatalf("invalid avatar status = %d, body = %s", invalidAvatarRec.Code, invalidAvatarRec.Body.String())
	}

	invalidTimezoneRec := performJSON(t, app, http.MethodPatch, "/api/v1/me", session.AccessToken, `{
		"timezone":"Mars/Base"
	}`)
	if invalidTimezoneRec.Code != http.StatusBadRequest || !strings.Contains(invalidTimezoneRec.Body.String(), "timezone 不合法") {
		t.Fatalf("invalid timezone status = %d, body = %s", invalidTimezoneRec.Code, invalidTimezoneRec.Body.String())
	}

	invalidLocaleRec := performJSON(t, app, http.MethodPatch, "/api/v1/me", session.AccessToken, `{
		"locale":"zh_CN"
	}`)
	if invalidLocaleRec.Code != http.StatusBadRequest || !strings.Contains(invalidLocaleRec.Body.String(), "locale 不合法") {
		t.Fatalf("invalid locale status = %d, body = %s", invalidLocaleRec.Code, invalidLocaleRec.Body.String())
	}

	wrongPasswordRec := performJSON(t, app, http.MethodPatch, "/api/v1/me/password", session.AccessToken, `{
		"old_password":"wrong-password",
		"new_password":"new-password-123"
	}`)
	if wrongPasswordRec.Code != http.StatusUnauthorized || !strings.Contains(wrongPasswordRec.Body.String(), "旧密码不正确") {
		t.Fatalf("wrong password status = %d, body = %s", wrongPasswordRec.Code, wrongPasswordRec.Body.String())
	}

	changePasswordRec := performJSON(t, app, http.MethodPatch, "/api/v1/me/password", session.AccessToken, `{
		"old_password":"password123",
		"new_password":"new-password-123"
	}`)
	if changePasswordRec.Code != http.StatusOK {
		t.Fatalf("change password status = %d, body = %s", changePasswordRec.Code, changePasswordRec.Body.String())
	}

	oldAccessAfterPasswordRec := performJSON(t, app, http.MethodGet, "/api/v1/me", session.AccessToken, "")
	if oldAccessAfterPasswordRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected old access token to be revoked after password change, got %d: %s", oldAccessAfterPasswordRec.Code, oldAccessAfterPasswordRec.Body.String())
	}

	oldRefreshAfterPasswordRec := performJSON(t, app, http.MethodPost, "/api/v1/auth/refresh", "", `{
		"refresh_token":"`+session.RefreshToken+`"
	}`)
	if oldRefreshAfterPasswordRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected old refresh token to be revoked after password change, got %d: %s", oldRefreshAfterPasswordRec.Code, oldRefreshAfterPasswordRec.Body.String())
	}

	oldLoginRec := performJSON(t, app, http.MethodPost, "/api/v1/auth/login", "", `{
		"email":"worker2@example.com",
		"password":"password123"
	}`)
	if oldLoginRec.Code != http.StatusUnauthorized {
		t.Fatalf("old login status = %d, body = %s", oldLoginRec.Code, oldLoginRec.Body.String())
	}

	loginRec := performJSONWithDevice(t, app, http.MethodPost, "/api/v1/auth/login", "", `{
		"email":"worker2@example.com",
		"password":"new-password-123"
	}`, "test-device-login", "", "")
	if loginRec.Code != http.StatusOK {
		t.Fatalf("login status = %d, body = %s", loginRec.Code, loginRec.Body.String())
	}
	var loginPayload struct {
		Data struct {
			User struct {
				Nickname string `json:"nickname"`
			} `json:"user"`
			Tokens struct {
				AccessToken  string `json:"access_token"`
				RefreshToken string `json:"refresh_token"`
			} `json:"tokens"`
		} `json:"data"`
	}
	decodeBody(t, loginRec.Body.Bytes(), &loginPayload)
	if loginPayload.Data.User.Nickname != "worker2-updated" {
		t.Fatalf("unexpected login nickname: %+v", loginPayload.Data.User)
	}
	if loginPayload.Data.Tokens.AccessToken == "" || loginPayload.Data.Tokens.RefreshToken == "" {
		t.Fatalf("expected login tokens, got %+v", loginPayload.Data.Tokens)
	}

	devicesRec := performJSONWithDevice(t, app, http.MethodGet, "/api/v1/me/devices", loginPayload.Data.Tokens.AccessToken, "", "test-device-login", "", "")
	if devicesRec.Code != http.StatusOK {
		t.Fatalf("devices after login status = %d, body = %s", devicesRec.Code, devicesRec.Body.String())
	}
	var devicesPayload struct {
		Data struct {
			Devices []struct {
				DeviceID   string `json:"device_id"`
				DeviceName string `json:"device_name"`
				Platform   string `json:"platform"`
			} `json:"devices"`
			CurrentDeviceID string `json:"current_device_id"`
		} `json:"data"`
	}
	decodeBody(t, devicesRec.Body.Bytes(), &devicesPayload)
	if len(devicesPayload.Data.Devices) == 0 {
		t.Fatalf("expected login device to be recorded, got %+v", devicesPayload.Data)
	}
	if devicesPayload.Data.CurrentDeviceID != "test-device-login" {
		t.Fatalf("unexpected current device id: %s", devicesPayload.Data.CurrentDeviceID)
	}
	if devicesPayload.Data.Devices[0].Platform != "iOS" || devicesPayload.Data.Devices[0].DeviceName != "iPhone" {
		t.Fatalf("expected user-agent fallback device fields, got %+v", devicesPayload.Data.Devices[0])
	}

	refreshRec := performJSONWithDevice(t, app, http.MethodPost, "/api/v1/auth/refresh", "", `{
		"refresh_token":"`+loginPayload.Data.Tokens.RefreshToken+`"
	}`, "test-device-refresh", "MacBook Pro", "macOS")
	if refreshRec.Code != http.StatusOK {
		t.Fatalf("refresh status = %d, body = %s", refreshRec.Code, refreshRec.Body.String())
	}
	var refreshPayload struct {
		Data struct {
			Tokens struct {
				AccessToken  string `json:"access_token"`
				RefreshToken string `json:"refresh_token"`
			} `json:"tokens"`
		} `json:"data"`
	}
	decodeBody(t, refreshRec.Body.Bytes(), &refreshPayload)
	if refreshPayload.Data.Tokens.AccessToken == "" || refreshPayload.Data.Tokens.RefreshToken == "" {
		t.Fatalf("expected refresh tokens, got %+v", refreshPayload.Data.Tokens)
	}

	reusedRefreshRec := performJSON(t, app, http.MethodPost, "/api/v1/auth/refresh", "", `{
		"refresh_token":"`+loginPayload.Data.Tokens.RefreshToken+`"
	}`)
	if reusedRefreshRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected rotated refresh token to be rejected, got %d: %s", reusedRefreshRec.Code, reusedRefreshRec.Body.String())
	}

	logoutRec := performJSONWithDevice(t, app, http.MethodPost, "/api/v1/auth/logout", refreshPayload.Data.Tokens.AccessToken, "", "test-device-refresh", "MacBook Pro", "macOS")
	if logoutRec.Code != http.StatusOK {
		t.Fatalf("logout status = %d, body = %s", logoutRec.Code, logoutRec.Body.String())
	}

	logoutAccessRec := performJSON(t, app, http.MethodGet, "/api/v1/me", refreshPayload.Data.Tokens.AccessToken, "")
	if logoutAccessRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected access token to be revoked after logout, got %d: %s", logoutAccessRec.Code, logoutAccessRec.Body.String())
	}

	logoutRefreshRec := performJSON(t, app, http.MethodPost, "/api/v1/auth/refresh", "", `{
		"refresh_token":"`+refreshPayload.Data.Tokens.RefreshToken+`"
	}`)
	if logoutRefreshRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected refresh token to be revoked after logout, got %d: %s", logoutRefreshRec.Code, logoutRefreshRec.Body.String())
	}
}

func TestRegisterValidationRejectsInvalidEmailTimezoneAndLocale(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)

	invalidEmailRec := performJSON(t, app, http.MethodPost, "/api/v1/auth/register", "", `{
		"email":"bad-email",
		"password":"password123",
		"nickname":"worker",
		"timezone":"Asia/Shanghai",
		"locale":"zh-CN"
	}`)
	if invalidEmailRec.Code != http.StatusBadRequest || !strings.Contains(invalidEmailRec.Body.String(), "email 格式不正确") {
		t.Fatalf("invalid email status = %d, body = %s", invalidEmailRec.Code, invalidEmailRec.Body.String())
	}

	invalidTimezoneRec := performJSON(t, app, http.MethodPost, "/api/v1/auth/register", "", `{
		"email":"worker@example.com",
		"password":"password123",
		"nickname":"worker",
		"timezone":"Invalid/Timezone",
		"locale":"zh-CN"
	}`)
	if invalidTimezoneRec.Code != http.StatusBadRequest || !strings.Contains(invalidTimezoneRec.Body.String(), "timezone 不合法") {
		t.Fatalf("invalid timezone status = %d, body = %s", invalidTimezoneRec.Code, invalidTimezoneRec.Body.String())
	}

	invalidLocaleRec := performJSON(t, app, http.MethodPost, "/api/v1/auth/register", "", `{
		"email":"worker@example.com",
		"password":"password123",
		"nickname":"worker",
		"timezone":"Asia/Shanghai",
		"locale":"zh_CN"
	}`)
	if invalidLocaleRec.Code != http.StatusBadRequest || !strings.Contains(invalidLocaleRec.Body.String(), "locale 不合法") {
		t.Fatalf("invalid locale status = %d, body = %s", invalidLocaleRec.Code, invalidLocaleRec.Body.String())
	}
}

func TestQuickNoteAudioConvertAndSyncChangesFlow(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)
	since := time.Now().UTC().Add(-time.Second).Format(time.RFC3339Nano)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	if err := writer.WriteField("content", "会议录音"); err != nil {
		t.Fatalf("write content: %v", err)
	}
	if err := writer.WriteField("audio_duration_ms", "3210"); err != nil {
		t.Fatalf("write duration: %v", err)
	}
	if err := writer.WriteField("waveform_samples", `[1,2,3]`); err != nil {
		t.Fatalf("write waveform: %v", err)
	}
	header := make(textproto.MIMEHeader)
	header.Set("Content-Disposition", `form-data; name="audio"; filename="meeting.webm"`)
	header.Set("Content-Type", "audio/webm")
	part, err := writer.CreatePart(header)
	if err != nil {
		t.Fatalf("create audio part: %v", err)
	}
	audioBytes := []byte("webm-audio-payload")
	if _, err := part.Write(audioBytes); err != nil {
		t.Fatalf("write audio: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close writer: %v", err)
	}

	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/quick-notes", body)
	createReq.Header.Set("Authorization", "Bearer "+token)
	createReq.Header.Set("Content-Type", writer.FormDataContentType())
	createReq.Host = "api.nexdo.test"
	createRec := httptest.NewRecorder()
	app.Router().ServeHTTP(createRec, createReq)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create quick note status = %d, body = %s", createRec.Code, createRec.Body.String())
	}
	var created struct {
		Data struct {
			ID              string  `json:"id"`
			Status          string  `json:"status"`
			AudioFilename   *string `json:"audio_filename"`
			AudioMimeType   *string `json:"audio_mime_type"`
			AudioDurationMS *int64  `json:"audio_duration_ms"`
			AudioURL        *string `json:"audio_url"`
			WaveformSamples []int   `json:"waveform_samples"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)
	if created.Data.ID == "" || created.Data.AudioURL == nil || created.Data.AudioFilename == nil || created.Data.AudioMimeType == nil || created.Data.AudioDurationMS == nil {
		t.Fatalf("unexpected quick note create payload: %+v", created.Data)
	}
	if *created.Data.AudioFilename != "meeting.webm" || *created.Data.AudioMimeType != "audio/webm" || *created.Data.AudioDurationMS != 3210 {
		t.Fatalf("unexpected quick note audio metadata: %+v", created.Data)
	}
	if len(created.Data.WaveformSamples) != 3 || !strings.Contains(*created.Data.AudioURL, "/api/v1/quick-notes/"+created.Data.ID+"/audio") {
		t.Fatalf("unexpected quick note view: %+v", created.Data)
	}

	audioReq := httptest.NewRequest(http.MethodGet, "/api/v1/quick-notes/"+created.Data.ID+"/audio", nil)
	audioReq.Header.Set("Authorization", "Bearer "+token)
	audioRec := httptest.NewRecorder()
	app.Router().ServeHTTP(audioRec, audioReq)
	if audioRec.Code != http.StatusOK {
		t.Fatalf("audio fetch status = %d, body = %s", audioRec.Code, audioRec.Body.String())
	}
	if audioRec.Body.String() != string(audioBytes) {
		t.Fatalf("unexpected audio body: %q", audioRec.Body.String())
	}
	if audioRec.Header().Get("Content-Type") != "audio/webm" || !strings.Contains(audioRec.Header().Get("Content-Disposition"), "meeting.webm") {
		t.Fatalf("unexpected audio headers: %+v", audioRec.Header())
	}

	convertRec := performJSON(t, app, http.MethodPost, "/api/v1/quick-notes/"+created.Data.ID+"/convert", token, `{
		"title":"会议纪要整理",
		"due_at":"2026-04-20T08:00:00Z",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`"
	}`)
	if convertRec.Code != http.StatusOK {
		t.Fatalf("convert quick note status = %d, body = %s", convertRec.Code, convertRec.Body.String())
	}
	var converted struct {
		Data struct {
			ID    string `json:"id"`
			Title string `json:"title"`
		} `json:"data"`
	}
	decodeBody(t, convertRec.Body.Bytes(), &converted)
	if converted.Data.ID == "" || converted.Data.Title != "会议纪要整理" {
		t.Fatalf("unexpected converted reminder: %+v", converted.Data)
	}

	listRec := performJSON(t, app, http.MethodGet, "/api/v1/quick-notes", token, "")
	if listRec.Code != http.StatusOK {
		t.Fatalf("list quick notes status = %d, body = %s", listRec.Code, listRec.Body.String())
	}
	var quickNotes struct {
		Data []struct {
			ID                  string  `json:"id"`
			Status              string  `json:"status"`
			ConvertedReminderID *string `json:"converted_reminder_id"`
		} `json:"data"`
	}
	decodeBody(t, listRec.Body.Bytes(), &quickNotes)
	if len(quickNotes.Data) != 1 || quickNotes.Data[0].ID != created.Data.ID || quickNotes.Data[0].Status != "converted" || quickNotes.Data[0].ConvertedReminderID == nil || *quickNotes.Data[0].ConvertedReminderID != converted.Data.ID {
		t.Fatalf("unexpected quick note list payload: %+v", quickNotes.Data)
	}

	deleteRec := performJSON(t, app, http.MethodDelete, "/api/v1/quick-notes/"+created.Data.ID, token, "")
	if deleteRec.Code != http.StatusOK {
		t.Fatalf("delete quick note status = %d, body = %s", deleteRec.Code, deleteRec.Body.String())
	}

	changesRec := performJSON(t, app, http.MethodGet, "/api/v1/sync/changes?since="+since, token, "")
	if changesRec.Code != http.StatusOK {
		t.Fatalf("changes status = %d, body = %s", changesRec.Code, changesRec.Body.String())
	}
	var changes struct {
		Data struct {
			Reminders []struct {
				ID string `json:"id"`
			} `json:"reminders"`
			DeletedQuickNoteIDs []string `json:"deleted_quick_note_ids"`
		} `json:"data"`
	}
	decodeBody(t, changesRec.Body.Bytes(), &changes)
	if len(changes.Data.Reminders) == 0 || changes.Data.Reminders[0].ID != converted.Data.ID {
		t.Fatalf("expected converted reminder in changes, got %+v", changes.Data.Reminders)
	}
	if len(changes.Data.DeletedQuickNoteIDs) != 1 || changes.Data.DeletedQuickNoteIDs[0] != created.Data.ID {
		t.Fatalf("expected deleted quick note id, got %+v", changes.Data.DeletedQuickNoteIDs)
	}
}

func TestSyncChangesValidationAndResourceDeleteConflict(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	missingSinceRec := performJSON(t, app, http.MethodGet, "/api/v1/sync/changes", token, "")
	if missingSinceRec.Code != http.StatusBadRequest || !strings.Contains(missingSinceRec.Body.String(), "since 参数必须是 RFC3339 时间戳") {
		t.Fatalf("missing since status = %d, body = %s", missingSinceRec.Code, missingSinceRec.Body.String())
	}

	invalidSinceRec := performJSON(t, app, http.MethodGet, "/api/v1/sync/changes?since=not-a-time", token, "")
	if invalidSinceRec.Code != http.StatusBadRequest || !strings.Contains(invalidSinceRec.Body.String(), "since 参数必须是 RFC3339 时间戳") {
		t.Fatalf("invalid since status = %d, body = %s", invalidSinceRec.Code, invalidSinceRec.Body.String())
	}

	createReminderRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"占用资源的提醒",
		"due_at":"2026-04-18T09:00:00Z",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`"
	}`)
	if createReminderRec.Code != http.StatusCreated {
		t.Fatalf("create reminder status = %d, body = %s", createReminderRec.Code, createReminderRec.Body.String())
	}

	deleteListRec := performJSON(t, app, http.MethodDelete, "/api/v1/lists/"+listID, token, "")
	if deleteListRec.Code != http.StatusConflict || !strings.Contains(deleteListRec.Body.String(), "清单仍被使用") {
		t.Fatalf("delete list conflict status = %d, body = %s", deleteListRec.Code, deleteListRec.Body.String())
	}

	deleteGroupRec := performJSON(t, app, http.MethodDelete, "/api/v1/groups/"+groupID, token, "")
	if deleteGroupRec.Code != http.StatusConflict || !strings.Contains(deleteGroupRec.Body.String(), "分组仍被使用") {
		t.Fatalf("delete group conflict status = %d, body = %s", deleteGroupRec.Code, deleteGroupRec.Body.String())
	}
}

func TestReminderListFiltersAndCompleteFlow(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	listRec := performJSON(t, app, http.MethodPost, "/api/v1/lists", token, `{"name":"家庭","color_value":2}`)
	groupRec := performJSON(t, app, http.MethodPost, "/api/v1/groups", token, `{"name":"生活","icon_code_point":99}`)
	tagRec := performJSON(t, app, http.MethodPost, "/api/v1/tags", token, `{"name":"筛选标签","color_value":5}`)
	if listRec.Code != http.StatusCreated || groupRec.Code != http.StatusCreated || tagRec.Code != http.StatusCreated {
		t.Fatalf("resource setup failed: %d %d %d", listRec.Code, groupRec.Code, tagRec.Code)
	}

	var secondList struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	var secondGroup struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	var tagPayload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, listRec.Body.Bytes(), &secondList)
	decodeBody(t, groupRec.Body.Bytes(), &secondGroup)
	decodeBody(t, tagRec.Body.Bytes(), &tagPayload)

	firstReminderRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"工作提醒",
		"due_at":"2026-04-18T09:00:00Z",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`",
		"tag_ids":["`+tagPayload.Data.ID+`"]
	}`)
	secondReminderRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"家庭提醒",
		"due_at":"2026-04-21T09:00:00Z",
		"list_id":"`+secondList.Data.ID+`",
		"group_id":"`+secondGroup.Data.ID+`"
	}`)
	if firstReminderRec.Code != http.StatusCreated || secondReminderRec.Code != http.StatusCreated {
		t.Fatalf("create reminder failed: %d %d", firstReminderRec.Code, secondReminderRec.Code)
	}

	var firstReminder struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	var secondReminder struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, firstReminderRec.Body.Bytes(), &firstReminder)
	decodeBody(t, secondReminderRec.Body.Bytes(), &secondReminder)

	completeRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders/"+firstReminder.Data.ID+"/complete", token, "")
	if completeRec.Code != http.StatusOK {
		t.Fatalf("complete reminder status = %d, body = %s", completeRec.Code, completeRec.Body.String())
	}
	var completed struct {
		Data struct {
			ID          string `json:"id"`
			IsCompleted bool   `json:"is_completed"`
		} `json:"data"`
	}
	decodeBody(t, completeRec.Body.Bytes(), &completed)
	if completed.Data.ID != firstReminder.Data.ID || !completed.Data.IsCompleted {
		t.Fatalf("unexpected complete payload: %+v", completed.Data)
	}

	uncompleteRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders/"+firstReminder.Data.ID+"/uncomplete", token, "")
	if uncompleteRec.Code != http.StatusOK {
		t.Fatalf("uncomplete reminder status = %d, body = %s", uncompleteRec.Code, uncompleteRec.Body.String())
	}

	filterByListRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders?list_ids="+listID, token, "")
	if filterByListRec.Code != http.StatusOK {
		t.Fatalf("filter list status = %d, body = %s", filterByListRec.Code, filterByListRec.Body.String())
	}
	var filterByList struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, filterByListRec.Body.Bytes(), &filterByList)
	if len(filterByList.Data) != 1 || filterByList.Data[0].ID != firstReminder.Data.ID {
		t.Fatalf("unexpected list filter result: %+v", filterByList.Data)
	}

	filterByTagRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders?tag_ids="+tagPayload.Data.ID, token, "")
	if filterByTagRec.Code != http.StatusOK {
		t.Fatalf("filter tag status = %d, body = %s", filterByTagRec.Code, filterByTagRec.Body.String())
	}
	var filterByTag struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, filterByTagRec.Body.Bytes(), &filterByTag)
	if len(filterByTag.Data) != 1 || filterByTag.Data[0].ID != firstReminder.Data.ID {
		t.Fatalf("unexpected tag filter result: %+v", filterByTag.Data)
	}

	filterByDueRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders?due_from=2026-04-20T00:00:00Z&due_to=2026-04-22T00:00:00Z", token, "")
	if filterByDueRec.Code != http.StatusOK {
		t.Fatalf("filter due range status = %d, body = %s", filterByDueRec.Code, filterByDueRec.Body.String())
	}
	var filterByDue struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, filterByDueRec.Body.Bytes(), &filterByDue)
	if len(filterByDue.Data) != 1 || filterByDue.Data[0].ID != secondReminder.Data.ID {
		t.Fatalf("unexpected due filter result: %+v", filterByDue.Data)
	}

	filterByCompletedRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders?is_completed=false", token, "")
	if filterByCompletedRec.Code != http.StatusOK {
		t.Fatalf("filter completed status = %d, body = %s", filterByCompletedRec.Code, filterByCompletedRec.Body.String())
	}
	var filterByCompleted struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, filterByCompletedRec.Body.Bytes(), &filterByCompleted)
	if len(filterByCompleted.Data) != 2 {
		t.Fatalf("expected two incomplete reminders, got %+v", filterByCompleted.Data)
	}

	invalidBoolRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders?is_completed=maybe", token, "")
	if invalidBoolRec.Code != http.StatusBadRequest || !strings.Contains(invalidBoolRec.Body.String(), "is_completed 必须是 true/false/1/0") {
		t.Fatalf("invalid is_completed status = %d, body = %s", invalidBoolRec.Code, invalidBoolRec.Body.String())
	}

	invalidDueRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders?due_from=tomorrow", token, "")
	if invalidDueRec.Code != http.StatusBadRequest || !strings.Contains(invalidDueRec.Body.String(), "due_from 必须是 RFC3339 时间戳") {
		t.Fatalf("invalid due_from status = %d, body = %s", invalidDueRec.Code, invalidDueRec.Body.String())
	}
}

func TestReminderPatchDueAtTriggersRollover(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"每周复盘",
		"due_at":"2026-04-18T09:00:00Z",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`",
		"repeat_rule":"daily"
	}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create recurring reminder status = %d, body = %s", createRec.Code, createRec.Body.String())
	}
	var created struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)

	patchRec := performJSON(t, app, http.MethodPatch, "/api/v1/reminders/"+created.Data.ID, token, `{
		"due_at":"2026-04-19T09:00:00Z"
	}`)
	if patchRec.Code != http.StatusOK {
		t.Fatalf("patch rollover status = %d, body = %s", patchRec.Code, patchRec.Body.String())
	}
	var patched struct {
		Data struct {
			ID         string `json:"id"`
			DueAt      string `json:"due_at"`
			RepeatRule string `json:"repeat_rule"`
		} `json:"data"`
	}
	decodeBody(t, patchRec.Body.Bytes(), &patched)
	if patched.Data.ID == created.Data.ID || patched.Data.DueAt != "2026-04-19T09:00:00Z" || patched.Data.RepeatRule != "daily" {
		t.Fatalf("unexpected patched rollover payload: %+v", patched.Data)
	}

	originalRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders/"+created.Data.ID, token, "")
	if originalRec.Code != http.StatusOK {
		t.Fatalf("original reminder status = %d, body = %s", originalRec.Code, originalRec.Body.String())
	}
	var original struct {
		Data struct {
			IsCompleted bool   `json:"is_completed"`
			RepeatRule  string `json:"repeat_rule"`
		} `json:"data"`
	}
	decodeBody(t, originalRec.Body.Bytes(), &original)
	if !original.Data.IsCompleted || original.Data.RepeatRule != "none" {
		t.Fatalf("unexpected original reminder after rollover: %+v", original.Data)
	}
}

func TestQuickNoteValidationAndAudioNotFound(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)

	emptyJSONRec := performJSON(t, app, http.MethodPost, "/api/v1/quick-notes", token, `{"content":""}`)
	if emptyJSONRec.Code != http.StatusBadRequest || !strings.Contains(emptyJSONRec.Body.String(), "content 必填") {
		t.Fatalf("empty json quick note status = %d, body = %s", emptyJSONRec.Code, emptyJSONRec.Body.String())
	}

	emptyMultipartBody := &bytes.Buffer{}
	emptyWriter := multipart.NewWriter(emptyMultipartBody)
	if err := emptyWriter.Close(); err != nil {
		t.Fatalf("close empty writer: %v", err)
	}
	emptyReq := httptest.NewRequest(http.MethodPost, "/api/v1/quick-notes", emptyMultipartBody)
	emptyReq.Header.Set("Authorization", "Bearer "+token)
	emptyReq.Header.Set("Content-Type", emptyWriter.FormDataContentType())
	emptyRec := httptest.NewRecorder()
	app.Router().ServeHTTP(emptyRec, emptyReq)
	if emptyRec.Code != http.StatusBadRequest || !strings.Contains(emptyRec.Body.String(), "content 或 audio 至少提供一个") {
		t.Fatalf("empty multipart status = %d, body = %s", emptyRec.Code, emptyRec.Body.String())
	}

	invalidDurationBody := &bytes.Buffer{}
	invalidDurationWriter := multipart.NewWriter(invalidDurationBody)
	if err := invalidDurationWriter.WriteField("content", "录音"); err != nil {
		t.Fatalf("write content: %v", err)
	}
	if err := invalidDurationWriter.WriteField("audio_duration_ms", "abc"); err != nil {
		t.Fatalf("write invalid duration: %v", err)
	}
	if err := invalidDurationWriter.Close(); err != nil {
		t.Fatalf("close invalid duration writer: %v", err)
	}
	invalidDurationReq := httptest.NewRequest(http.MethodPost, "/api/v1/quick-notes", invalidDurationBody)
	invalidDurationReq.Header.Set("Authorization", "Bearer "+token)
	invalidDurationReq.Header.Set("Content-Type", invalidDurationWriter.FormDataContentType())
	invalidDurationRec := httptest.NewRecorder()
	app.Router().ServeHTTP(invalidDurationRec, invalidDurationReq)
	if invalidDurationRec.Code != http.StatusBadRequest || !strings.Contains(invalidDurationRec.Body.String(), "audio_duration_ms 必须是大于等于 0 的数字") {
		t.Fatalf("invalid duration status = %d, body = %s", invalidDurationRec.Code, invalidDurationRec.Body.String())
	}

	invalidWaveBody := &bytes.Buffer{}
	invalidWaveWriter := multipart.NewWriter(invalidWaveBody)
	if err := invalidWaveWriter.WriteField("content", "录音"); err != nil {
		t.Fatalf("write content: %v", err)
	}
	if err := invalidWaveWriter.WriteField("waveform_samples", `{"bad":true}`); err != nil {
		t.Fatalf("write invalid waveform: %v", err)
	}
	if err := invalidWaveWriter.Close(); err != nil {
		t.Fatalf("close invalid waveform writer: %v", err)
	}
	invalidWaveReq := httptest.NewRequest(http.MethodPost, "/api/v1/quick-notes", invalidWaveBody)
	invalidWaveReq.Header.Set("Authorization", "Bearer "+token)
	invalidWaveReq.Header.Set("Content-Type", invalidWaveWriter.FormDataContentType())
	invalidWaveRec := httptest.NewRecorder()
	app.Router().ServeHTTP(invalidWaveRec, invalidWaveReq)
	if invalidWaveRec.Code != http.StatusBadRequest || !strings.Contains(invalidWaveRec.Body.String(), "waveform_samples 必须是数字数组 JSON") {
		t.Fatalf("invalid waveform status = %d, body = %s", invalidWaveRec.Code, invalidWaveRec.Body.String())
	}

	textOnlyRec := performJSON(t, app, http.MethodPost, "/api/v1/quick-notes", token, `{"content":"纯文本闪念"}`)
	if textOnlyRec.Code != http.StatusCreated {
		t.Fatalf("text quick note create status = %d, body = %s", textOnlyRec.Code, textOnlyRec.Body.String())
	}
	var textOnly struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, textOnlyRec.Body.Bytes(), &textOnly)

	audioNotFoundRec := performJSON(t, app, http.MethodGet, "/api/v1/quick-notes/"+textOnly.Data.ID+"/audio", token, "")
	if audioNotFoundRec.Code != http.StatusNotFound || !strings.Contains(audioNotFoundRec.Body.String(), "录音不存在") {
		t.Fatalf("audio not found status = %d, body = %s", audioNotFoundRec.Code, audioNotFoundRec.Body.String())
	}
}

func TestCrossUserOwnershipAndNotFound(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	ownerSession := registerTestSessionFor(t, app, "owner@example.com", "owner")
	otherSession := registerTestSessionFor(t, app, "other@example.com", "other")
	listID, groupID := firstListAndGroupIDs(t, app, ownerSession.AccessToken)

	deviceProbeRec := performJSONWithDevice(t, app, http.MethodGet, "/api/v1/me", ownerSession.AccessToken, "", "owner-device-1", "Owner iPhone", "iOS")
	if deviceProbeRec.Code != http.StatusOK {
		t.Fatalf("owner device probe status = %d, body = %s", deviceProbeRec.Code, deviceProbeRec.Body.String())
	}

	devicesRec := performJSONWithDevice(t, app, http.MethodGet, "/api/v1/me/devices", ownerSession.AccessToken, "", "owner-device-1", "Owner iPhone", "iOS")
	if devicesRec.Code != http.StatusOK {
		t.Fatalf("owner devices status = %d, body = %s", devicesRec.Code, devicesRec.Body.String())
	}
	var devicesPayload struct {
		Data struct {
			Devices []struct {
				ID string `json:"id"`
			} `json:"devices"`
		} `json:"data"`
	}
	decodeBody(t, devicesRec.Body.Bytes(), &devicesPayload)
	if len(devicesPayload.Data.Devices) != 1 {
		t.Fatalf("expected one owner device, got %+v", devicesPayload.Data.Devices)
	}

	reminderRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", ownerSession.AccessToken, `{
		"title":"owner reminder",
		"due_at":"2026-04-18T09:00:00Z",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`"
	}`)
	if reminderRec.Code != http.StatusCreated {
		t.Fatalf("owner create reminder status = %d, body = %s", reminderRec.Code, reminderRec.Body.String())
	}
	var reminderPayload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, reminderRec.Body.Bytes(), &reminderPayload)

	quickNoteRec := performJSON(t, app, http.MethodPost, "/api/v1/quick-notes", ownerSession.AccessToken, `{"content":"owner text note"}`)
	if quickNoteRec.Code != http.StatusCreated {
		t.Fatalf("owner create quick note status = %d, body = %s", quickNoteRec.Code, quickNoteRec.Body.String())
	}
	var quickNotePayload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, quickNoteRec.Body.Bytes(), &quickNotePayload)

	otherReminderRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders/"+reminderPayload.Data.ID, otherSession.AccessToken, "")
	if otherReminderRec.Code != http.StatusNotFound {
		t.Fatalf("cross-user reminder status = %d, body = %s", otherReminderRec.Code, otherReminderRec.Body.String())
	}

	otherQuickNoteAudioRec := performJSON(t, app, http.MethodGet, "/api/v1/quick-notes/"+quickNotePayload.Data.ID+"/audio", otherSession.AccessToken, "")
	if otherQuickNoteAudioRec.Code != http.StatusNotFound {
		t.Fatalf("cross-user quick note audio status = %d, body = %s", otherQuickNoteAudioRec.Code, otherQuickNoteAudioRec.Body.String())
	}

	otherDeleteDeviceRec := performJSON(t, app, http.MethodDelete, "/api/v1/me/devices/"+devicesPayload.Data.Devices[0].ID, otherSession.AccessToken, "")
	if otherDeleteDeviceRec.Code != http.StatusNotFound {
		t.Fatalf("cross-user device delete status = %d, body = %s", otherDeleteDeviceRec.Code, otherDeleteDeviceRec.Body.String())
	}
}

func TestReminderTagReplacementAndDeletedTagCleanup(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	firstTagRec := performJSON(t, app, http.MethodPost, "/api/v1/tags", token, `{"name":"标签一","color_value":1}`)
	secondTagRec := performJSON(t, app, http.MethodPost, "/api/v1/tags", token, `{"name":"标签二","color_value":2}`)
	if firstTagRec.Code != http.StatusCreated || secondTagRec.Code != http.StatusCreated {
		t.Fatalf("create tags failed: %d %d", firstTagRec.Code, secondTagRec.Code)
	}
	var firstTag struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	var secondTag struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, firstTagRec.Body.Bytes(), &firstTag)
	decodeBody(t, secondTagRec.Body.Bytes(), &secondTag)

	reminderRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"标签提醒",
		"due_at":"2026-04-18T09:00:00Z",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`",
		"tag_ids":["`+firstTag.Data.ID+`"]
	}`)
	if reminderRec.Code != http.StatusCreated {
		t.Fatalf("create tagged reminder status = %d, body = %s", reminderRec.Code, reminderRec.Body.String())
	}
	var reminderPayload struct {
		Data struct {
			ID   string `json:"id"`
			Tags []struct {
				ID string `json:"id"`
			} `json:"tags"`
		} `json:"data"`
	}
	decodeBody(t, reminderRec.Body.Bytes(), &reminderPayload)
	if len(reminderPayload.Data.Tags) != 1 || reminderPayload.Data.Tags[0].ID != firstTag.Data.ID {
		t.Fatalf("unexpected initial reminder tags: %+v", reminderPayload.Data.Tags)
	}

	replaceTagsRec := performJSON(t, app, http.MethodPatch, "/api/v1/reminders/"+reminderPayload.Data.ID, token, `{
		"tag_ids":["`+secondTag.Data.ID+`"]
	}`)
	if replaceTagsRec.Code != http.StatusOK {
		t.Fatalf("replace reminder tags status = %d, body = %s", replaceTagsRec.Code, replaceTagsRec.Body.String())
	}
	var replaced struct {
		Data struct {
			Tags []struct {
				ID string `json:"id"`
			} `json:"tags"`
		} `json:"data"`
	}
	decodeBody(t, replaceTagsRec.Body.Bytes(), &replaced)
	if len(replaced.Data.Tags) != 1 || replaced.Data.Tags[0].ID != secondTag.Data.ID {
		t.Fatalf("unexpected replaced reminder tags: %+v", replaced.Data.Tags)
	}

	deleteTagRec := performJSON(t, app, http.MethodDelete, "/api/v1/tags/"+secondTag.Data.ID, token, "")
	if deleteTagRec.Code != http.StatusOK {
		t.Fatalf("delete tag status = %d, body = %s", deleteTagRec.Code, deleteTagRec.Body.String())
	}

	getReminderRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders/"+reminderPayload.Data.ID, token, "")
	if getReminderRec.Code != http.StatusOK {
		t.Fatalf("get reminder after tag delete status = %d, body = %s", getReminderRec.Code, getReminderRec.Body.String())
	}
	var afterDelete struct {
		Data struct {
			ID   string `json:"id"`
			Tags []struct {
				ID string `json:"id"`
			} `json:"tags"`
		} `json:"data"`
	}
	decodeBody(t, getReminderRec.Body.Bytes(), &afterDelete)
	if afterDelete.Data.ID != reminderPayload.Data.ID {
		t.Fatalf("unexpected reminder id after tag delete: %+v", afterDelete.Data)
	}
	if len(afterDelete.Data.Tags) != 0 {
		t.Fatalf("expected reminder tags to be cleaned after tag delete, got %+v", afterDelete.Data.Tags)
	}
}

func TestQuickNotePatchValidationMissingAudioFileAndDeleteVisibility(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/quick-notes", token, `{"content":"待处理闪念"}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create quick note status = %d, body = %s", createRec.Code, createRec.Body.String())
	}
	var created struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)

	invalidPatchRec := performJSON(t, app, http.MethodPatch, "/api/v1/quick-notes/"+created.Data.ID, token, `{"status":"archived"}`)
	if invalidPatchRec.Code != http.StatusBadRequest || !strings.Contains(invalidPatchRec.Body.String(), "status 只能是 draft 或 converted") {
		t.Fatalf("invalid quick note patch status = %d, body = %s", invalidPatchRec.Code, invalidPatchRec.Body.String())
	}

	invalidConvertedRec := performJSON(t, app, http.MethodPatch, "/api/v1/quick-notes/"+created.Data.ID, token, `{"status":"converted"}`)
	if invalidConvertedRec.Code != http.StatusBadRequest || !strings.Contains(invalidConvertedRec.Body.String(), "converted_reminder_id") {
		t.Fatalf("invalid converted status = %d, body = %s", invalidConvertedRec.Code, invalidConvertedRec.Body.String())
	}

	audioPath := filepath.Join(t.TempDir(), "missing-audio.webm")
	audioFilename := "missing-audio.webm"
	audioMime := "audio/webm"
	if err := app.db.Model(&models.QuickNote{}).Where("id = ?", created.Data.ID).Updates(map[string]any{
		"audio_key":       audioPath,
		"audio_filename":  audioFilename,
		"audio_mime_type": audioMime,
	}).Error; err != nil {
		t.Fatalf("seed missing audio metadata: %v", err)
	}

	missingAudioRec := performJSON(t, app, http.MethodGet, "/api/v1/quick-notes/"+created.Data.ID+"/audio", token, "")
	if missingAudioRec.Code != http.StatusNotFound || !strings.Contains(missingAudioRec.Body.String(), "录音不存在") {
		t.Fatalf("missing audio file status = %d, body = %s", missingAudioRec.Code, missingAudioRec.Body.String())
	}

	deleteRec := performJSON(t, app, http.MethodDelete, "/api/v1/quick-notes/"+created.Data.ID, token, "")
	if deleteRec.Code != http.StatusOK {
		t.Fatalf("delete quick note status = %d, body = %s", deleteRec.Code, deleteRec.Body.String())
	}

	listRec := performJSON(t, app, http.MethodGet, "/api/v1/quick-notes", token, "")
	if listRec.Code != http.StatusOK {
		t.Fatalf("list quick notes status = %d, body = %s", listRec.Code, listRec.Body.String())
	}
	var listPayload struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, listRec.Body.Bytes(), &listPayload)
	if len(listPayload.Data) != 0 {
		t.Fatalf("expected deleted quick note to be hidden from list, got %+v", listPayload.Data)
	}

	convertDeletedRec := performJSON(t, app, http.MethodPost, "/api/v1/quick-notes/"+created.Data.ID+"/convert", token, `{
		"title":"删除后不应转换",
		"due_at":"2026-04-20T08:00:00Z",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`"
	}`)
	if convertDeletedRec.Code != http.StatusNotFound {
		t.Fatalf("convert deleted quick note status = %d, body = %s", convertDeletedRec.Code, convertDeletedRec.Body.String())
	}

	audioDeletedRec := performJSON(t, app, http.MethodGet, "/api/v1/quick-notes/"+created.Data.ID+"/audio", token, "")
	if audioDeletedRec.Code != http.StatusNotFound {
		t.Fatalf("audio deleted quick note status = %d, body = %s", audioDeletedRec.Code, audioDeletedRec.Body.String())
	}
}

func TestQuickNoteDeleteRemovesStoredAudioFile(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	if err := writer.WriteField("content", "待删除录音"); err != nil {
		t.Fatalf("write content: %v", err)
	}
	header := make(textproto.MIMEHeader)
	header.Set("Content-Disposition", `form-data; name="audio"; filename="delete-me.webm"`)
	header.Set("Content-Type", "audio/webm")
	part, err := writer.CreatePart(header)
	if err != nil {
		t.Fatalf("create audio part: %v", err)
	}
	if _, err := part.Write([]byte("delete-audio")); err != nil {
		t.Fatalf("write audio: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close writer: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/quick-notes", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	app.Router().ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create quick note status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var created struct {
		Data struct {
			ID       string  `json:"id"`
			AudioKey *string `json:"audio_key"`
		} `json:"data"`
	}
	decodeBody(t, rec.Body.Bytes(), &created)
	if created.Data.AudioKey == nil || *created.Data.AudioKey == "" {
		t.Fatalf("expected audio_key, got %+v", created.Data)
	}
	if _, err := os.Stat(*created.Data.AudioKey); err != nil {
		t.Fatalf("expected audio file to exist before delete: %v", err)
	}

	deleteRec := performJSON(t, app, http.MethodDelete, "/api/v1/quick-notes/"+created.Data.ID, token, "")
	if deleteRec.Code != http.StatusOK {
		t.Fatalf("delete quick note status = %d, body = %s", deleteRec.Code, deleteRec.Body.String())
	}
	if _, err := os.Stat(*created.Data.AudioKey); !os.IsNotExist(err) {
		t.Fatalf("expected audio file to be removed, stat err = %v", err)
	}
}

func TestQuickNoteDeleteRollsBackWhenAudioCleanupFails(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/quick-notes", token, `{"content":"需要回滚"}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create quick note status = %d, body = %s", createRec.Code, createRec.Body.String())
	}
	var created struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)

	audioDir := filepath.Join(t.TempDir(), "audio-dir-instead-of-file")
	if err := os.MkdirAll(audioDir, 0o755); err != nil {
		t.Fatalf("mkdir audio dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(audioDir, "nested.webm"), []byte("not-empty"), 0o644); err != nil {
		t.Fatalf("seed nested file: %v", err)
	}
	audioFilename := "bad-audio.webm"
	audioMime := "audio/webm"
	if err := app.db.Model(&models.QuickNote{}).Where("id = ?", created.Data.ID).Updates(map[string]any{
		"audio_key":       audioDir,
		"audio_filename":  audioFilename,
		"audio_mime_type": audioMime,
	}).Error; err != nil {
		t.Fatalf("seed broken audio metadata: %v", err)
	}

	deleteRec := performJSON(t, app, http.MethodDelete, "/api/v1/quick-notes/"+created.Data.ID, token, "")
	if deleteRec.Code != http.StatusInternalServerError {
		t.Fatalf("expected delete to fail when audio cleanup fails, got %d: %s", deleteRec.Code, deleteRec.Body.String())
	}

	listRec := performJSON(t, app, http.MethodGet, "/api/v1/quick-notes", token, "")
	if listRec.Code != http.StatusOK {
		t.Fatalf("list quick notes status = %d, body = %s", listRec.Code, listRec.Body.String())
	}
	var listPayload struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, listRec.Body.Bytes(), &listPayload)
	if len(listPayload.Data) != 1 || listPayload.Data[0].ID != created.Data.ID {
		t.Fatalf("expected quick note deletion rollback, got %+v", listPayload.Data)
	}
}

func TestQuickNoteMultipartCreateRemovesAudioOnDatabaseFailure(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	if err := writer.WriteField("content", "写文件后失败"); err != nil {
		t.Fatalf("write content: %v", err)
	}
	header := make(textproto.MIMEHeader)
	header.Set("Content-Disposition", `form-data; name="audio"; filename="rollback.webm"`)
	header.Set("Content-Type", "audio/webm")
	part, err := writer.CreatePart(header)
	if err != nil {
		t.Fatalf("create audio part: %v", err)
	}
	if _, err := part.Write([]byte("rollback-audio")); err != nil {
		t.Fatalf("write audio: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close writer: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/quick-notes", body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(rec)
	ctx.Request = req
	ctx.Set("userID", "rollback-user")

	sqlDB, err := app.db.DB()
	if err != nil {
		t.Fatalf("db handle: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close db: %v", err)
	}

	err = app.handleCreateQuickNote(ctx)
	if err == nil {
		t.Fatal("expected create quick note to fail after database close")
	}

	audioRoot := filepath.Join(app.cfg.AudioStorageDir, "quick-notes", "rollback-user")
	if _, statErr := os.Stat(audioRoot); !os.IsNotExist(statErr) {
		t.Fatalf("expected rollback audio files to be cleaned, stat err = %v", statErr)
	}
}

func TestReminderPatchEmptyTagIDsClearsTags(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	tagRec := performJSON(t, app, http.MethodPost, "/api/v1/tags", token, `{"name":"待清空标签","color_value":3}`)
	if tagRec.Code != http.StatusCreated {
		t.Fatalf("create tag status = %d, body = %s", tagRec.Code, tagRec.Body.String())
	}
	var tagPayload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, tagRec.Body.Bytes(), &tagPayload)

	reminderRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"带标签提醒",
		"due_at":"2026-04-18T09:00:00Z",
		"list_id":"`+listID+`",
		"group_id":"`+groupID+`",
		"tag_ids":["`+tagPayload.Data.ID+`"]
	}`)
	if reminderRec.Code != http.StatusCreated {
		t.Fatalf("create reminder status = %d, body = %s", reminderRec.Code, reminderRec.Body.String())
	}
	var created struct {
		Data struct {
			ID   string `json:"id"`
			Tags []struct {
				ID string `json:"id"`
			} `json:"tags"`
		} `json:"data"`
	}
	decodeBody(t, reminderRec.Body.Bytes(), &created)
	if len(created.Data.Tags) != 1 || created.Data.Tags[0].ID != tagPayload.Data.ID {
		t.Fatalf("unexpected initial tags: %+v", created.Data.Tags)
	}

	clearTagsRec := performJSON(t, app, http.MethodPatch, "/api/v1/reminders/"+created.Data.ID, token, `{
		"tag_ids":[]
	}`)
	if clearTagsRec.Code != http.StatusOK {
		t.Fatalf("clear reminder tags status = %d, body = %s", clearTagsRec.Code, clearTagsRec.Body.String())
	}
	var cleared struct {
		Data struct {
			ID   string `json:"id"`
			Tags []struct {
				ID string `json:"id"`
			} `json:"tags"`
		} `json:"data"`
	}
	decodeBody(t, clearTagsRec.Body.Bytes(), &cleared)
	if cleared.Data.ID != created.Data.ID {
		t.Fatalf("unexpected reminder after clear tags: %+v", cleared.Data)
	}
	if len(cleared.Data.Tags) != 0 {
		t.Fatalf("expected tags to be cleared, got %+v", cleared.Data.Tags)
	}
}

func TestReminderMultiValueQueryCombinationFilters(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	defaultListID, defaultGroupID := firstListAndGroupIDs(t, app, token)

	listOneRec := performJSON(t, app, http.MethodPost, "/api/v1/lists", token, `{"name":"项目A","color_value":1}`)
	listTwoRec := performJSON(t, app, http.MethodPost, "/api/v1/lists", token, `{"name":"项目B","color_value":2}`)
	groupOneRec := performJSON(t, app, http.MethodPost, "/api/v1/groups", token, `{"name":"分组A","icon_code_point":11}`)
	groupTwoRec := performJSON(t, app, http.MethodPost, "/api/v1/groups", token, `{"name":"分组B","icon_code_point":12}`)
	tagOneRec := performJSON(t, app, http.MethodPost, "/api/v1/tags", token, `{"name":"标签A","color_value":1}`)
	tagTwoRec := performJSON(t, app, http.MethodPost, "/api/v1/tags", token, `{"name":"标签B","color_value":2}`)
	if listOneRec.Code != http.StatusCreated || listTwoRec.Code != http.StatusCreated || groupOneRec.Code != http.StatusCreated || groupTwoRec.Code != http.StatusCreated || tagOneRec.Code != http.StatusCreated || tagTwoRec.Code != http.StatusCreated {
		t.Fatalf("setup resource failed: %d %d %d %d %d %d", listOneRec.Code, listTwoRec.Code, groupOneRec.Code, groupTwoRec.Code, tagOneRec.Code, tagTwoRec.Code)
	}

	var listOne, listTwo, groupOne, groupTwo, tagOne, tagTwo struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, listOneRec.Body.Bytes(), &listOne)
	decodeBody(t, listTwoRec.Body.Bytes(), &listTwo)
	decodeBody(t, groupOneRec.Body.Bytes(), &groupOne)
	decodeBody(t, groupTwoRec.Body.Bytes(), &groupTwo)
	decodeBody(t, tagOneRec.Body.Bytes(), &tagOne)
	decodeBody(t, tagTwoRec.Body.Bytes(), &tagTwo)

	matchRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"命中组合条件",
		"due_at":"2026-04-18T09:00:00Z",
		"list_id":"`+listOne.Data.ID+`",
		"group_id":"`+groupOne.Data.ID+`",
		"tag_ids":["`+tagOne.Data.ID+`"]
	}`)
	otherListRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"只命中tag",
		"due_at":"2026-04-18T10:00:00Z",
		"list_id":"`+listTwo.Data.ID+`",
		"group_id":"`+groupOne.Data.ID+`",
		"tag_ids":["`+tagOne.Data.ID+`"]
	}`)
	otherGroupRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"只命中list",
		"due_at":"2026-04-18T11:00:00Z",
		"list_id":"`+listOne.Data.ID+`",
		"group_id":"`+groupTwo.Data.ID+`",
		"tag_ids":["`+tagTwo.Data.ID+`"]
	}`)
	defaultResourceRec := performJSON(t, app, http.MethodPost, "/api/v1/reminders", token, `{
		"title":"默认资源提醒",
		"due_at":"2026-04-18T12:00:00Z",
		"list_id":"`+defaultListID+`",
		"group_id":"`+defaultGroupID+`"
	}`)
	if matchRec.Code != http.StatusCreated || otherListRec.Code != http.StatusCreated || otherGroupRec.Code != http.StatusCreated || defaultResourceRec.Code != http.StatusCreated {
		t.Fatalf("create reminders failed: %d %d %d %d", matchRec.Code, otherListRec.Code, otherGroupRec.Code, defaultResourceRec.Code)
	}

	var matched struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, matchRec.Body.Bytes(), &matched)

	comboRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders?list_ids="+listOne.Data.ID+","+defaultListID+"&group_ids="+groupOne.Data.ID+"&tag_ids="+tagOne.Data.ID, token, "")
	if comboRec.Code != http.StatusOK {
		t.Fatalf("combo filter status = %d, body = %s", comboRec.Code, comboRec.Body.String())
	}
	var comboPayload struct {
		Data []struct {
			ID    string `json:"id"`
			Title string `json:"title"`
		} `json:"data"`
	}
	decodeBody(t, comboRec.Body.Bytes(), &comboPayload)
	if len(comboPayload.Data) != 1 || comboPayload.Data[0].ID != matched.Data.ID {
		t.Fatalf("unexpected combo filter result: %+v", comboPayload.Data)
	}

	queryArrayRec := performJSON(t, app, http.MethodGet, "/api/v1/reminders?list_ids="+listOne.Data.ID+"&list_ids="+listTwo.Data.ID+"&group_ids="+groupOne.Data.ID+"&tag_ids="+tagOne.Data.ID, token, "")
	if queryArrayRec.Code != http.StatusOK {
		t.Fatalf("query array filter status = %d, body = %s", queryArrayRec.Code, queryArrayRec.Body.String())
	}
	var queryArrayPayload struct {
		Data []struct {
			Title string `json:"title"`
		} `json:"data"`
	}
	decodeBody(t, queryArrayRec.Body.Bytes(), &queryArrayPayload)
	if len(queryArrayPayload.Data) != 2 {
		t.Fatalf("expected two reminders from repeated list_ids filter, got %+v", queryArrayPayload.Data)
	}
}

func newTestApp(t *testing.T) *Application {
	t.Helper()

	dbFile := filepath.Join(t.TempDir(), "test.db")
	audioDir := filepath.Join(t.TempDir(), "audio")
	app, err := New(config.Config{
		Addr:              ":0",
		DatabaseURL:       "sqlite://" + dbFile,
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

func registerTestUser(t *testing.T, app *Application) string {
	t.Helper()
	return registerTestSession(t, app).AccessToken
}

type testSession struct {
	AccessToken  string
	RefreshToken string
}

func registerTestSession(t *testing.T, app *Application) testSession {
	t.Helper()

	return registerTestSessionFor(t, app, "worker2@example.com", "worker2")
}

func registerTestSessionFor(t *testing.T, app *Application, email, nickname string) testSession {
	t.Helper()

	rec := performJSON(t, app, http.MethodPost, "/api/v1/auth/register", "", `{
		"email":"`+email+`",
		"password":"password123",
		"nickname":"`+nickname+`",
		"timezone":"Asia/Shanghai",
		"locale":"zh-CN"
	}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("register status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var payload struct {
		Data struct {
			Tokens struct {
				AccessToken  string `json:"access_token"`
				RefreshToken string `json:"refresh_token"`
			} `json:"tokens"`
		} `json:"data"`
	}
	decodeBody(t, rec.Body.Bytes(), &payload)
	return testSession{
		AccessToken:  payload.Data.Tokens.AccessToken,
		RefreshToken: payload.Data.Tokens.RefreshToken,
	}
}

func firstListAndGroupIDs(t *testing.T, app *Application, token string) (string, string) {
	t.Helper()

	rec := performJSON(t, app, http.MethodGet, "/api/v1/sync/bootstrap", token, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("bootstrap status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var payload struct {
		Data struct {
			Lists []struct {
				ID string `json:"id"`
			} `json:"lists"`
			Groups []struct {
				ID string `json:"id"`
			} `json:"groups"`
		} `json:"data"`
	}
	decodeBody(t, rec.Body.Bytes(), &payload)
	if len(payload.Data.Lists) == 0 || len(payload.Data.Groups) == 0 {
		t.Fatalf("expected seeded list/group, got %+v", payload.Data)
	}
	return payload.Data.Lists[0].ID, payload.Data.Groups[0].ID
}

func performJSON(t *testing.T, app *Application, method, path, token, body string) *httptest.ResponseRecorder {
	t.Helper()

	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	rec := httptest.NewRecorder()
	app.Router().ServeHTTP(rec, req)
	return rec
}

func performJSONWithDevice(t *testing.T, app *Application, method, path, token, body, deviceID, deviceName, platform string) *httptest.ResponseRecorder {
	t.Helper()

	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set(deviceIDHeader, deviceID)
	if deviceName != "" {
		req.Header.Set(deviceNameHeader, deviceName)
	}
	if platform != "" {
		req.Header.Set(devicePlatformHeader, platform)
	}
	userAgent := "NexdoTest/1.0 (iOS; iPhone)"
	if platform != "" || deviceName != "" {
		userAgent = "NexdoTest/1.0 (" + valueOrDefaultString(platform, "unknown") + "; " + valueOrDefaultString(deviceName, "device") + ")"
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("X-Forwarded-For", "203.0.113.8")

	rec := httptest.NewRecorder()
	app.Router().ServeHTTP(rec, req)
	return rec
}

func valueOrDefaultString(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func decodeBody(t *testing.T, body []byte, dst any) {
	t.Helper()
	if err := json.Unmarshal(body, dst); err != nil {
		t.Fatalf("decode body: %v, body=%s", err, string(body))
	}
}

func TestMain(m *testing.M) {
	os.Exit(m.Run())
}
