package app

import "nexdo-server-golang/internal/models"

import "gorm.io/gorm"

type authRepository struct{}

func (r authRepository) countUsersByEmail(app *Application, email string) (int64, error) {
	var count int64
	err := app.db.Model(&models.User{}).Where("email = ?", email).Count(&count).Error
	return count, err
}

func (r authRepository) getUserByEmail(app *Application, email string) (models.User, error) {
	var user models.User
	if err := app.db.Where("email = ?", email).First(&user).Error; err != nil {
		return models.User{}, err
	}
	return user, nil
}

func (r authRepository) getUserByID(app *Application, id string) (models.User, error) {
	var user models.User
	if err := app.db.Where("id = ?", id).First(&user).Error; err != nil {
		return models.User{}, err
	}
	return user, nil
}

func (r authRepository) createUserWithDefaults(app *Application, user *models.User) error {
	now := user.CreatedAt
	return app.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(user).Error; err != nil {
			return err
		}
		if err := tx.Create(&models.List{ID: newID(), UserID: user.ID, Name: "我的清单", ColorValue: 0, SortOrder: 0, CreatedAt: now, UpdatedAt: now}).Error; err != nil {
			return err
		}
		if err := tx.Create(&models.Group{ID: newID(), UserID: user.ID, Name: "我的分组", IconCodePoint: 0, SortOrder: 0, CreatedAt: now, UpdatedAt: now}).Error; err != nil {
			return err
		}
		return tx.Create(&models.Tag{ID: newID(), UserID: user.ID, Name: "重要", ColorValue: 0, CreatedAt: now, UpdatedAt: now}).Error
	})
}

func (r authRepository) saveUser(app *Application, user *models.User) error {
	return app.db.Save(user).Error
}

func (r authRepository) createSession(app *Application, session *models.Session) error {
	return app.db.Create(session).Error
}

func (r authRepository) saveSession(app *Application, session *models.Session) error {
	return app.db.Save(session).Error
}

func (r authRepository) getSession(app *Application, sessionID string) (models.Session, error) {
	var session models.Session
	if err := app.db.Where("id = ?", sessionID).First(&session).Error; err != nil {
		return models.Session{}, err
	}
	return session, nil
}

func (r authRepository) rotateSession(app *Application, session *models.Session, refreshTokenID, expiresAt string) error {
	return app.db.Transaction(func(tx *gorm.DB) error {
		session.RefreshTokenID = refreshTokenID
		session.ExpiresAt = expiresAt
		session.LastUsedAt = nowISO()
		session.UpdatedAt = session.LastUsedAt
		session.RevokedAt = nil
		return tx.Save(session).Error
	})
}

func (r authRepository) revokeSession(app *Application, sessionID, userID string) (bool, error) {
	now := nowISO()
	result := app.db.Model(&models.Session{}).
		Where("id = ? AND user_id = ? AND revoked_at IS NULL", sessionID, userID).
		Updates(map[string]any{"revoked_at": now, "updated_at": now, "last_used_at": now})
	if result.Error != nil {
		return false, result.Error
	}
	return result.RowsAffected > 0, nil
}

func (r authRepository) revokeSessionsByUser(app *Application, userID string) error {
	now := nowISO()
	return app.db.Model(&models.Session{}).
		Where("user_id = ? AND revoked_at IS NULL", userID).
		Updates(map[string]any{"revoked_at": now, "updated_at": now, "last_used_at": now}).Error
}

func (r authRepository) listDevices(app *Application, userID string) ([]models.Device, error) {
	var devices []models.Device
	if err := app.db.Where("user_id = ?", userID).Order("updated_at desc").Find(&devices).Error; err != nil {
		return nil, err
	}
	return devices, nil
}

func (r authRepository) deleteDevice(app *Application, userID, id string) (bool, error) {
	var device models.Device
	if err := app.db.Where("user_id = ? AND (id = ? OR device_id = ?)", userID, id, id).First(&device).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return false, nil
		}
		return false, err
	}
	now := nowISO()
	if err := app.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("user_id = ? AND device_id = ? AND revoked_at IS NULL", userID, device.DeviceID).
			Model(&models.Session{}).
			Updates(map[string]any{"revoked_at": now, "updated_at": now, "last_used_at": now}).Error; err != nil {
			return err
		}
		return tx.Delete(&device).Error
	}); err != nil {
		return false, err
	}
	return true, nil
}
