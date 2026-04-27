package app

import (
	"nexdo-server-golang/internal/models"

	"gorm.io/gorm"
)

type reminderRepository struct {
	db *gorm.DB
}

func (r reminderRepository) get(userID, id string) (models.Reminder, error) {
	var item models.Reminder
	if err := r.db.Where("id = ? AND user_id = ? AND deleted_at IS NULL", id, userID).First(&item).Error; err != nil {
		return models.Reminder{}, notFound("")
	}
	return item, nil
}

func (r reminderRepository) list(userID string, c queryProvider) ([]models.Reminder, error) {
	query := r.db.Model(&models.Reminder{}).Where("user_id = ? AND deleted_at IS NULL", userID)
	if raw := c.Query("is_completed"); raw != "" {
		parsed, err := parseBooleanQuery(raw, "is_completed")
		if err != nil {
			return nil, err
		}
		query = query.Where("is_completed = ?", parsed)
	}
	if ids := parseMultiValueQueryProvider(c, "list_ids"); len(ids) > 0 {
		query = query.Where("list_id IN ?", ids)
	}
	if ids := parseMultiValueQueryProvider(c, "group_ids"); len(ids) > 0 {
		query = query.Where("group_id IN ?", ids)
	}
	if ids := parseMultiValueQueryProvider(c, "tag_ids"); len(ids) > 0 {
		query = query.Where("id IN (?)", r.db.Table("reminder_tags").Select("reminder_id").Where("tag_id IN ?", ids))
	}
	if dueFrom := c.Query("due_from"); dueFrom != "" {
		if _, err := parseRFC3339Time(dueFrom); err != nil {
			return nil, badRequest("due_from 必须是 RFC3339 时间戳")
		}
		query = query.Where("due_at >= ?", dueFrom)
	}
	if dueTo := c.Query("due_to"); dueTo != "" {
		if _, err := parseRFC3339Time(dueTo); err != nil {
			return nil, badRequest("due_to 必须是 RFC3339 时间戳")
		}
		query = query.Where("due_at <= ?", dueTo)
	}
	var items []models.Reminder
	if err := query.Order("is_completed asc, due_at asc").Find(&items).Error; err != nil {
		return nil, err
	}
	return items, nil
}

func (r reminderRepository) listCompletionLogs(userID, reminderID string) ([]models.ReminderCompletionLog, error) {
	var logs []models.ReminderCompletionLog
	if err := r.db.Where("user_id = ? AND reminder_id = ?", userID, reminderID).Order("completed_at desc, created_at desc").Find(&logs).Error; err != nil {
		return nil, err
	}
	return logs, nil
}

func (r reminderRepository) create(item *models.Reminder, tagIDs []string) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		if err := insertReminder(tx, item); err != nil {
			return err
		}
		return replaceReminderTags(tx, item.ID, tagIDs)
	})
}

func (r reminderRepository) update(item *models.Reminder, tagIDs []string, replaceTags bool) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Save(item).Error; err != nil {
			return err
		}
		if replaceTags {
			return replaceReminderTags(tx, item.ID, tagIDs)
		}
		return nil
	})
}

func (r reminderRepository) softDelete(item *models.Reminder) error {
	now := nowISO()
	item.DeletedAt = &now
	item.UpdatedAt = now
	return r.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("reminder_id = ?", item.ID).Delete(&models.ReminderTag{}).Error; err != nil {
			return err
		}
		return tx.Save(item).Error
	})
}

func (r reminderRepository) rollover(userID string, current *models.Reminder, nextReminder *models.Reminder, tagIDs []string, nextDueAt string) error {
	now := nowISO()
	return r.db.Transaction(func(tx *gorm.DB) error {
		current.IsCompleted = true
		current.RepeatRule = "none"
		current.UpdatedAt = now
		if err := tx.Save(current).Error; err != nil {
			return err
		}
		if err := insertReminder(tx, nextReminder); err != nil {
			return err
		}
		if err := replaceReminderTags(tx, nextReminder.ID, tagIDs); err != nil {
			return err
		}
		return tx.Create(&models.ReminderCompletionLog{
			ID:            newID(),
			ReminderID:    current.ID,
			UserID:        userID,
			CompletedAt:   now,
			OriginalDueAt: current.DueAt,
			NextDueAt:     nextDueAt,
			CreatedAt:     now,
		}).Error
	})
}

func insertReminder(tx *gorm.DB, item *models.Reminder) error {
	values := map[string]any{
		"id":                    item.ID,
		"user_id":               item.UserID,
		"title":                 item.Title,
		"note":                  item.Note,
		"due_at":                item.DueAt,
		"repeat_until_at":       item.RepeatUntilAt,
		"remind_before_minutes": item.RemindBeforeMinutes,
		"is_completed":          item.IsCompleted,
		"list_id":               item.ListID,
		"group_id":              item.GroupID,
		"notification_enabled":  item.NotificationEnabled,
		"repeat_rule":           item.RepeatRule,
		"created_at":            item.CreatedAt,
		"updated_at":            item.UpdatedAt,
	}
	if item.DeletedAt != nil {
		values["deleted_at"] = *item.DeletedAt
	}
	return tx.Model(&models.Reminder{}).Create(values).Error
}
