package app

import "nexdo-server-golang/internal/models"

type resourceRepository struct{}

func (r resourceRepository) createList(app *Application, item *models.List) error {
	return app.db.Create(item).Error
}

func (r resourceRepository) saveList(app *Application, item *models.List) error {
	return app.db.Save(item).Error
}

func (r resourceRepository) listLists(app *Application, userID string) ([]models.List, error) {
	var items []models.List
	if err := app.db.Where("user_id = ? AND deleted_at IS NULL", userID).Order("sort_order asc, created_at asc").Find(&items).Error; err != nil {
		return nil, err
	}
	return items, nil
}

func (r resourceRepository) listListReminderCount(app *Application, userID, listID string) (int64, error) {
	var count int64
	err := app.db.Model(&models.Reminder{}).Where("user_id = ? AND list_id = ? AND deleted_at IS NULL", userID, listID).Count(&count).Error
	return count, err
}

func (r resourceRepository) createGroup(app *Application, item *models.Group) error {
	return app.db.Create(item).Error
}

func (r resourceRepository) saveGroup(app *Application, item *models.Group) error {
	return app.db.Save(item).Error
}

func (r resourceRepository) listGroups(app *Application, userID string) ([]models.Group, error) {
	var items []models.Group
	if err := app.db.Where("user_id = ? AND deleted_at IS NULL", userID).Order("sort_order asc, created_at asc").Find(&items).Error; err != nil {
		return nil, err
	}
	return items, nil
}

func (r resourceRepository) listGroupReminderCount(app *Application, userID, groupID string) (int64, error) {
	var count int64
	err := app.db.Model(&models.Reminder{}).Where("user_id = ? AND group_id = ? AND deleted_at IS NULL", userID, groupID).Count(&count).Error
	return count, err
}

func (r resourceRepository) createTag(app *Application, item *models.Tag) error {
	return app.db.Create(item).Error
}

func (r resourceRepository) saveTag(app *Application, item *models.Tag) error {
	return app.db.Save(item).Error
}

func (r resourceRepository) listTags(app *Application, userID string) ([]models.Tag, error) {
	var items []models.Tag
	if err := app.db.Where("user_id = ? AND deleted_at IS NULL", userID).Order("created_at asc").Find(&items).Error; err != nil {
		return nil, err
	}
	return items, nil
}

func (r resourceRepository) deleteTagRelations(app *Application, tagID string) error {
	return app.db.Where("tag_id = ?", tagID).Delete(&models.ReminderTag{}).Error
}
