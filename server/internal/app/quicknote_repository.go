package app

import "nexdo-server-golang/internal/models"

type quickNoteRepository struct{}

func (r quickNoteRepository) get(app *Application, userID, id string) (models.QuickNote, error) {
	return app.requireQuickNote(userID, id)
}

func (r quickNoteRepository) list(app *Application, userID string) ([]models.QuickNote, error) {
	var items []models.QuickNote
	if err := app.db.Where("user_id = ? AND deleted_at IS NULL", userID).Order("created_at desc").Find(&items).Error; err != nil {
		return nil, err
	}
	return items, nil
}

func (r quickNoteRepository) create(app *Application, note *models.QuickNote) error {
	return app.db.Create(note).Error
}

func (r quickNoteRepository) save(app *Application, note *models.QuickNote) error {
	return app.db.Save(note).Error
}
