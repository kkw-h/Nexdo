package app

import (
	"testing"

	"nexdo-server-golang/internal/models"
)

func TestAuthRepositoryRotateSession(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	repo := authRepository{}
	now := nowISO()
	session := models.Session{
		ID:             newID(),
		UserID:         "user-1",
		RefreshTokenID: "refresh-1",
		ExpiresAt:      "2026-04-30T09:00:00Z",
		LastUsedAt:     now,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	if err := repo.createSession(app, &session); err != nil {
		t.Fatalf("create session: %v", err)
	}

	oldUpdatedAt := session.UpdatedAt
	if err := repo.rotateSession(app, &session, "refresh-2", "2026-05-30T09:00:00Z"); err != nil {
		t.Fatalf("rotate session: %v", err)
	}

	stored, err := repo.getSession(app, session.ID)
	if err != nil {
		t.Fatalf("get session: %v", err)
	}
	if stored.RefreshTokenID != "refresh-2" {
		t.Fatalf("unexpected refresh token id: %s", stored.RefreshTokenID)
	}
	if stored.ExpiresAt != "2026-05-30T09:00:00Z" {
		t.Fatalf("unexpected expires_at: %s", stored.ExpiresAt)
	}
	if stored.UpdatedAt == oldUpdatedAt {
		t.Fatal("expected updated_at to change")
	}
}

func TestAuthRepositoryRevokeSessionAndRevokeSessionsByUser(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	repo := authRepository{}
	now := nowISO()
	sessions := []models.Session{
		{ID: newID(), UserID: "user-1", RefreshTokenID: "r1", ExpiresAt: "2026-04-30T09:00:00Z", LastUsedAt: now, CreatedAt: now, UpdatedAt: now},
		{ID: newID(), UserID: "user-1", RefreshTokenID: "r2", ExpiresAt: "2026-04-30T09:00:00Z", LastUsedAt: now, CreatedAt: now, UpdatedAt: now},
		{ID: newID(), UserID: "user-2", RefreshTokenID: "r3", ExpiresAt: "2026-04-30T09:00:00Z", LastUsedAt: now, CreatedAt: now, UpdatedAt: now},
	}
	for i := range sessions {
		if err := repo.createSession(app, &sessions[i]); err != nil {
			t.Fatalf("create session %d: %v", i, err)
		}
	}

	ok, err := repo.revokeSession(app, sessions[0].ID, "user-1")
	if err != nil {
		t.Fatalf("revokeSession: %v", err)
	}
	if !ok {
		t.Fatal("expected revokeSession to return true")
	}

	first, err := repo.getSession(app, sessions[0].ID)
	if err != nil {
		t.Fatalf("get revoked session: %v", err)
	}
	if first.RevokedAt == nil {
		t.Fatal("expected first session to be revoked")
	}

	if err := repo.revokeSessionsByUser(app, "user-1"); err != nil {
		t.Fatalf("revokeSessionsByUser: %v", err)
	}

	second, err := repo.getSession(app, sessions[1].ID)
	if err != nil {
		t.Fatalf("get second session: %v", err)
	}
	if second.RevokedAt == nil {
		t.Fatal("expected second session to be revoked")
	}

	third, err := repo.getSession(app, sessions[2].ID)
	if err != nil {
		t.Fatalf("get third session: %v", err)
	}
	if third.RevokedAt != nil {
		t.Fatal("expected other user's session to remain active")
	}
}

func TestAuthRepositoryDeleteDeviceRevokesRelatedSessions(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	repo := authRepository{}
	now := nowISO()
	deviceID := "device-1"
	device := models.Device{
		ID:         newID(),
		UserID:     "user-1",
		DeviceID:   deviceID,
		DeviceName: "iPhone",
		Platform:   "iOS",
		LastSeenAt: now,
		CreatedAt:  now,
		UpdatedAt:  now,
	}
	if err := app.db.Create(&device).Error; err != nil {
		t.Fatalf("create device: %v", err)
	}
	sessions := []models.Session{
		{ID: newID(), UserID: "user-1", DeviceID: &deviceID, RefreshTokenID: "r1", ExpiresAt: "2026-04-30T09:00:00Z", LastUsedAt: now, CreatedAt: now, UpdatedAt: now},
		{ID: newID(), UserID: "user-1", RefreshTokenID: "r2", ExpiresAt: "2026-04-30T09:00:00Z", LastUsedAt: now, CreatedAt: now, UpdatedAt: now},
	}
	for i := range sessions {
		if err := repo.createSession(app, &sessions[i]); err != nil {
			t.Fatalf("create session %d: %v", i, err)
		}
	}

	ok, err := repo.deleteDevice(app, "user-1", deviceID)
	if err != nil {
		t.Fatalf("deleteDevice: %v", err)
	}
	if !ok {
		t.Fatal("expected deleteDevice to return true")
	}

	var count int64
	if err := app.db.Model(&models.Device{}).Where("id = ?", device.ID).Count(&count).Error; err != nil {
		t.Fatalf("count devices: %v", err)
	}
	if count != 0 {
		t.Fatalf("expected device to be deleted, count=%d", count)
	}

	related, err := repo.getSession(app, sessions[0].ID)
	if err != nil {
		t.Fatalf("get related session: %v", err)
	}
	if related.RevokedAt == nil {
		t.Fatal("expected related session to be revoked")
	}

	unrelated, err := repo.getSession(app, sessions[1].ID)
	if err != nil {
		t.Fatalf("get unrelated session: %v", err)
	}
	if unrelated.RevokedAt != nil {
		t.Fatal("expected unrelated session to stay active")
	}
}
