package app

import (
	"testing"

	"nexdo-server-golang/internal/models"
	jwtutil "nexdo-server-golang/internal/pkg/jwt"
)

func TestReminderServicePatchReplacesAndClearsTags(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	userID := mustUserIDFromToken(t, app, token)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	firstTag := createTagForTest(t, app, token, "service-tag-1")
	secondTag := createTagForTest(t, app, token, "service-tag-2")

	service := newReminderService(app)
	created, err := service.create(userID, reminderPayload{
		Title:   "service reminder",
		DueAt:   "2026-04-18T09:00:00Z",
		ListID:  listID,
		GroupID: groupID,
		TagIDs:  []string{firstTag},
	})
	if err != nil {
		t.Fatalf("create reminder: %v", err)
	}
	if len(created.Tags) != 1 || created.Tags[0].ID != firstTag {
		t.Fatalf("unexpected created tags: %+v", created.Tags)
	}

	replaced, err := service.patch(userID, created.ID, updateReminderPayload{TagIDs: []string{secondTag}})
	if err != nil {
		t.Fatalf("replace tags: %v", err)
	}
	if len(replaced.Tags) != 1 || replaced.Tags[0].ID != secondTag {
		t.Fatalf("unexpected replaced tags: %+v", replaced.Tags)
	}

	cleared, err := service.patch(userID, created.ID, updateReminderPayload{TagIDs: []string{}})
	if err != nil {
		t.Fatalf("clear tags: %v", err)
	}
	if len(cleared.Tags) != 0 {
		t.Fatalf("expected tags to be cleared, got %+v", cleared.Tags)
	}
}

func TestReminderServiceCompleteRecurringRolloverPreservesTagsAndWritesLog(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	userID := mustUserIDFromToken(t, app, token)
	listID, groupID := firstListAndGroupIDs(t, app, token)
	tagID := createTagForTest(t, app, token, "service-rollover-tag")

	service := newReminderService(app)
	created, err := service.create(userID, reminderPayload{
		Title:      "weekly review",
		DueAt:      "2026-04-18T09:00:00Z",
		ListID:     listID,
		GroupID:    groupID,
		TagIDs:     []string{tagID},
		RepeatRule: stringPtr("weekly"),
	})
	if err != nil {
		t.Fatalf("create recurring reminder: %v", err)
	}

	next, err := service.complete(userID, created.ID)
	if err != nil {
		t.Fatalf("complete recurring reminder: %v", err)
	}
	if next.ID == created.ID {
		t.Fatal("expected rollover to create a new reminder")
	}
	if next.DueAt != "2026-04-25T09:00:00Z" {
		t.Fatalf("unexpected next due date: %s", next.DueAt)
	}
	if len(next.Tags) != 1 || next.Tags[0].ID != tagID {
		t.Fatalf("expected tags to be preserved, got %+v", next.Tags)
	}

	var original models.Reminder
	if err := app.db.Where("id = ?", created.ID).First(&original).Error; err != nil {
		t.Fatalf("load original reminder: %v", err)
	}
	if !original.IsCompleted || original.RepeatRule != "none" {
		t.Fatalf("unexpected original reminder state: %+v", original)
	}

	logs, err := service.logs(userID, created.ID)
	if err != nil {
		t.Fatalf("load completion logs: %v", err)
	}
	if len(logs) != 1 {
		t.Fatalf("expected one completion log, got %d", len(logs))
	}
	if logs[0].NextDueAt != "2026-04-25T09:00:00Z" {
		t.Fatalf("unexpected log next due date: %+v", logs[0])
	}
}

func TestReminderServiceCreateRejectsForeignTag(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	ownerToken := registerTestUser(t, app)
	otherToken := registerTestSessionFor(t, app, "service-other@example.com", "service-other").AccessToken
	ownerUserID := mustUserIDFromToken(t, app, ownerToken)
	listID, groupID := firstListAndGroupIDs(t, app, ownerToken)
	foreignTagID := createTagForTest(t, app, otherToken, "foreign-tag")

	service := newReminderService(app)
	if _, err := service.create(ownerUserID, reminderPayload{
		Title:   "should fail",
		DueAt:   "2026-04-18T09:00:00Z",
		ListID:  listID,
		GroupID: groupID,
		TagIDs:  []string{foreignTagID},
	}); err == nil {
		t.Fatal("expected create reminder to reject foreign tag")
	}
}

func createTagForTest(t *testing.T, app *Application, token, name string) string {
	t.Helper()

	rec := performJSON(t, app, "POST", "/api/v1/tags", token, `{"name":"`+name+`","color_value":1}`)
	if rec.Code != 201 {
		t.Fatalf("create tag status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var payload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, rec.Body.Bytes(), &payload)
	return payload.Data.ID
}

func mustUserIDFromToken(t *testing.T, app *Application, accessToken string) string {
	t.Helper()

	claims, err := jwtutil.Parse(accessToken, app.cfg.JWTAccessSecret, "access")
	if err != nil {
		t.Fatalf("parse access token: %v", err)
	}
	return claims.Subject
}

func stringPtr(value string) *string {
	return &value
}
