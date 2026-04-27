package app

import "nexdo-server-golang/internal/models"

type resourceService struct {
	app  *Application
	repo resourceRepository
}

func newResourceService(app *Application) resourceService {
	return resourceService{app: app, repo: resourceRepository{}}
}

func (s resourceService) listLists(userID string) ([]models.List, error) {
	return s.repo.listLists(s.app, userID)
}

func (s resourceService) createList(userID string, req listPayload) (models.List, error) {
	item := models.List{ID: newID(), UserID: userID, Name: req.Name, ColorValue: req.ColorValue, SortOrder: valueOrDefault(req.SortOrder, 0), CreatedAt: nowISO(), UpdatedAt: nowISO()}
	return item, s.repo.createList(s.app, &item)
}

func (s resourceService) patchList(userID, id string, req updateListPayload) (models.List, error) {
	item, err := s.app.requireList(userID, id)
	if err != nil {
		return models.List{}, err
	}
	if req.Name != nil {
		item.Name = *req.Name
	}
	if req.ColorValue != nil {
		item.ColorValue = *req.ColorValue
	}
	if req.SortOrder != nil {
		item.SortOrder = *req.SortOrder
	}
	item.UpdatedAt = nowISO()
	return item, s.repo.saveList(s.app, &item)
}

func (s resourceService) deleteList(userID, id string) error {
	item, err := s.app.requireList(userID, id)
	if err != nil {
		return err
	}
	count, err := s.repo.listListReminderCount(s.app, userID, item.ID)
	if err != nil {
		return err
	}
	if count > 0 {
		return conflict(40901, "清单仍被使用")
	}
	now := nowISO()
	item.DeletedAt = &now
	item.UpdatedAt = now
	return s.repo.saveList(s.app, &item)
}

func (s resourceService) listGroups(userID string) ([]models.Group, error) {
	return s.repo.listGroups(s.app, userID)
}

func (s resourceService) createGroup(userID string, req groupPayload) (models.Group, error) {
	item := models.Group{ID: newID(), UserID: userID, Name: req.Name, IconCodePoint: req.IconCodePoint, SortOrder: valueOrDefault(req.SortOrder, 0), CreatedAt: nowISO(), UpdatedAt: nowISO()}
	return item, s.repo.createGroup(s.app, &item)
}

func (s resourceService) patchGroup(userID, id string, req updateGroupPayload) (models.Group, error) {
	item, err := s.app.requireGroup(userID, id)
	if err != nil {
		return models.Group{}, err
	}
	if req.Name != nil {
		item.Name = *req.Name
	}
	if req.IconCodePoint != nil {
		item.IconCodePoint = *req.IconCodePoint
	}
	if req.SortOrder != nil {
		item.SortOrder = *req.SortOrder
	}
	item.UpdatedAt = nowISO()
	return item, s.repo.saveGroup(s.app, &item)
}

func (s resourceService) deleteGroup(userID, id string) error {
	item, err := s.app.requireGroup(userID, id)
	if err != nil {
		return err
	}
	count, err := s.repo.listGroupReminderCount(s.app, userID, item.ID)
	if err != nil {
		return err
	}
	if count > 0 {
		return conflict(40902, "分组仍被使用")
	}
	now := nowISO()
	item.DeletedAt = &now
	item.UpdatedAt = now
	return s.repo.saveGroup(s.app, &item)
}

func (s resourceService) listTags(userID string) ([]models.Tag, error) {
	return s.repo.listTags(s.app, userID)
}

func (s resourceService) createTag(userID string, req tagPayload) (models.Tag, error) {
	item := models.Tag{ID: newID(), UserID: userID, Name: req.Name, ColorValue: req.ColorValue, CreatedAt: nowISO(), UpdatedAt: nowISO()}
	return item, s.repo.createTag(s.app, &item)
}

func (s resourceService) patchTag(userID, id string, req updateTagPayload) (models.Tag, error) {
	item, err := s.app.requireTag(userID, id)
	if err != nil {
		return models.Tag{}, err
	}
	if req.Name != nil {
		item.Name = *req.Name
	}
	if req.ColorValue != nil {
		item.ColorValue = *req.ColorValue
	}
	item.UpdatedAt = nowISO()
	return item, s.repo.saveTag(s.app, &item)
}

func (s resourceService) deleteTag(userID, id string) error {
	item, err := s.app.requireTag(userID, id)
	if err != nil {
		return err
	}
	if err := s.repo.deleteTagRelations(s.app, item.ID); err != nil {
		return err
	}
	now := nowISO()
	item.DeletedAt = &now
	item.UpdatedAt = now
	return s.repo.saveTag(s.app, &item)
}
