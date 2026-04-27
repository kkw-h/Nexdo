package app

import (
	"strings"
	"time"

	"nexdo-server-golang/internal/models"
	jwtutil "nexdo-server-golang/internal/pkg/jwt"
	"nexdo-server-golang/internal/pkg/password"

	"github.com/gin-gonic/gin"
)

type authService struct {
	app  *Application
	repo authRepository
}

func newAuthService(app *Application) authService {
	return authService{app: app, repo: authRepository{}}
}

func (s authService) issueSessionTokens(c *gin.Context, userID string) (jwtutil.TokenPair, error) {
	deviceID, err := s.app.recordDeviceFromRequest(c, userID)
	if err != nil {
		return jwtutil.TokenPair{}, err
	}
	sessionID := newID()
	issued, err := jwtutil.IssuePair(userID, sessionID, s.app.cfg.JWTAccessSecret, s.app.cfg.JWTRefreshSecret, s.app.cfg.AccessTokenTTL, s.app.cfg.RefreshTokenTTL)
	if err != nil {
		return jwtutil.TokenPair{}, err
	}
	now := nowISO()
	session := models.Session{
		ID:             sessionID,
		UserID:         userID,
		RefreshTokenID: issued.RefreshTokenID,
		ExpiresAt:      issued.RefreshExpiresAt.UTC().Format(time.RFC3339Nano),
		LastUsedAt:     now,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	if deviceID != "" {
		session.DeviceID = &deviceID
	}
	if err := s.repo.createSession(s.app, &session); err != nil {
		return jwtutil.TokenPair{}, err
	}
	return issued.Pair, nil
}

func (s authService) register(c *gin.Context, req registerRequest) (gin.H, error) {
	if err := validateRegister(req); err != nil {
		return nil, err
	}
	count, err := s.repo.countUsersByEmail(s.app, req.Email)
	if err != nil {
		return nil, err
	}
	if count > 0 {
		return nil, conflict(40900, "邮箱已被注册")
	}
	hash, err := password.Hash(req.Password)
	if err != nil {
		return nil, err
	}
	now := nowISO()
	user := models.User{ID: newID(), Email: req.Email, PasswordHash: hash, Nickname: req.Nickname, Timezone: req.Timezone, Locale: req.Locale, CreatedAt: now, UpdatedAt: now}
	if err := s.repo.createUserWithDefaults(s.app, &user); err != nil {
		return nil, err
	}
	tokens, err := s.issueSessionTokens(c, user.ID)
	if err != nil {
		return nil, err
	}
	return gin.H{"user": publicUser(user), "tokens": tokens}, nil
}

func (s authService) login(c *gin.Context, req loginRequest) (gin.H, error) {
	if req.Email == "" || req.Password == "" {
		return nil, badRequest("email 和 password 必填")
	}
	user, err := s.repo.getUserByEmail(s.app, req.Email)
	if err != nil || !password.Verify(user.PasswordHash, req.Password) {
		return nil, unauthorized("邮箱或密码不正确")
	}
	tokens, err := s.issueSessionTokens(c, user.ID)
	if err != nil {
		return nil, err
	}
	return gin.H{"user": publicUser(user), "tokens": tokens}, nil
}

func (s authService) refresh(c *gin.Context, req refreshRequest) (gin.H, error) {
	claims, err := jwtutil.Parse(req.RefreshToken, s.app.cfg.JWTRefreshSecret, "refresh")
	if err != nil {
		return nil, unauthorized("")
	}
	session, err := s.repo.getSession(s.app, claims.SessionID)
	if err != nil || session.UserID != claims.Subject || session.RefreshTokenID != claims.ID {
		return nil, unauthorized("refresh token 已失效")
	}
	if session.RevokedAt != nil {
		return nil, unauthorized("refresh token 已失效")
	}
	expiresAt, err := parseRFC3339Time(session.ExpiresAt)
	if err != nil || expiresAt.Before(time.Now().UTC()) {
		return nil, unauthorized("refresh token 已过期")
	}
	user, err := s.repo.getUserByID(s.app, claims.Subject)
	if err != nil {
		return nil, unauthorized("用户不存在")
	}
	deviceID, err := s.app.recordDeviceFromRequest(c, user.ID)
	if err != nil {
		return nil, err
	}
	if deviceID != "" {
		session.DeviceID = &deviceID
	}
	issued, err := jwtutil.IssuePair(user.ID, session.ID, s.app.cfg.JWTAccessSecret, s.app.cfg.JWTRefreshSecret, s.app.cfg.AccessTokenTTL, s.app.cfg.RefreshTokenTTL)
	if err != nil {
		return nil, err
	}
	if err := s.repo.rotateSession(s.app, &session, issued.RefreshTokenID, issued.RefreshExpiresAt.UTC().Format(time.RFC3339Nano)); err != nil {
		return nil, err
	}
	return gin.H{"user": publicUser(user), "tokens": issued.Pair}, nil
}

func (s authService) currentUser(c *gin.Context) (gin.H, error) {
	user, err := s.app.currentUser(c)
	if err != nil {
		return nil, err
	}
	return publicUser(user), nil
}

func (s authService) updateProfile(c *gin.Context, req updateProfileRequest) (gin.H, error) {
	user, err := s.app.currentUser(c)
	if err != nil {
		return nil, err
	}
	if req.Nickname != nil {
		user.Nickname = strings.TrimSpace(*req.Nickname)
	}
	if req.AvatarURL != nil {
		if err := validateAvatarURL(*req.AvatarURL); err != nil {
			return nil, err
		}
		user.AvatarURL = strings.TrimSpace(*req.AvatarURL)
	}
	if req.Timezone != nil {
		if err := validateTimezone(*req.Timezone); err != nil {
			return nil, err
		}
		user.Timezone = strings.TrimSpace(*req.Timezone)
	}
	if req.Locale != nil {
		if err := validateLocale(*req.Locale); err != nil {
			return nil, err
		}
		user.Locale = strings.TrimSpace(*req.Locale)
	}
	user.UpdatedAt = nowISO()
	if err := s.repo.saveUser(s.app, &user); err != nil {
		return nil, err
	}
	return publicUser(user), nil
}

func (s authService) changePassword(c *gin.Context, req changePasswordRequest) (gin.H, error) {
	if len(req.NewPassword) < 8 {
		return nil, badRequest("new_password 长度不能少于 8")
	}
	user, err := s.app.currentUser(c)
	if err != nil {
		return nil, err
	}
	if !password.Verify(user.PasswordHash, req.OldPassword) {
		return nil, unauthorizedWithCode(40101, "旧密码不正确")
	}
	hash, err := password.Hash(req.NewPassword)
	if err != nil {
		return nil, err
	}
	user.PasswordHash = hash
	user.UpdatedAt = nowISO()
	if err := s.repo.saveUser(s.app, &user); err != nil {
		return nil, err
	}
	if err := s.repo.revokeSessionsByUser(s.app, user.ID); err != nil {
		return nil, err
	}
	return gin.H{"changed": true}, nil
}

func (s authService) devices(c *gin.Context) (gin.H, error) {
	userID := c.MustGet("userID").(string)
	devices, err := s.repo.listDevices(s.app, userID)
	if err != nil {
		return nil, err
	}
	currentDeviceID, _ := c.Get("deviceID")
	return gin.H{"devices": devices, "current_device_id": currentDeviceID}, nil
}

func (s authService) deleteDevice(c *gin.Context, id string) (gin.H, error) {
	ok, err := s.repo.deleteDevice(s.app, c.MustGet("userID").(string), id)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, notFound("设备不存在")
	}
	return gin.H{"deleted": true}, nil
}

func (s authService) logout(c *gin.Context) (gin.H, error) {
	userID := c.MustGet("userID").(string)
	sessionID, _ := c.Get("sessionID")
	if sessionID == nil || sessionID.(string) == "" {
		return nil, unauthorized("")
	}
	if _, err := s.repo.revokeSession(s.app, sessionID.(string), userID); err != nil {
		return nil, err
	}
	return gin.H{"logged_out": true}, nil
}
