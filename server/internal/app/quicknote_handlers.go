package app

import (
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"nexdo-server-golang/internal/http/response"
	"nexdo-server-golang/internal/models"

	"github.com/gin-gonic/gin"
)

func (a *Application) handleListQuickNotes(c *gin.Context) error {
	views, err := newQuickNoteService(a).list(c.MustGet("userID").(string), ginContextAdapter{ctx: c})
	if err != nil {
		return err
	}
	response.OK(c, views)
	return nil
}

func (a *Application) handleCreateQuickNote(c *gin.Context) error {
	userID := c.MustGet("userID").(string)
	contentType := c.ContentType()
	note := models.QuickNote{ID: newID(), UserID: userID, Status: "draft", CreatedAt: nowISO()}
	note.UpdatedAt = note.CreatedAt
	if strings.Contains(contentType, "multipart/form-data") {
		content, durationMS, waveform, audioFile, err := parseMultipartQuickNote(c)
		if err != nil {
			return err
		}
		note.Content = content
		note.AudioDurationMS = durationMS
		if len(waveform) > 0 {
			encoded, _ := json.Marshal(waveform)
			w := string(encoded)
			note.WaveformSamples = &w
		}
		if audioFile != nil {
			audioKey, audioSize, audioName, audioMime, err := a.storeQuickNoteAudio(userID, note.ID, audioFile)
			if err != nil {
				return err
			}
			note.AudioKey = &audioKey
			note.AudioFilename = &audioName
			note.AudioMimeType = &audioMime
			note.AudioSizeBytes = &audioSize
		}
	} else {
		var req quickNotePayload
		if err := decodeJSON(c, &req); err != nil {
			return err
		}
		view, err := newQuickNoteService(a).createFromJSON(userID, req, ginContextAdapter{ctx: c})
		if err != nil {
			return err
		}
		response.OK(c, view, 201)
		return nil
	}
	if err := a.db.Create(&note).Error; err != nil {
		if note.AudioKey != nil {
			_ = a.removeQuickNoteAudio(*note.AudioKey)
		}
		return err
	}
	response.OK(c, a.quickNoteView(c, note), 201)
	return nil
}

func (a *Application) handlePatchQuickNote(c *gin.Context) error {
	var req updateQuickNotePayload
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	view, err := newQuickNoteService(a).patch(c.MustGet("userID").(string), c.Param("id"), req, ginContextAdapter{ctx: c})
	if err != nil {
		return err
	}
	response.OK(c, view)
	return nil
}

func (a *Application) handleDeleteQuickNote(c *gin.Context) error {
	if err := newQuickNoteService(a).delete(c.MustGet("userID").(string), c.Param("id")); err != nil {
		return err
	}
	response.OK(c, gin.H{"deleted": true})
	return nil
}

func (a *Application) handleQuickNoteAudio(c *gin.Context) error {
	item, err := a.requireQuickNote(c.MustGet("userID").(string), c.Param("id"))
	if err != nil {
		return err
	}
	if item.AudioKey == nil {
		return notFound("录音不存在")
	}
	file, err := os.Open(*item.AudioKey)
	if err != nil {
		if os.IsNotExist(err) {
			return notFound("录音不存在")
		}
		return err
	}
	defer file.Close()
	if item.AudioMimeType != nil {
		c.Header("Content-Type", *item.AudioMimeType)
	}
	if item.AudioFilename != nil {
		c.Header("Content-Disposition", fmt.Sprintf("inline; filename*=UTF-8''%s", url.QueryEscape(*item.AudioFilename)))
	}
	_, err = io.Copy(c.Writer, file)
	return err
}

func (a *Application) handleConvertQuickNote(c *gin.Context) error {
	var req reminderPayload
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	userID := c.MustGet("userID").(string)
	item, err := a.requireQuickNote(userID, c.Param("id"))
	if err != nil {
		return err
	}
	created, err := a.createReminder(userID, req)
	if err != nil {
		return err
	}
	if reminder, ok := created.(reminderView); ok {
		item.Status = "converted"
		item.ConvertedReminderID = &reminder.ID
		item.UpdatedAt = nowISO()
		if err := a.db.Save(&item).Error; err != nil {
			return err
		}
	}
	response.OK(c, created)
	return nil
}

func (a *Application) quickNoteView(c *gin.Context, item models.QuickNote) quickNoteView {
	var samples []int
	if item.WaveformSamples != nil && *item.WaveformSamples != "" {
		_ = json.Unmarshal([]byte(*item.WaveformSamples), &samples)
	}
	var audioURL *string
	if item.AudioKey != nil {
		value := absoluteURL(c, fmt.Sprintf("/api/v1/quick-notes/%s/audio", item.ID))
		audioURL = &value
	}
	return quickNoteView{ID: item.ID, Content: item.Content, Status: item.Status, ConvertedReminderID: item.ConvertedReminderID, AudioKey: item.AudioKey, AudioFilename: item.AudioFilename, AudioMimeType: item.AudioMimeType, AudioSizeBytes: item.AudioSizeBytes, AudioDurationMS: item.AudioDurationMS, WaveformSamples: samples, AudioURL: audioURL, CreatedAt: item.CreatedAt, UpdatedAt: item.UpdatedAt}
}

func parseMultipartQuickNote(c *gin.Context) (string, *int64, []int, *multipart.FileHeader, error) {
	content := strings.TrimSpace(c.PostForm("content"))
	audioFile, _ := c.FormFile("audio")
	if content == "" && audioFile == nil {
		return "", nil, nil, nil, badRequest("content 或 audio 至少提供一个")
	}
	if audioFile != nil {
		if audioFile.Size > 10*1024*1024 {
			return "", nil, nil, nil, badRequest("audio 大小不能超过 10MB")
		}
		if !isAudioUpload(audioFile.Filename, audioFile.Header.Get("Content-Type")) {
			return "", nil, nil, nil, badRequest("audio 必须是音频文件")
		}
	}
	var durationMS *int64
	if raw := strings.TrimSpace(c.PostForm("audio_duration_ms")); raw != "" {
		value, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || value < 0 {
			return "", nil, nil, nil, badRequest("audio_duration_ms 必须是大于等于 0 的数字")
		}
		durationMS = &value
	}
	var waveform []int
	if raw := strings.TrimSpace(c.PostForm("waveform_samples")); raw != "" {
		if err := json.Unmarshal([]byte(raw), &waveform); err != nil {
			return "", nil, nil, nil, badRequest("waveform_samples 必须是数字数组 JSON")
		}
	}
	return content, durationMS, waveform, audioFile, nil
}

func (a *Application) storeQuickNoteAudio(userID, noteID string, file *multipart.FileHeader) (string, int64, string, string, error) {
	src, err := file.Open()
	if err != nil {
		return "", 0, "", "", err
	}
	defer src.Close()
	safeName := sanitizeFilename(file.Filename)
	key := filepath.Join(a.cfg.AudioStorageDir, "quick-notes", userID, noteID, safeName)
	if err := os.MkdirAll(filepath.Dir(key), 0o755); err != nil {
		return "", 0, "", "", err
	}
	dst, err := os.Create(key)
	if err != nil {
		return "", 0, "", "", err
	}
	defer dst.Close()
	size, err := io.Copy(dst, src)
	if err != nil {
		return "", 0, "", "", err
	}
	return key, size, safeName, detectAudioMimeType(file.Filename, file.Header.Get("Content-Type")), nil
}

func (a *Application) removeQuickNoteAudio(path string) error {
	if strings.TrimSpace(path) == "" {
		return nil
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	dir := filepath.Dir(path)
	for dir != "." && dir != "/" {
		if dir == a.cfg.AudioStorageDir || dir == filepath.Clean(a.cfg.AudioStorageDir) {
			break
		}
		if err := os.Remove(dir); err != nil {
			break
		}
		dir = filepath.Dir(dir)
	}
	return nil
}
