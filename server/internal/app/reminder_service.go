package app

import (
	"strings"

	"nexdo-server-golang/internal/models"
)

type reminderService struct {
	app  *Application
	repo reminderRepository
}

func newReminderService(app *Application) reminderService {
	return reminderService{app: app, repo: reminderRepository{db: app.db}}
}

func (a *Application) reminderView(reminder models.Reminder) (reminderView, error) {
	tags, err := a.reminderTags(reminder.ID)
	if err != nil {
		return reminderView{}, err
	}
	return reminderView{ID: reminder.ID, Title: reminder.Title, Note: reminder.Note, DueAt: reminder.DueAt, RepeatUntilAt: reminder.RepeatUntilAt, RemindBeforeMinutes: reminder.RemindBeforeMinutes, IsCompleted: reminder.IsCompleted, ListID: reminder.ListID, GroupID: reminder.GroupID, NotificationEnabled: reminder.NotificationEnabled, RepeatRule: normalizeRepeatRule(reminder.RepeatRule), CreatedAt: reminder.CreatedAt, UpdatedAt: reminder.UpdatedAt, Tags: tags}, nil
}

func (a *Application) reminderViews(reminders []models.Reminder) ([]reminderView, error) {
	ids := make([]string, 0, len(reminders))
	for _, reminder := range reminders {
		ids = append(ids, reminder.ID)
	}
	tagsByReminderID, err := a.reminderTagsByIDs(ids)
	if err != nil {
		return nil, err
	}
	views := make([]reminderView, 0, len(reminders))
	for _, reminder := range reminders {
		views = append(views, reminderView{
			ID:                  reminder.ID,
			Title:               reminder.Title,
			Note:                reminder.Note,
			DueAt:               reminder.DueAt,
			RepeatUntilAt:       reminder.RepeatUntilAt,
			RemindBeforeMinutes: reminder.RemindBeforeMinutes,
			IsCompleted:         reminder.IsCompleted,
			ListID:              reminder.ListID,
			GroupID:             reminder.GroupID,
			NotificationEnabled: reminder.NotificationEnabled,
			RepeatRule:          normalizeRepeatRule(reminder.RepeatRule),
			CreatedAt:           reminder.CreatedAt,
			UpdatedAt:           reminder.UpdatedAt,
			Tags:                tagsByReminderID[reminder.ID],
		})
	}
	return views, nil
}

func (a *Application) createReminder(userID string, req reminderPayload) (any, error) {
	return newReminderService(a).create(userID, req)
}

func (a *Application) listReminders(userID string, c queryProvider) ([]reminderView, error) {
	return newReminderService(a).list(userID, c)
}

func (s reminderService) get(userID, id string) (reminderView, error) {
	item, err := s.repo.get(userID, id)
	if err != nil {
		return reminderView{}, err
	}
	return s.app.reminderView(item)
}

func (s reminderService) list(userID string, c queryProvider) ([]reminderView, error) {
	items, err := s.repo.list(userID, c)
	if err != nil {
		return nil, err
	}
	return s.app.reminderViews(items)
}

func (s reminderService) logs(userID, id string) ([]models.ReminderCompletionLog, error) {
	if _, err := s.repo.get(userID, id); err != nil {
		return nil, err
	}
	return s.repo.listCompletionLogs(userID, id)
}

func (s reminderService) create(userID string, req reminderPayload) (reminderView, error) {
	if err := validateReminderPayload(req); err != nil {
		return reminderView{}, err
	}
	if _, err := s.app.requireList(userID, req.ListID); err != nil {
		return reminderView{}, err
	}
	if _, err := s.app.requireGroup(userID, req.GroupID); err != nil {
		return reminderView{}, err
	}
	if err := s.app.ensureTagsOwned(userID, req.TagIDs); err != nil {
		return reminderView{}, err
	}
	rule, err := validateReminderSchedule(req.DueAt, req.RepeatRule, req.RepeatUntilAt, req.RemindBeforeMinutes)
	if err != nil {
		return reminderView{}, err
	}
	now := nowISO()
	item := models.Reminder{ID: newID(), UserID: userID, Title: req.Title, Note: valueOrDefault(req.Note, ""), DueAt: req.DueAt, RepeatUntilAt: req.RepeatUntilAt, RemindBeforeMinutes: valueOrDefault(req.RemindBeforeMinutes, 0), ListID: req.ListID, GroupID: req.GroupID, NotificationEnabled: boolOrDefault(req.NotificationEnabled, true), RepeatRule: rule, CreatedAt: now, UpdatedAt: now}
	if err := s.repo.create(&item, req.TagIDs); err != nil {
		return reminderView{}, err
	}
	created, err := s.repo.get(userID, item.ID)
	if err != nil {
		return reminderView{}, err
	}
	return s.app.reminderView(created)
}

func (s reminderService) patch(userID, id string, req updateReminderPayload) (reminderView, error) {
	current, err := s.repo.get(userID, id)
	if err != nil {
		return reminderView{}, err
	}
	if current.RepeatRule != "none" && req.IsCompleted != nil && *req.IsCompleted {
		return s.rollover(userID, current)
	}
	if current.RepeatRule != "none" && req.DueAt != nil && *req.DueAt != current.DueAt && req.Title == nil && req.Note == nil && req.ListID == nil && req.GroupID == nil && req.NotificationEnabled == nil && req.RepeatRule == nil && req.IsCompleted == nil {
		nextDueAt, err := nextDate(current.RepeatRule, current.DueAt)
		if err != nil {
			return reminderView{}, err
		}
		normalizedPatch, err := parseRFC3339Time(*req.DueAt)
		if err != nil {
			return reminderView{}, badRequest("due_at 必须是 RFC3339 时间戳")
		}
		normalizedExpected, _ := parseRFC3339Time(nextDueAt)
		if normalizedPatch.UTC().Equal(normalizedExpected.UTC()) {
			return s.rollover(userID, current)
		}
	}

	next := current
	if req.Title != nil {
		next.Title = *req.Title
	}
	if req.Note != nil {
		next.Note = *req.Note
	}
	if req.DueAt != nil {
		next.DueAt = *req.DueAt
	}
	if req.RepeatUntilAt.Set {
		if req.RepeatUntilAt.Valid {
			value := strings.TrimSpace(req.RepeatUntilAt.Value)
			next.RepeatUntilAt = &value
		} else {
			next.RepeatUntilAt = nil
		}
	}
	if req.RemindBeforeMinutes != nil {
		next.RemindBeforeMinutes = *req.RemindBeforeMinutes
	}
	if req.ListID != nil {
		if _, err := s.app.requireList(userID, *req.ListID); err != nil {
			return reminderView{}, err
		}
		next.ListID = *req.ListID
	}
	if req.GroupID != nil {
		if _, err := s.app.requireGroup(userID, *req.GroupID); err != nil {
			return reminderView{}, err
		}
		next.GroupID = *req.GroupID
	}
	if req.NotificationEnabled != nil {
		next.NotificationEnabled = *req.NotificationEnabled
	}
	if req.RepeatRule != nil {
		next.RepeatRule = *req.RepeatRule
	}
	if req.IsCompleted != nil {
		next.IsCompleted = *req.IsCompleted
	}
	rule, err := validateReminderSchedule(next.DueAt, &next.RepeatRule, next.RepeatUntilAt, &next.RemindBeforeMinutes)
	if err != nil {
		return reminderView{}, err
	}
	next.RepeatRule = rule
	next.UpdatedAt = nowISO()
	replaceTags := req.TagIDs != nil
	if replaceTags {
		if err := s.app.ensureTagsOwned(userID, req.TagIDs); err != nil {
			return reminderView{}, err
		}
	}
	if err := s.repo.update(&next, req.TagIDs, replaceTags); err != nil {
		return reminderView{}, err
	}
	return s.app.reminderView(next)
}

func (s reminderService) complete(userID, id string) (reminderView, error) {
	current, err := s.repo.get(userID, id)
	if err != nil {
		return reminderView{}, err
	}
	if current.RepeatRule == "none" {
		return s.completeCurrent(current)
	}
	return s.rollover(userID, current)
}

func (s reminderService) uncomplete(userID, id string) (reminderView, error) {
	current, err := s.repo.get(userID, id)
	if err != nil {
		return reminderView{}, err
	}
	current.IsCompleted = false
	current.UpdatedAt = nowISO()
	if err := s.repo.update(&current, nil, false); err != nil {
		return reminderView{}, err
	}
	return s.app.reminderView(current)
}

func (s reminderService) delete(userID, id string) error {
	current, err := s.repo.get(userID, id)
	if err != nil {
		return err
	}
	return s.repo.softDelete(&current)
}

func (s reminderService) rollover(userID string, current models.Reminder) (reminderView, error) {
	nextDueAt, err := nextDate(current.RepeatRule, current.DueAt)
	if err != nil {
		return reminderView{}, err
	}
	if shouldStopRecurringRollover(current.RepeatUntilAt, nextDueAt) {
		return s.completeCurrent(current)
	}
	tagIDs, err := s.app.reminderTagIDs(current.ID)
	if err != nil {
		return reminderView{}, err
	}
	now := nowISO()
	nextReminder := current
	nextReminder.ID = newID()
	nextReminder.DueAt = nextDueAt
	nextReminder.IsCompleted = false
	nextReminder.CreatedAt = now
	nextReminder.UpdatedAt = now
	if err := s.repo.rollover(userID, &current, &nextReminder, tagIDs, nextDueAt); err != nil {
		return reminderView{}, err
	}
	created, err := s.repo.get(userID, nextReminder.ID)
	if err != nil {
		return reminderView{}, err
	}
	return s.app.reminderView(created)
}

func (s reminderService) completeCurrent(current models.Reminder) (reminderView, error) {
	current.IsCompleted = true
	current.RepeatRule = "none"
	current.UpdatedAt = nowISO()
	if err := s.repo.update(&current, nil, false); err != nil {
		return reminderView{}, err
	}
	return s.app.reminderView(current)
}

func shouldStopRecurringRollover(repeatUntilAt *string, nextDueAt string) bool {
	if repeatUntilAt == nil || strings.TrimSpace(*repeatUntilAt) == "" {
		return false
	}
	repeatUntilTS, err := parseRFC3339Time(*repeatUntilAt)
	if err != nil {
		return false
	}
	nextDueTS, err := parseRFC3339Time(nextDueAt)
	if err != nil {
		return false
	}
	return nextDueTS.UTC().After(repeatUntilTS.UTC())
}
