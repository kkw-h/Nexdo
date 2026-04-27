package app

import (
	"nexdo-server-golang/internal/models"

	"gorm.io/gorm"
)

func replaceReminderTags(tx *gorm.DB, reminderID string, tagIDs []string) error {
	if err := tx.Where("reminder_id = ?", reminderID).Delete(&models.ReminderTag{}).Error; err != nil {
		return err
	}
	for _, tagID := range tagIDs {
		if err := tx.Create(&models.ReminderTag{ReminderID: reminderID, TagID: tagID}).Error; err != nil {
			return err
		}
	}
	return nil
}

func (a *Application) reminderTags(reminderID string) ([]models.Tag, error) {
	var tags []models.Tag
	err := a.db.Table("tags").
		Select("tags.*").
		Joins("join reminder_tags on reminder_tags.tag_id = tags.id").
		Where("reminder_tags.reminder_id = ? AND tags.deleted_at IS NULL", reminderID).
		Order("tags.created_at asc").
		Scan(&tags).Error
	return tags, err
}

func (a *Application) reminderTagsByIDs(reminderIDs []string) (map[string][]models.Tag, error) {
	result := make(map[string][]models.Tag, len(reminderIDs))
	if len(reminderIDs) == 0 {
		return result, nil
	}
	var rows []struct {
		ReminderID string `gorm:"column:reminder_id"`
		models.Tag
	}
	err := a.db.Table("reminder_tags").
		Select("reminder_tags.reminder_id, tags.*").
		Joins("join tags on tags.id = reminder_tags.tag_id").
		Where("reminder_tags.reminder_id IN ? AND tags.deleted_at IS NULL", reminderIDs).
		Order("tags.created_at asc").
		Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	for _, row := range rows {
		result[row.ReminderID] = append(result[row.ReminderID], row.Tag)
	}
	return result, nil
}

func (a *Application) reminderTagIDs(reminderID string) ([]string, error) {
	var rows []struct{ TagID string }
	if err := a.db.Table("reminder_tags").Select("tag_id").Where("reminder_id = ?", reminderID).Scan(&rows).Error; err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(rows))
	for _, row := range rows {
		ids = append(ids, row.TagID)
	}
	return ids, nil
}
