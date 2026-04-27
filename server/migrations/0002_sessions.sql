CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  device_id TEXT,
  refresh_token_id TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  last_used_at TEXT NOT NULL,
  revoked_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_updated ON sessions (user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_device ON sessions (device_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_refresh_token_id ON sessions (refresh_token_id);
