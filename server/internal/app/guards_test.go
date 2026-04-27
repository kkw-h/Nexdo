package app

import (
	"testing"
	"time"

	"nexdo-server-golang/internal/models"
)

func TestRequireActiveSession(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	now := nowISO()
	session := models.Session{
		ID:             newID(),
		UserID:         "user-1",
		RefreshTokenID: "refresh-1",
		ExpiresAt:      time.Now().UTC().Add(time.Hour).Format(time.RFC3339Nano),
		LastUsedAt:     now,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	if err := app.db.Create(&session).Error; err != nil {
		t.Fatalf("create session: %v", err)
	}

	got, err := app.requireActiveSession("user-1", session.ID)
	if err != nil {
		t.Fatalf("requireActiveSession returned error: %v", err)
	}
	if got.ID != session.ID {
		t.Fatalf("unexpected session id: %s", got.ID)
	}
}

func TestRequireActiveSessionRejectsRevokedAndExpired(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	now := nowISO()
	revokedAt := nowISO()
	cases := []models.Session{
		{
			ID:             newID(),
			UserID:         "user-1",
			RefreshTokenID: "refresh-revoked",
			ExpiresAt:      time.Now().UTC().Add(time.Hour).Format(time.RFC3339Nano),
			LastUsedAt:     now,
			RevokedAt:      &revokedAt,
			CreatedAt:      now,
			UpdatedAt:      now,
		},
		{
			ID:             newID(),
			UserID:         "user-1",
			RefreshTokenID: "refresh-expired",
			ExpiresAt:      time.Now().UTC().Add(-time.Hour).Format(time.RFC3339Nano),
			LastUsedAt:     now,
			CreatedAt:      now,
			UpdatedAt:      now,
		},
	}

	for _, session := range cases {
		if err := app.db.Create(&session).Error; err != nil {
			t.Fatalf("create session: %v", err)
		}
		if _, err := app.requireActiveSession("user-1", session.ID); err == nil {
			t.Fatalf("expected session %s to be rejected", session.ID)
		}
	}
}
