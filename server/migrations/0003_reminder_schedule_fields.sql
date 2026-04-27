ALTER TABLE reminders ADD COLUMN repeat_until_at TEXT;
ALTER TABLE reminders ADD COLUMN remind_before_minutes INTEGER NOT NULL DEFAULT 0;
