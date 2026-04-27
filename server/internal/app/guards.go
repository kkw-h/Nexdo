package app

import (
	"strings"
	"time"

	"nexdo-server-golang/internal/models"

	"github.com/gin-gonic/gin"
)

func (a *Application) currentUser(c *gin.Context) (models.User, error) {
	var user models.User
	if err := a.db.Where("id = ?", c.MustGet("userID").(string)).First(&user).Error; err != nil {
		return models.User{}, unauthorized("用户不存在")
	}
	return user, nil
}

func (a *Application) requireUser(userID string) (models.User, error) {
	var user models.User
	if err := a.db.Where("id = ?", userID).First(&user).Error; err != nil {
		return models.User{}, notFound("用户不存在")
	}
	return user, nil
}

func (a *Application) requireActiveSession(userID, sessionID string) (models.Session, error) {
	if strings.TrimSpace(sessionID) == "" {
		return models.Session{}, unauthorized("会话已失效")
	}
	var session models.Session
	if err := a.db.Where("id = ? AND user_id = ?", sessionID, userID).First(&session).Error; err != nil {
		return models.Session{}, unauthorized("会话已失效")
	}
	if session.RevokedAt != nil {
		return models.Session{}, unauthorized("会话已失效")
	}
	expiresAt, err := parseRFC3339Time(session.ExpiresAt)
	if err != nil || expiresAt.Before(time.Now().UTC()) {
		return models.Session{}, unauthorized("会话已失效")
	}
	return session, nil
}

func (a *Application) requireList(userID, id string) (models.List, error) {
	var item models.List
	if err := a.db.Where("id = ? AND user_id = ? AND deleted_at IS NULL", id, userID).First(&item).Error; err != nil {
		return models.List{}, notFound("")
	}
	return item, nil
}

func (a *Application) requireGroup(userID, id string) (models.Group, error) {
	var item models.Group
	if err := a.db.Where("id = ? AND user_id = ? AND deleted_at IS NULL", id, userID).First(&item).Error; err != nil {
		return models.Group{}, notFound("")
	}
	return item, nil
}

func (a *Application) requireTag(userID, id string) (models.Tag, error) {
	var item models.Tag
	if err := a.db.Where("id = ? AND user_id = ? AND deleted_at IS NULL", id, userID).First(&item).Error; err != nil {
		return models.Tag{}, notFound("")
	}
	return item, nil
}

func (a *Application) requireReminder(userID, id string) (models.Reminder, error) {
	var item models.Reminder
	if err := a.db.Where("id = ? AND user_id = ? AND deleted_at IS NULL", id, userID).First(&item).Error; err != nil {
		return models.Reminder{}, notFound("")
	}
	return item, nil
}

func (a *Application) requireQuickNote(userID, id string) (models.QuickNote, error) {
	var item models.QuickNote
	if err := a.db.Where("id = ? AND user_id = ? AND deleted_at IS NULL", id, userID).First(&item).Error; err != nil {
		return models.QuickNote{}, notFound("")
	}
	return item, nil
}

func (a *Application) ensureTagsOwned(userID string, tagIDs []string) error {
	if len(tagIDs) == 0 {
		return nil
	}
	var count int64
	if err := a.db.Model(&models.Tag{}).Where("user_id = ? AND deleted_at IS NULL AND id IN ?", userID, tagIDs).Count(&count).Error; err != nil {
		return err
	}
	if int(count) != len(tagIDs) {
		return notFound("标签不存在")
	}
	return nil
}
