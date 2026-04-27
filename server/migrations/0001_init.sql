CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  nickname TEXT NOT NULL DEFAULT '',
  avatar_url TEXT NOT NULL DEFAULT '',
  timezone TEXT NOT NULL DEFAULT 'UTC',
  locale TEXT NOT NULL DEFAULT 'en-US',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  device_id TEXT NOT NULL UNIQUE,
  device_name TEXT NOT NULL DEFAULT '',
  platform TEXT NOT NULL DEFAULT '',
  user_agent TEXT NOT NULL DEFAULT '',
  last_seen_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_devices_user_updated ON devices (user_id, updated_at);

CREATE TABLE IF NOT EXISTS lists (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  color_value INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_lists_user_sort ON lists (user_id, sort_order, created_at);
CREATE INDEX IF NOT EXISTS idx_lists_user_updated ON lists (user_id, updated_at);

CREATE TABLE IF NOT EXISTS groups (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  icon_code_point INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_groups_user_sort ON groups (user_id, sort_order, created_at);
CREATE INDEX IF NOT EXISTS idx_groups_user_updated ON groups (user_id, updated_at);

CREATE TABLE IF NOT EXISTS tags (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  color_value INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_tags_user_created ON tags (user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_tags_user_updated ON tags (user_id, updated_at);

CREATE TABLE IF NOT EXISTS reminders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  title TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  due_at TEXT NOT NULL,
  is_completed BOOLEAN NOT NULL DEFAULT FALSE,
  list_id TEXT NOT NULL,
  group_id TEXT NOT NULL,
  notification_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  repeat_rule TEXT NOT NULL DEFAULT 'none',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (list_id) REFERENCES lists(id),
  FOREIGN KEY (group_id) REFERENCES groups(id)
);

CREATE INDEX IF NOT EXISTS idx_reminders_user_due ON reminders (user_id, is_completed, due_at);
CREATE INDEX IF NOT EXISTS idx_reminders_user_updated ON reminders (user_id, updated_at);

CREATE TABLE IF NOT EXISTS reminder_tags (
  reminder_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  PRIMARY KEY (reminder_id, tag_id),
  FOREIGN KEY (reminder_id) REFERENCES reminders(id),
  FOREIGN KEY (tag_id) REFERENCES tags(id)
);

CREATE INDEX IF NOT EXISTS idx_reminder_tags_tag ON reminder_tags (tag_id);

CREATE TABLE IF NOT EXISTS reminder_completion_logs (
  id TEXT PRIMARY KEY,
  reminder_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  completed_at TEXT NOT NULL,
  original_due_at TEXT NOT NULL,
  next_due_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (reminder_id) REFERENCES reminders(id),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_reminder_completion_logs_reminder_completed
  ON reminder_completion_logs (reminder_id, completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_reminder_completion_logs_user_created
  ON reminder_completion_logs (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS quick_notes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  content TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft',
  converted_reminder_id TEXT,
  audio_key TEXT,
  audio_filename TEXT,
  audio_mime_type TEXT,
  audio_size_bytes INTEGER,
  audio_duration_ms INTEGER,
  waveform_samples TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (converted_reminder_id) REFERENCES reminders(id)
);

CREATE INDEX IF NOT EXISTS idx_quick_notes_user_created ON quick_notes (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_quick_notes_user_updated ON quick_notes (user_id, updated_at);
