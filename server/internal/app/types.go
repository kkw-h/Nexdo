package app

import (
	"encoding/json"

	"nexdo-server-golang/internal/models"
)

type bootstrapData struct {
	Lists      []models.List   `json:"lists"`
	Groups     []models.Group  `json:"groups"`
	Tags       []models.Tag    `json:"tags"`
	Reminders  []reminderView  `json:"reminders"`
	QuickNotes []quickNoteView `json:"quick_notes"`
	ServerTime string          `json:"server_time"`
}

type changesData struct {
	Lists               []models.List   `json:"lists"`
	DeletedListIDs      []string        `json:"deleted_list_ids"`
	Groups              []models.Group  `json:"groups"`
	DeletedGroupIDs     []string        `json:"deleted_group_ids"`
	Tags                []models.Tag    `json:"tags"`
	DeletedTagIDs       []string        `json:"deleted_tag_ids"`
	Reminders           []reminderView  `json:"reminders"`
	DeletedReminderIDs  []string        `json:"deleted_reminder_ids"`
	QuickNotes          []quickNoteView `json:"quick_notes"`
	DeletedQuickNoteIDs []string        `json:"deleted_quick_note_ids"`
	ServerTime          string          `json:"server_time"`
}

type reminderView struct {
	ID                  string       `json:"id"`
	Title               string       `json:"title"`
	Note                string       `json:"note"`
	DueAt               string       `json:"due_at"`
	RepeatUntilAt       *string      `json:"repeat_until_at"`
	RemindBeforeMinutes int          `json:"remind_before_minutes"`
	IsCompleted         bool         `json:"is_completed"`
	ListID              string       `json:"list_id"`
	GroupID             string       `json:"group_id"`
	NotificationEnabled bool         `json:"notification_enabled"`
	RepeatRule          string       `json:"repeat_rule"`
	CreatedAt           string       `json:"created_at"`
	UpdatedAt           string       `json:"updated_at"`
	Tags                []models.Tag `json:"tags"`
}

type quickNoteView struct {
	ID                  string  `json:"id"`
	Content             string  `json:"content"`
	Status              string  `json:"status"`
	ConvertedReminderID *string `json:"converted_reminder_id"`
	AudioKey            *string `json:"audio_key"`
	AudioFilename       *string `json:"audio_filename"`
	AudioMimeType       *string `json:"audio_mime_type"`
	AudioSizeBytes      *int64  `json:"audio_size_bytes"`
	AudioDurationMS     *int64  `json:"audio_duration_ms"`
	WaveformSamples     []int   `json:"waveform_samples"`
	AudioURL            *string `json:"audio_url"`
	CreatedAt           string  `json:"created_at"`
	UpdatedAt           string  `json:"updated_at"`
}

type registerRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Nickname string `json:"nickname"`
	Timezone string `json:"timezone"`
	Locale   string `json:"locale"`
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type updateProfileRequest struct {
	Nickname  *string `json:"nickname"`
	AvatarURL *string `json:"avatar_url"`
	Timezone  *string `json:"timezone"`
	Locale    *string `json:"locale"`
}

type changePasswordRequest struct {
	OldPassword string `json:"old_password"`
	NewPassword string `json:"new_password"`
}

type listPayload struct {
	Name       string `json:"name"`
	ColorValue int    `json:"color_value"`
	SortOrder  *int   `json:"sort_order"`
}

type groupPayload struct {
	Name          string `json:"name"`
	IconCodePoint int    `json:"icon_code_point"`
	SortOrder     *int   `json:"sort_order"`
}

type tagPayload struct {
	Name       string `json:"name"`
	ColorValue int    `json:"color_value"`
}

type updateListPayload struct {
	Name       *string `json:"name"`
	ColorValue *int    `json:"color_value"`
	SortOrder  *int    `json:"sort_order"`
}

type updateGroupPayload struct {
	Name          *string `json:"name"`
	IconCodePoint *int    `json:"icon_code_point"`
	SortOrder     *int    `json:"sort_order"`
}

type updateTagPayload struct {
	Name       *string `json:"name"`
	ColorValue *int    `json:"color_value"`
}

type reminderPayload struct {
	Title               string   `json:"title"`
	Note                *string  `json:"note"`
	DueAt               string   `json:"due_at"`
	RepeatUntilAt       *string  `json:"repeat_until_at"`
	RemindBeforeMinutes *int     `json:"remind_before_minutes"`
	ListID              string   `json:"list_id"`
	GroupID             string   `json:"group_id"`
	TagIDs              []string `json:"tag_ids"`
	NotificationEnabled *bool    `json:"notification_enabled"`
	RepeatRule          *string  `json:"repeat_rule"`
}

type updateReminderPayload struct {
	Title               *string        `json:"title"`
	Note                *string        `json:"note"`
	DueAt               *string        `json:"due_at"`
	RepeatUntilAt       optionalString `json:"repeat_until_at"`
	RemindBeforeMinutes *int           `json:"remind_before_minutes"`
	ListID              *string        `json:"list_id"`
	GroupID             *string        `json:"group_id"`
	TagIDs              []string       `json:"tag_ids"`
	NotificationEnabled *bool          `json:"notification_enabled"`
	RepeatRule          *string        `json:"repeat_rule"`
	IsCompleted         *bool          `json:"is_completed"`
}

type optionalString struct {
	Set   bool
	Valid bool
	Value string
}

func (o *optionalString) UnmarshalJSON(data []byte) error {
	o.Set = true
	if string(data) == "null" {
		o.Valid = false
		o.Value = ""
		return nil
	}
	o.Valid = true
	return json.Unmarshal(data, &o.Value)
}

type quickNotePayload struct {
	Content         string `json:"content"`
	WaveformSamples []int  `json:"waveform_samples"`
}

type updateQuickNotePayload struct {
	Content         *string `json:"content"`
	Status          *string `json:"status"`
	WaveformSamples []int   `json:"waveform_samples"`
}
