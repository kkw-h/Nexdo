package app

import (
	"testing"

	"nexdo-server-golang/internal/models"
)

func TestReminderRepositoryCreateAndSoftDeleteManageTagRelations(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	userID := mustUserIDFromToken(t, app, token)
	listID, groupID := firstListAndGroupIDs(t, app, token)
	tagID := createTagForTest(t, app, token, "repo-tag")

	repo := reminderRepository{db: app.db}
	now := nowISO()
	item := models.Reminder{
		ID:                  newID(),
		UserID:              userID,
		Title:               "repo reminder",
		Note:                "",
		DueAt:               "2026-04-18T09:00:00Z",
		ListID:              listID,
		GroupID:             groupID,
		NotificationEnabled: true,
		RepeatRule:          "none",
		CreatedAt:           now,
		UpdatedAt:           now,
	}
	if err := repo.create(&item, []string{tagID}); err != nil {
		t.Fatalf("create reminder: %v", err)
	}

	tagIDs, err := app.reminderTagIDs(item.ID)
	if err != nil {
		t.Fatalf("reminderTagIDs after create: %v", err)
	}
	if len(tagIDs) != 1 || tagIDs[0] != tagID {
		t.Fatalf("unexpected tag relations after create: %+v", tagIDs)
	}

	if err := repo.softDelete(&item); err != nil {
		t.Fatalf("softDelete: %v", err)
	}
	if item.DeletedAt == nil {
		t.Fatal("expected deleted_at to be set")
	}

	tagIDs, err = app.reminderTagIDs(item.ID)
	if err != nil {
		t.Fatalf("reminderTagIDs after delete: %v", err)
	}
	if len(tagIDs) != 0 {
		t.Fatalf("expected tag relations to be removed, got %+v", tagIDs)
	}
}

func TestReminderRepositoryCreatePersistsFalseNotificationEnabled(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	userID := mustUserIDFromToken(t, app, token)
	listID, groupID := firstListAndGroupIDs(t, app, token)

	repo := reminderRepository{db: app.db}
	now := nowISO()
	item := models.Reminder{
		ID:                  newID(),
		UserID:              userID,
		Title:               "repo reminder false notification",
		Note:                "",
		DueAt:               "2026-04-18T09:00:00Z",
		RemindBeforeMinutes: 15,
		ListID:              listID,
		GroupID:             groupID,
		NotificationEnabled: false,
		RepeatRule:          "none",
		CreatedAt:           now,
		UpdatedAt:           now,
	}
	if err := repo.create(&item, nil); err != nil {
		t.Fatalf("create reminder: %v", err)
	}

	stored, err := repo.get(userID, item.ID)
	if err != nil {
		t.Fatalf("get created reminder: %v", err)
	}
	if stored.NotificationEnabled {
		t.Fatalf("expected notification_enabled=false, got %+v", stored)
	}
	if stored.RemindBeforeMinutes != 15 {
		t.Fatalf("expected remind_before_minutes=15, got %+v", stored)
	}
}

func TestReminderRepositoryRolloverCreatesNextReminderAndLog(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	userID := mustUserIDFromToken(t, app, token)
	listID, groupID := firstListAndGroupIDs(t, app, token)
	tagID := createTagForTest(t, app, token, "repo-rollover-tag")

	repo := reminderRepository{db: app.db}
	now := nowISO()
	current := models.Reminder{
		ID:                  newID(),
		UserID:              userID,
		Title:               "repo recurring reminder",
		Note:                "",
		DueAt:               "2026-04-18T09:00:00Z",
		ListID:              listID,
		GroupID:             groupID,
		NotificationEnabled: true,
		RepeatRule:          "weekly",
		CreatedAt:           now,
		UpdatedAt:           now,
	}
	if err := repo.create(&current, []string{tagID}); err != nil {
		t.Fatalf("create recurring reminder: %v", err)
	}

	next := current
	next.ID = newID()
	next.DueAt = "2026-04-25T09:00:00Z"
	next.IsCompleted = false
	next.CreatedAt = nowISO()
	next.UpdatedAt = next.CreatedAt
	if err := repo.rollover(userID, &current, &next, []string{tagID}, next.DueAt); err != nil {
		t.Fatalf("rollover: %v", err)
	}

	storedCurrent, err := repo.get(userID, current.ID)
	if err != nil {
		t.Fatalf("get current: %v", err)
	}
	if !storedCurrent.IsCompleted || storedCurrent.RepeatRule != "none" {
		t.Fatalf("unexpected current state after rollover: %+v", storedCurrent)
	}

	storedNext, err := repo.get(userID, next.ID)
	if err != nil {
		t.Fatalf("get next: %v", err)
	}
	if storedNext.DueAt != next.DueAt || storedNext.RepeatRule != "weekly" {
		t.Fatalf("unexpected next state after rollover: %+v", storedNext)
	}

	tagIDs, err := app.reminderTagIDs(next.ID)
	if err != nil {
		t.Fatalf("reminderTagIDs next: %v", err)
	}
	if len(tagIDs) != 1 || tagIDs[0] != tagID {
		t.Fatalf("expected next reminder tags to be copied, got %+v", tagIDs)
	}

	logs, err := repo.listCompletionLogs(userID, current.ID)
	if err != nil {
		t.Fatalf("listCompletionLogs: %v", err)
	}
	if len(logs) != 1 {
		t.Fatalf("expected one completion log, got %d", len(logs))
	}
	if logs[0].OriginalDueAt != "2026-04-18T09:00:00Z" || logs[0].NextDueAt != next.DueAt {
		t.Fatalf("unexpected rollover log: %+v", logs[0])
	}
}
