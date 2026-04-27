package app

import (
	"errors"
	"net/http"
	"os"
	"strings"

	"nexdo-server-golang/internal/config"
	"nexdo-server-golang/internal/http/response"
	"nexdo-server-golang/internal/models"
	jwtutil "nexdo-server-golang/internal/pkg/jwt"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

const (
	deviceIDHeader       = "X-Nexdo-Device-ID"
	deviceNameHeader     = "X-Nexdo-Device-Name"
	devicePlatformHeader = "X-Nexdo-Device-Platform"
)

type Application struct {
	cfg    config.Config
	db     *gorm.DB
	router *gin.Engine
}

func New(cfg config.Config) (*Application, error) {
	db, err := openDB(cfg.DatabaseURL)
	if err != nil {
		return nil, err
	}
	if cfg.EnableAutoMigrate {
		if _, err := runMigrations(db, cfg.MigrationsDir); err != nil {
			return nil, err
		}
	}
	if err := os.MkdirAll(cfg.AudioStorageDir, 0o755); err != nil {
		return nil, err
	}

	app := &Application{cfg: cfg, db: db}
	app.router = app.routes()
	return app, nil
}

func openDB(databaseURL string) (*gorm.DB, error) {
	if strings.HasPrefix(databaseURL, "postgres://") || strings.HasPrefix(databaseURL, "postgresql://") {
		return gorm.Open(postgres.Open(databaseURL), &gorm.Config{})
	}
	dsn := strings.TrimPrefix(databaseURL, "sqlite://")
	if dsn == databaseURL {
		dsn = databaseURL
	}
	return gorm.Open(sqlite.Open(dsn), &gorm.Config{})
}

func (a *Application) Router() *gin.Engine {
	return a.router
}

func (a *Application) Run() error {
	return a.router.Run(a.cfg.Addr)
}

func (a *Application) routes() *gin.Engine {
	router := gin.New()
	router.Use(gin.Recovery())

	router.GET("/", func(c *gin.Context) {
		response.OK(c, gin.H{
			"service": a.cfg.AppName,
			"env":     a.cfg.AppEnv,
			"version": "go-v1",
		})
	})
	router.GET("/api/v1/health", func(c *gin.Context) {
		response.OK(c, gin.H{"status": "healthy", "timestamp": nowISO()})
	})
	router.GET("/api/v1/docs", func(c *gin.Context) { response.OK(c, buildDoc()) })
	router.GET("/api/v1/docs/ui", func(c *gin.Context) {
		c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(buildDocUI()))
	})

	v1 := router.Group("/api/v1")
	{
		v1.POST("/auth/register", a.wrap(a.handleRegister))
		v1.POST("/auth/login", a.wrap(a.handleLogin))
		v1.POST("/auth/refresh", a.wrap(a.handleRefresh))
	}

	authorized := v1.Group("")
	authorized.Use(a.authMiddleware())
	{
		authorized.POST("/auth/logout", a.wrap(a.handleLogout))
		authorized.GET("/me", a.wrap(a.handleMe))
		authorized.PATCH("/me", a.wrap(a.handleUpdateMe))
		authorized.PATCH("/me/password", a.wrap(a.handlePassword))
		authorized.GET("/me/devices", a.wrap(a.handleDevices))
		authorized.DELETE("/me/devices/:id", a.wrap(a.handleDeleteDevice))
		authorized.GET("/sync/bootstrap", a.wrap(a.handleBootstrap))
		authorized.GET("/sync/changes", a.wrap(a.handleChanges))
		authorized.GET("/lists", a.wrap(a.handleListLists))
		authorized.POST("/lists", a.wrap(a.handleCreateList))
		authorized.PATCH("/lists/:id", a.wrap(a.handlePatchList))
		authorized.DELETE("/lists/:id", a.wrap(a.handleDeleteList))
		authorized.GET("/groups", a.wrap(a.handleListGroups))
		authorized.POST("/groups", a.wrap(a.handleCreateGroup))
		authorized.PATCH("/groups/:id", a.wrap(a.handlePatchGroup))
		authorized.DELETE("/groups/:id", a.wrap(a.handleDeleteGroup))
		authorized.GET("/tags", a.wrap(a.handleListTags))
		authorized.POST("/tags", a.wrap(a.handleCreateTag))
		authorized.PATCH("/tags/:id", a.wrap(a.handlePatchTag))
		authorized.DELETE("/tags/:id", a.wrap(a.handleDeleteTag))
		authorized.GET("/reminders", a.wrap(a.handleListReminders))
		authorized.GET("/reminders/:id", a.wrap(a.handleGetReminder))
		authorized.GET("/reminders/:id/completion-logs", a.wrap(a.handleReminderLogs))
		authorized.POST("/reminders", a.wrap(a.handleCreateReminder))
		authorized.PATCH("/reminders/:id", a.wrap(a.handlePatchReminder))
		authorized.DELETE("/reminders/:id", a.wrap(a.handleDeleteReminder))
		authorized.POST("/reminders/:id/complete", a.wrap(a.handleCompleteReminder))
		authorized.POST("/reminders/:id/uncomplete", a.wrap(a.handleUncompleteReminder))
		authorized.GET("/quick-notes", a.wrap(a.handleListQuickNotes))
		authorized.POST("/quick-notes", a.wrap(a.handleCreateQuickNote))
		authorized.PATCH("/quick-notes/:id", a.wrap(a.handlePatchQuickNote))
		authorized.DELETE("/quick-notes/:id", a.wrap(a.handleDeleteQuickNote))
		authorized.GET("/quick-notes/:id/audio", a.wrap(a.handleQuickNoteAudio))
		authorized.POST("/quick-notes/:id/convert", a.wrap(a.handleConvertQuickNote))
		authorized.POST("/ai/commands/resolve", a.wrap(a.handleResolveAICommand))
		authorized.POST("/ai/commands/confirmations/verify", a.wrap(a.handleVerifyAIConfirmation))
		authorized.POST("/ai/commands/confirmations/execute", a.wrap(a.handleExecuteAIConfirmation))
	}
	return router
}

func (a *Application) wrap(handler func(*gin.Context) error) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := handler(c); err != nil {
			a.renderError(c, err)
		}
	}
}

func (a *Application) renderError(c *gin.Context, err error) {
	var appErr *AppError
	if errors.As(err, &appErr) {
		response.Fail(c, appErr.Status, appErr.Code, appErr.Message, appErr.Detail)
		return
	}
	response.Fail(c, 500, 50000, "服务器内部错误", err.Error())
}

func (a *Application) authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := strings.TrimSpace(strings.TrimPrefix(c.GetHeader("Authorization"), "Bearer"))
		if token == "" {
			a.renderError(c, unauthorized(""))
			c.Abort()
			return
		}
		claims, err := jwtutil.Parse(token, a.cfg.JWTAccessSecret, "access")
		if err != nil {
			a.renderError(c, unauthorized(""))
			c.Abort()
			return
		}
		session, err := a.requireActiveSession(claims.Subject, claims.SessionID)
		if err != nil {
			a.renderError(c, unauthorized("会话已失效"))
			c.Abort()
			return
		}
		var user models.User
		if err := a.db.Where("id = ?", claims.Subject).First(&user).Error; err != nil {
			a.renderError(c, unauthorized("用户不存在"))
			c.Abort()
			return
		}
		c.Set("userID", user.ID)
		c.Set("sessionID", session.ID)
		if deviceID, err := a.recordDeviceFromRequest(c, user.ID); err == nil && deviceID != "" {
			c.Set("deviceID", deviceID)
			if session.DeviceID == nil || *session.DeviceID != deviceID {
				session.DeviceID = &deviceID
				session.LastUsedAt = nowISO()
				session.UpdatedAt = session.LastUsedAt
				_ = authRepository{}.saveSession(a, &session)
			}
		}
		c.Next()
	}
}
