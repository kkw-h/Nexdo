package app

import (
	"testing"

	"nexdo-server-golang/internal/models"
)

func TestQuickNoteRepositoryListExcludesSoftDeletedAndOrdersNewestFirst(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	repo := quickNoteRepository{}
	now := nowISO()
	deletedAt := nowISO()
	items := []models.QuickNote{
		{ID: newID(), UserID: "user-1", Content: "older", Status: "draft", CreatedAt: "2026-04-18T09:00:00Z", UpdatedAt: now},
		{ID: newID(), UserID: "user-1", Content: "newer", Status: "draft", CreatedAt: "2026-04-19T09:00:00Z", UpdatedAt: now},
		{ID: newID(), UserID: "user-1", Content: "deleted", Status: "draft", CreatedAt: "2026-04-20T09:00:00Z", UpdatedAt: now, DeletedAt: &deletedAt},
	}
	for i := range items {
		if err := repo.create(app, &items[i]); err != nil {
			t.Fatalf("create quick note %d: %v", i, err)
		}
	}

	list, err := repo.list(app, "user-1")
	if err != nil {
		t.Fatalf("list quick notes: %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("expected 2 visible quick notes, got %d", len(list))
	}
	if list[0].Content != "newer" || list[1].Content != "older" {
		t.Fatalf("unexpected order: %+v", list)
	}
}

func TestQuickNoteRepositoryGetRejectsSoftDeleted(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	repo := quickNoteRepository{}
	deletedAt := nowISO()
	item := models.QuickNote{
		ID:        newID(),
		UserID:    "user-1",
		Content:   "deleted quick note",
		Status:    "draft",
		CreatedAt: nowISO(),
		UpdatedAt: nowISO(),
		DeletedAt: &deletedAt,
	}
	if err := repo.create(app, &item); err != nil {
		t.Fatalf("create quick note: %v", err)
	}

	if _, err := repo.get(app, "user-1", item.ID); err == nil {
		t.Fatal("expected get to reject soft deleted quick note")
	}
}
