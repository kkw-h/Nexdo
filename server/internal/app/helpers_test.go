package app

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNormalizeMultiValueItems(t *testing.T) {
	t.Parallel()

	got := normalizeMultiValueItems([]string{"a,b", " b , c ", "", "a"})
	want := []string{"a", "b", "c"}
	if len(got) != len(want) {
		t.Fatalf("unexpected length: got %v want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("unexpected values: got %v want %v", got, want)
		}
	}
}

func TestSanitizeFilename(t *testing.T) {
	t.Parallel()

	if got := sanitizeFilename(" meeting note?.webm "); got != "meeting_note_.webm" {
		t.Fatalf("unexpected sanitized filename: %s", got)
	}
}

func TestRemoveQuickNoteAudioRemovesFileAndDirectories(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	audioPath := filepath.Join(app.cfg.AudioStorageDir, "quick-notes", "user-1", "note-1", "voice.webm")
	if err := os.MkdirAll(filepath.Dir(audioPath), 0o755); err != nil {
		t.Fatalf("mkdirs: %v", err)
	}
	if err := os.WriteFile(audioPath, []byte("audio"), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}

	if err := app.removeQuickNoteAudio(audioPath); err != nil {
		t.Fatalf("removeQuickNoteAudio: %v", err)
	}
	if _, err := os.Stat(audioPath); !os.IsNotExist(err) {
		t.Fatalf("expected audio file to be removed, stat err = %v", err)
	}
	if _, err := os.Stat(filepath.Dir(audioPath)); !os.IsNotExist(err) {
		t.Fatalf("expected leaf directory to be removed, stat err = %v", err)
	}
}
