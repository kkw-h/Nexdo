CREATE TABLE IF NOT EXISTS ai_command_confirmations (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  token_id TEXT NOT NULL,
  intent TEXT NOT NULL,
  operation_type TEXT NOT NULL,
  action TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_ids_json TEXT NOT NULL,
  patch_json TEXT NOT NULL,
  plan_json TEXT NOT NULL,
  proposal_hash TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_command_confirmations_token_id
ON ai_command_confirmations (token_id);

CREATE INDEX IF NOT EXISTS idx_ai_command_confirmations_user_updated
ON ai_command_confirmations (user_id, updated_at DESC);
