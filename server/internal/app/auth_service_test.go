package app

import (
	"net/http/httptest"
	"testing"

	"nexdo-server-golang/internal/models"
	jwtutil "nexdo-server-golang/internal/pkg/jwt"

	"github.com/gin-gonic/gin"
)

func TestAuthServiceRefreshRotatesSessionState(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	service := newAuthService(app)

	registerCtx := newServiceContext()
	registerCtx.Request.Header.Set(deviceIDHeader, "register-device")
	registerCtx.Request.Header.Set(deviceNameHeader, "iPhone")
	registerCtx.Request.Header.Set(devicePlatformHeader, "iOS")
	registerData, err := service.register(registerCtx, registerRequest{
		Email:    "service-auth@example.com",
		Password: "password123",
		Nickname: "service-auth",
		Timezone: "Asia/Shanghai",
		Locale:   "zh-CN",
	})
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	registerTokens := registerData["tokens"].(jwtutil.TokenPair)
	refreshClaims, err := jwtutil.Parse(registerTokens.RefreshToken, app.cfg.JWTRefreshSecret, "refresh")
	if err != nil {
		t.Fatalf("parse refresh token: %v", err)
	}

	var before models.Session
	if err := app.db.Where("id = ?", refreshClaims.SessionID).First(&before).Error; err != nil {
		t.Fatalf("load session before refresh: %v", err)
	}

	refreshCtx := newServiceContext()
	refreshCtx.Request.Header.Set(deviceIDHeader, "refresh-device")
	refreshCtx.Request.Header.Set(deviceNameHeader, "MacBook Pro")
	refreshCtx.Request.Header.Set(devicePlatformHeader, "macOS")
	refreshData, err := service.refresh(refreshCtx, refreshRequest{RefreshToken: registerTokens.RefreshToken})
	if err != nil {
		t.Fatalf("refresh: %v", err)
	}
	refreshedTokens := refreshData["tokens"].(jwtutil.TokenPair)
	refreshedClaims, err := jwtutil.Parse(refreshedTokens.RefreshToken, app.cfg.JWTRefreshSecret, "refresh")
	if err != nil {
		t.Fatalf("parse rotated refresh token: %v", err)
	}
	if refreshedClaims.SessionID != refreshClaims.SessionID {
		t.Fatalf("expected same session id, got %s want %s", refreshedClaims.SessionID, refreshClaims.SessionID)
	}
	if refreshedClaims.ID == refreshClaims.ID {
		t.Fatal("expected refresh token id to rotate")
	}

	var after models.Session
	if err := app.db.Where("id = ?", refreshClaims.SessionID).First(&after).Error; err != nil {
		t.Fatalf("load session after refresh: %v", err)
	}
	if after.RefreshTokenID != refreshedClaims.ID {
		t.Fatalf("expected session refresh token id to update, got %s want %s", after.RefreshTokenID, refreshedClaims.ID)
	}
	if after.DeviceID == nil || *after.DeviceID != "refresh-device" {
		t.Fatalf("expected session device id to update, got %+v", after.DeviceID)
	}
	if after.UpdatedAt == before.UpdatedAt {
		t.Fatal("expected session updated_at to change after refresh")
	}
}

func TestAuthServiceChangePasswordRevokesAllSessions(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	service := newAuthService(app)
	firstSession := registerTestSessionFor(t, app, "service-password@example.com", "service-password")

	loginCtx := newServiceContext()
	loginCtx.Request.Header.Set(deviceIDHeader, "second-device")
	loginCtx.Request.Header.Set(deviceNameHeader, "iPad")
	loginCtx.Request.Header.Set(devicePlatformHeader, "iPadOS")
	loginData, err := service.login(loginCtx, loginRequest{
		Email:    "service-password@example.com",
		Password: "password123",
	})
	if err != nil {
		t.Fatalf("login second session: %v", err)
	}
	secondTokens := loginData["tokens"].(jwtutil.TokenPair)

	accessClaims, err := jwtutil.Parse(firstSession.AccessToken, app.cfg.JWTAccessSecret, "access")
	if err != nil {
		t.Fatalf("parse access token: %v", err)
	}
	changeCtx := newServiceContext()
	changeCtx.Set("userID", accessClaims.Subject)
	changeCtx.Set("sessionID", accessClaims.SessionID)
	if _, err := service.changePassword(changeCtx, changePasswordRequest{
		OldPassword: "password123",
		NewPassword: "new-password-123",
	}); err != nil {
		t.Fatalf("change password: %v", err)
	}

	var sessions []models.Session
	if err := app.db.Where("user_id = ?", accessClaims.Subject).Find(&sessions).Error; err != nil {
		t.Fatalf("list sessions: %v", err)
	}
	if len(sessions) < 2 {
		t.Fatalf("expected at least 2 sessions, got %d", len(sessions))
	}
	for _, session := range sessions {
		if session.RevokedAt == nil {
			t.Fatalf("expected session %s to be revoked", session.ID)
		}
	}

	secondAccessClaims, err := jwtutil.Parse(secondTokens.AccessToken, app.cfg.JWTAccessSecret, "access")
	if err != nil {
		t.Fatalf("parse second access token: %v", err)
	}
	if _, err := app.requireActiveSession(accessClaims.Subject, secondAccessClaims.SessionID); err == nil {
		t.Fatal("expected second session to be inactive after password change")
	}
}

func newServiceContext() *gin.Context {
	rec := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(rec)
	ctx.Request = httptest.NewRequest("POST", "/", nil)
	return ctx
}
