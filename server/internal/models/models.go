package models

type User struct {
	ID           string `gorm:"primaryKey;type:text" json:"id"`
	Email        string `gorm:"uniqueIndex;not null" json:"email"`
	PasswordHash string `gorm:"column:password_hash;not null" json:"-"`
	Nickname     string `gorm:"not null;default:''" json:"nickname"`
	AvatarURL    string `gorm:"column:avatar_url;not null;default:''" json:"avatar_url"`
	Timezone     string `gorm:"not null;default:'UTC'" json:"timezone"`
	Locale       string `gorm:"not null;default:'en-US'" json:"locale"`
	CreatedAt    string `gorm:"column:created_at;not null" json:"created_at"`
	UpdatedAt    string `gorm:"column:updated_at;not null" json:"updated_at"`
}

func (User) TableName() string { return "users" }

type Device struct {
	ID         string `gorm:"primaryKey;type:text" json:"id"`
	UserID     string `gorm:"column:user_id;index;not null" json:"user_id"`
	DeviceID   string `gorm:"column:device_id;uniqueIndex;not null" json:"device_id"`
	DeviceName string `gorm:"column:device_name;not null;default:''" json:"device_name"`
	Platform   string `gorm:"not null;default:''" json:"platform"`
	UserAgent  string `gorm:"column:user_agent;not null;default:''" json:"user_agent"`
	IPAddress  string `gorm:"column:ip_address;not null;default:''" json:"ip_address"`
	LastSeenAt string `gorm:"column:last_seen_at;not null" json:"last_seen_at"`
	CreatedAt  string `gorm:"column:created_at;not null" json:"created_at"`
	UpdatedAt  string `gorm:"column:updated_at;not null" json:"updated_at"`
}

func (Device) TableName() string { return "devices" }

type Session struct {
	ID             string  `gorm:"primaryKey;type:text" json:"id"`
	UserID         string  `gorm:"column:user_id;index;not null" json:"user_id"`
	DeviceID       *string `gorm:"column:device_id;index" json:"device_id"`
	RefreshTokenID string  `gorm:"column:refresh_token_id;not null" json:"refresh_token_id"`
	ExpiresAt      string  `gorm:"column:expires_at;not null" json:"expires_at"`
	LastUsedAt     string  `gorm:"column:last_used_at;not null" json:"last_used_at"`
	RevokedAt      *string `gorm:"column:revoked_at" json:"revoked_at,omitempty"`
	CreatedAt      string  `gorm:"column:created_at;not null" json:"created_at"`
	UpdatedAt      string  `gorm:"column:updated_at;not null" json:"updated_at"`
}

func (Session) TableName() string { return "sessions" }

type List struct {
	ID         string  `gorm:"primaryKey;type:text" json:"id"`
	UserID     string  `gorm:"column:user_id;index;not null" json:"user_id"`
	Name       string  `gorm:"not null" json:"name"`
	ColorValue int     `gorm:"column:color_value;not null" json:"color_value"`
	SortOrder  int     `gorm:"column:sort_order;not null;default:0" json:"sort_order"`
	CreatedAt  string  `gorm:"column:created_at;not null" json:"created_at"`
	UpdatedAt  string  `gorm:"column:updated_at;not null" json:"updated_at"`
	DeletedAt  *string `gorm:"column:deleted_at" json:"deleted_at,omitempty"`
}

func (List) TableName() string { return "lists" }

type Group struct {
	ID            string  `gorm:"primaryKey;type:text" json:"id"`
	UserID        string  `gorm:"column:user_id;index;not null" json:"user_id"`
	Name          string  `gorm:"not null" json:"name"`
	IconCodePoint int     `gorm:"column:icon_code_point;not null" json:"icon_code_point"`
	SortOrder     int     `gorm:"column:sort_order;not null;default:0" json:"sort_order"`
	CreatedAt     string  `gorm:"column:created_at;not null" json:"created_at"`
	UpdatedAt     string  `gorm:"column:updated_at;not null" json:"updated_at"`
	DeletedAt     *string `gorm:"column:deleted_at" json:"deleted_at,omitempty"`
}

func (Group) TableName() string { return "groups" }

type Tag struct {
	ID         string  `gorm:"primaryKey;type:text" json:"id"`
	UserID     string  `gorm:"column:user_id;index;not null" json:"user_id"`
	Name       string  `gorm:"not null" json:"name"`
	ColorValue int     `gorm:"column:color_value;not null" json:"color_value"`
	CreatedAt  string  `gorm:"column:created_at;not null" json:"created_at"`
	UpdatedAt  string  `gorm:"column:updated_at;not null" json:"updated_at"`
	DeletedAt  *string `gorm:"column:deleted_at" json:"deleted_at,omitempty"`
}

func (Tag) TableName() string { return "tags" }

type Reminder struct {
	ID                  string  `gorm:"primaryKey;type:text" json:"id"`
	UserID              string  `gorm:"column:user_id;index;not null" json:"user_id"`
	Title               string  `gorm:"not null" json:"title"`
	Note                string  `gorm:"not null;default:''" json:"note"`
	DueAt               string  `gorm:"column:due_at;not null" json:"due_at"`
	RepeatUntilAt       *string `gorm:"column:repeat_until_at" json:"repeat_until_at,omitempty"`
	RemindBeforeMinutes int     `gorm:"column:remind_before_minutes;not null;default:0" json:"remind_before_minutes"`
	IsCompleted         bool    `gorm:"column:is_completed;not null;default:false" json:"is_completed"`
	ListID              string  `gorm:"column:list_id;not null" json:"list_id"`
	GroupID             string  `gorm:"column:group_id;not null" json:"group_id"`
	NotificationEnabled bool    `gorm:"column:notification_enabled;not null;default:true" json:"notification_enabled"`
	RepeatRule          string  `gorm:"column:repeat_rule;not null;default:none" json:"repeat_rule"`
	CreatedAt           string  `gorm:"column:created_at;not null" json:"created_at"`
	UpdatedAt           string  `gorm:"column:updated_at;not null" json:"updated_at"`
	DeletedAt           *string `gorm:"column:deleted_at" json:"deleted_at,omitempty"`
}

func (Reminder) TableName() string { return "reminders" }

type ReminderTag struct {
	ReminderID string `gorm:"column:reminder_id;primaryKey;type:text"`
	TagID      string `gorm:"column:tag_id;primaryKey;type:text"`
}

func (ReminderTag) TableName() string { return "reminder_tags" }

type ReminderCompletionLog struct {
	ID            string `gorm:"primaryKey;type:text" json:"id"`
	ReminderID    string `gorm:"column:reminder_id;index;not null" json:"reminder_id"`
	UserID        string `gorm:"column:user_id;index;not null" json:"user_id"`
	CompletedAt   string `gorm:"column:completed_at;not null" json:"completed_at"`
	OriginalDueAt string `gorm:"column:original_due_at;not null" json:"original_due_at"`
	NextDueAt     string `gorm:"column:next_due_at;not null" json:"next_due_at"`
	CreatedAt     string `gorm:"column:created_at;not null" json:"created_at"`
}

func (ReminderCompletionLog) TableName() string { return "reminder_completion_logs" }

type QuickNote struct {
	ID                  string  `gorm:"primaryKey;type:text" json:"id"`
	UserID              string  `gorm:"column:user_id;index;not null" json:"user_id"`
	Content             string  `gorm:"not null" json:"content"`
	Status              string  `gorm:"not null;default:draft" json:"status"`
	ConvertedReminderID *string `gorm:"column:converted_reminder_id" json:"converted_reminder_id"`
	AudioKey            *string `gorm:"column:audio_key" json:"audio_key"`
	AudioFilename       *string `gorm:"column:audio_filename" json:"audio_filename"`
	AudioMimeType       *string `gorm:"column:audio_mime_type" json:"audio_mime_type"`
	AudioSizeBytes      *int64  `gorm:"column:audio_size_bytes" json:"audio_size_bytes"`
	AudioDurationMS     *int64  `gorm:"column:audio_duration_ms" json:"audio_duration_ms"`
	WaveformSamples     *string `gorm:"column:waveform_samples" json:"waveform_samples"`
	CreatedAt           string  `gorm:"column:created_at;not null" json:"created_at"`
	UpdatedAt           string  `gorm:"column:updated_at;not null" json:"updated_at"`
	DeletedAt           *string `gorm:"column:deleted_at" json:"deleted_at,omitempty"`
}

func (QuickNote) TableName() string { return "quick_notes" }

type AICommandConfirmation struct {
	ID            string  `gorm:"primaryKey;type:text" json:"id"`
	UserID        string  `gorm:"column:user_id;index;not null" json:"user_id"`
	TokenID       string  `gorm:"column:token_id;uniqueIndex;not null" json:"token_id"`
	Intent        string  `gorm:"not null" json:"intent"`
	OperationType string  `gorm:"column:operation_type;not null" json:"operation_type"`
	Action        string  `gorm:"not null" json:"action"`
	TargetType    string  `gorm:"column:target_type;not null" json:"target_type"`
	TargetIDsJSON string  `gorm:"column:target_ids_json;not null" json:"target_ids_json"`
	PatchJSON     string  `gorm:"column:patch_json;not null" json:"patch_json"`
	PlanJSON      string  `gorm:"column:plan_json;not null" json:"plan_json"`
	ProposalHash  string  `gorm:"column:proposal_hash;not null" json:"proposal_hash"`
	ExpiresAt     string  `gorm:"column:expires_at;not null" json:"expires_at"`
	ConsumedAt    *string `gorm:"column:consumed_at" json:"consumed_at,omitempty"`
	CreatedAt     string  `gorm:"column:created_at;not null" json:"created_at"`
	UpdatedAt     string  `gorm:"column:updated_at;not null" json:"updated_at"`
}

func (AICommandConfirmation) TableName() string { return "ai_command_confirmations" }
