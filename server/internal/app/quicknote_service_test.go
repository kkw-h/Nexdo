package app

import (
	"os"
	"path/filepath"
	"testing"

	"nexdo-server-golang/internal/models"
)

func TestQuickNoteServiceCreateFromJSONSerializesWaveform(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	userID := mustUserIDFromToken(t, app, token)
	service := newQuickNoteService(app)

	view, err := service.createFromJSON(userID, quickNotePayload{
		Content:         "service quick note",
		WaveformSamples: []int{1, 3, 5},
	}, ginContextAdapter{ctx: newServiceContext()})
	if err != nil {
		t.Fatalf("createFromJSON: %v", err)
	}
	if view.Status != "draft" {
		t.Fatalf("expected draft status, got %s", view.Status)
	}
	if len(view.WaveformSamples) != 3 || view.WaveformSamples[1] != 3 {
		t.Fatalf("unexpected waveform samples: %+v", view.WaveformSamples)
	}

	item, err := service.repo.get(app, userID, view.ID)
	if err != nil {
		t.Fatalf("get created quick note: %v", err)
	}
	if item.WaveformSamples == nil || *item.WaveformSamples != "[1,3,5]" {
		t.Fatalf("unexpected stored waveform: %+v", item.WaveformSamples)
	}
}

func TestQuickNoteServicePatchStateRules(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	userID := mustUserIDFromToken(t, app, token)
	service := newQuickNoteService(app)

	created, err := service.createFromJSON(userID, quickNotePayload{Content: "needs reminder"}, ginContextAdapter{ctx: newServiceContext()})
	if err != nil {
		t.Fatalf("createFromJSON: %v", err)
	}

	if _, err := service.patch(userID, created.ID, updateQuickNotePayload{Status: stringPtr("converted")}, ginContextAdapter{ctx: newServiceContext()}); err == nil {
		t.Fatal("expected converted status without reminder id to fail")
	}

	reminderID := newID()
	item, err := service.repo.get(app, userID, created.ID)
	if err != nil {
		t.Fatalf("get quick note: %v", err)
	}
	item.Status = "converted"
	item.ConvertedReminderID = &reminderID
	if err := service.repo.save(app, &item); err != nil {
		t.Fatalf("save converted quick note: %v", err)
	}

	if _, err := service.patch(userID, created.ID, updateQuickNotePayload{Status: stringPtr("draft")}, ginContextAdapter{ctx: newServiceContext()}); err == nil {
		t.Fatal("expected converted quick note to reject draft transition")
	}
}

func TestQuickNoteServiceDeleteRemovesAudioAndRollsBackOnFailure(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	userID := mustUserIDFromToken(t, app, token)
	service := newQuickNoteService(app)
	now := nowISO()

	audioPath := filepath.Join(app.cfg.AudioStorageDir, "quick-notes", userID, newID(), "voice.webm")
	if err := os.MkdirAll(filepath.Dir(audioPath), 0o755); err != nil {
		t.Fatalf("mkdir audio dir: %v", err)
	}
	if err := os.WriteFile(audioPath, []byte("audio"), 0o644); err != nil {
		t.Fatalf("write audio file: %v", err)
	}
	item := models.QuickNote{
		ID:        newID(),
		UserID:    userID,
		Content:   "with audio",
		Status:    "draft",
		AudioKey:  &audioPath,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := service.repo.create(app, &item); err != nil {
		t.Fatalf("create quick note: %v", err)
	}

	if err := service.delete(userID, item.ID); err != nil {
		t.Fatalf("delete quick note: %v", err)
	}
	if _, err := os.Stat(audioPath); !os.IsNotExist(err) {
		t.Fatalf("expected audio file to be removed, stat err = %v", err)
	}

	badDir := filepath.Join(t.TempDir(), "non-empty-audio-dir")
	if err := os.MkdirAll(badDir, 0o755); err != nil {
		t.Fatalf("mkdir bad dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(badDir, "nested.txt"), []byte("keep"), 0o644); err != nil {
		t.Fatalf("seed nested file: %v", err)
	}
	badItem := models.QuickNote{
		ID:        newID(),
		UserID:    userID,
		Content:   "bad delete",
		Status:    "draft",
		AudioKey:  &badDir,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := service.repo.create(app, &badItem); err != nil {
		t.Fatalf("create bad quick note: %v", err)
	}

	if err := service.delete(userID, badItem.ID); err == nil {
		t.Fatal("expected delete to fail when audio cleanup fails")
	}
	stored, err := service.repo.get(app, userID, badItem.ID)
	if err != nil {
		t.Fatalf("get bad quick note after failed delete: %v", err)
	}
	if stored.DeletedAt != nil {
		t.Fatal("expected deleted_at rollback after failed audio cleanup")
	}
}
