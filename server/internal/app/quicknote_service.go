package app

import (
	"encoding/json"
	"strings"

	"nexdo-server-golang/internal/models"
)

type quickNoteService struct {
	app  *Application
	repo quickNoteRepository
}

func newQuickNoteService(app *Application) quickNoteService {
	return quickNoteService{app: app, repo: quickNoteRepository{}}
}

func (s quickNoteService) list(userID string, qp requestContextProvider) ([]quickNoteView, error) {
	items, err := s.repo.list(s.app, userID)
	if err != nil {
		return nil, err
	}
	views := make([]quickNoteView, 0, len(items))
	for _, item := range items {
		views = append(views, s.app.quickNoteView(qp.GinContext(), item))
	}
	return views, nil
}

func (s quickNoteService) createFromJSON(userID string, req quickNotePayload, c requestContextProvider) (quickNoteView, error) {
	content := strings.TrimSpace(req.Content)
	if content == "" {
		return quickNoteView{}, badRequest("content 必填")
	}
	note := models.QuickNote{ID: newID(), UserID: userID, Status: "draft", Content: content, CreatedAt: nowISO()}
	note.UpdatedAt = note.CreatedAt
	if len(req.WaveformSamples) > 0 {
		encoded, _ := json.Marshal(req.WaveformSamples)
		w := string(encoded)
		note.WaveformSamples = &w
	}
	if err := s.repo.create(s.app, &note); err != nil {
		return quickNoteView{}, err
	}
	return s.app.quickNoteView(c.GinContext(), note), nil
}

func (s quickNoteService) patch(userID, id string, req updateQuickNotePayload, c requestContextProvider) (quickNoteView, error) {
	item, err := s.repo.get(s.app, userID, id)
	if err != nil {
		return quickNoteView{}, err
	}
	if req.Content != nil {
		content := strings.TrimSpace(*req.Content)
		if content == "" {
			return quickNoteView{}, badRequest("content 必填")
		}
		item.Content = content
	}
	if req.Status != nil {
		if *req.Status != "draft" && *req.Status != "converted" {
			return quickNoteView{}, badRequest("status 只能是 draft 或 converted")
		}
		if *req.Status == "converted" && item.ConvertedReminderID == nil {
			return quickNoteView{}, badRequest("status=converted 需要 converted_reminder_id")
		}
		if item.Status == "converted" && *req.Status == "draft" {
			return quickNoteView{}, badRequest("converted 状态不能改回 draft")
		}
		item.Status = *req.Status
	}
	if req.WaveformSamples != nil {
		encoded, _ := json.Marshal(req.WaveformSamples)
		w := string(encoded)
		item.WaveformSamples = &w
	}
	item.UpdatedAt = nowISO()
	if err := s.repo.save(s.app, &item); err != nil {
		return quickNoteView{}, err
	}
	return s.app.quickNoteView(c.GinContext(), item), nil
}

func (s quickNoteService) delete(userID, id string) error {
	item, err := s.repo.get(s.app, userID, id)
	if err != nil {
		return err
	}
	originalUpdatedAt := item.UpdatedAt
	originalDeletedAt := item.DeletedAt
	now := nowISO()
	item.DeletedAt = &now
	item.UpdatedAt = now
	if err := s.repo.save(s.app, &item); err != nil {
		return err
	}
	if item.AudioKey == nil {
		return nil
	}
	if err := s.app.removeQuickNoteAudio(*item.AudioKey); err != nil {
		item.DeletedAt = originalDeletedAt
		item.UpdatedAt = originalUpdatedAt
		if revertErr := s.repo.save(s.app, &item); revertErr != nil {
			return internal("删除闪念音频失败且数据库回滚失败: " + revertErr.Error())
		}
		return err
	}
	return nil
}
