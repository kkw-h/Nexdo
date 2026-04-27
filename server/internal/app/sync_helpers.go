package app

import (
	"net/http"
	"net/url"

	"nexdo-server-golang/internal/http/response"
	"nexdo-server-golang/internal/models"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func (a *Application) handleBootstrap(c *gin.Context) error {
	data, err := a.buildBootstrap(c, c.MustGet("userID").(string))
	if err != nil {
		return err
	}
	response.OK(c, data)
	return nil
}

func (a *Application) handleChanges(c *gin.Context) error {
	userID := c.MustGet("userID").(string)
	since := c.Query("since")
	if since == "" {
		return badRequestWithCode(40001, "since 参数必须是 RFC3339 时间戳")
	}
	if _, err := parseRFC3339Time(since); err != nil {
		return badRequestWithCode(40002, "since 参数必须是 RFC3339 时间戳")
	}
	data, err := a.buildChanges(c, userID, since)
	if err != nil {
		return err
	}
	response.OK(c, data)
	return nil
}

func (a *Application) buildBootstrap(c *gin.Context, userID string) (bootstrapData, error) {
	cursor := nowISO()
	var lists []models.List
	var groups []models.Group
	var tags []models.Tag
	var quickNotes []models.QuickNote
	if err := a.db.Where("user_id = ? AND deleted_at IS NULL", userID).Order("sort_order asc, created_at asc").Find(&lists).Error; err != nil {
		return bootstrapData{}, err
	}
	if err := a.db.Where("user_id = ? AND deleted_at IS NULL", userID).Order("sort_order asc, created_at asc").Find(&groups).Error; err != nil {
		return bootstrapData{}, err
	}
	if err := a.db.Where("user_id = ? AND deleted_at IS NULL", userID).Order("created_at asc").Find(&tags).Error; err != nil {
		return bootstrapData{}, err
	}
	reminders, err := a.listReminders(userID, &gin.Context{Request: &http.Request{URL: &url.URL{}}})
	if err != nil {
		return bootstrapData{}, err
	}
	if err := a.db.Where("user_id = ? AND deleted_at IS NULL", userID).Order("created_at desc").Find(&quickNotes).Error; err != nil {
		return bootstrapData{}, err
	}
	quickNoteViews := make([]quickNoteView, 0, len(quickNotes))
	for _, item := range quickNotes {
		quickNoteViews = append(quickNoteViews, a.quickNoteView(c, item))
	}
	return bootstrapData{Lists: lists, Groups: groups, Tags: tags, Reminders: reminders, QuickNotes: quickNoteViews, ServerTime: cursor}, nil
}

func (a *Application) buildChanges(c *gin.Context, userID, since string) (changesData, error) {
	cursor := nowISO()
	var lists []models.List
	var groups []models.Group
	var tags []models.Tag
	var reminders []models.Reminder
	var quickNotes []models.QuickNote
	if err := a.db.Where("user_id = ? AND deleted_at IS NULL AND updated_at > ?", userID, since).Order("updated_at asc").Find(&lists).Error; err != nil {
		return changesData{}, err
	}
	if err := a.db.Where("user_id = ? AND deleted_at IS NULL AND updated_at > ?", userID, since).Order("updated_at asc").Find(&groups).Error; err != nil {
		return changesData{}, err
	}
	if err := a.db.Where("user_id = ? AND deleted_at IS NULL AND updated_at > ?", userID, since).Order("updated_at asc").Find(&tags).Error; err != nil {
		return changesData{}, err
	}
	if err := a.db.Where("user_id = ? AND deleted_at IS NULL AND updated_at > ?", userID, since).Order("updated_at asc").Find(&reminders).Error; err != nil {
		return changesData{}, err
	}
	if err := a.db.Where("user_id = ? AND deleted_at IS NULL AND updated_at > ?", userID, since).Order("updated_at asc").Find(&quickNotes).Error; err != nil {
		return changesData{}, err
	}
	reminderViews, err := a.reminderViews(reminders)
	if err != nil {
		return changesData{}, err
	}
	quickNoteViews := make([]quickNoteView, 0, len(quickNotes))
	for _, item := range quickNotes {
		quickNoteViews = append(quickNoteViews, a.quickNoteView(c, item))
	}
	return changesData{
		Lists:               lists,
		DeletedListIDs:      deletedIDs[models.List](a.db, userID, since),
		Groups:              groups,
		DeletedGroupIDs:     deletedIDs[models.Group](a.db, userID, since),
		Tags:                tags,
		DeletedTagIDs:       deletedIDs[models.Tag](a.db, userID, since),
		Reminders:           reminderViews,
		DeletedReminderIDs:  deletedIDs[models.Reminder](a.db, userID, since),
		QuickNotes:          quickNoteViews,
		DeletedQuickNoteIDs: deletedIDs[models.QuickNote](a.db, userID, since),
		ServerTime:          cursor,
	}, nil
}

func deletedIDs[T any](db *gorm.DB, userID, since string) []string {
	var rows []struct{ ID string }
	var model T
	_ = db.Model(&model).Select("id").Where("user_id = ? AND deleted_at IS NOT NULL AND deleted_at > ?", userID, since).Order("deleted_at asc").Scan(&rows).Error
	ids := make([]string, 0, len(rows))
	for _, row := range rows {
		ids = append(ids, row.ID)
	}
	return ids
}
