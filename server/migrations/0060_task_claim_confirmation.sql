ALTER TABLE task_claim_requests
  ADD COLUMN IF NOT EXISTS requester_id VARCHAR(36),
  ADD COLUMN IF NOT EXISTS source_message_id VARCHAR(36),
  ADD COLUMN IF NOT EXISTS confirmation_message_id VARCHAR(36);

ALTER TABLE task_claim_requests DROP CONSTRAINT IF EXISTS chk_task_claim_status;
ALTER TABLE task_claim_requests ADD CONSTRAINT chk_task_claim_status
  CHECK (status IN ('pending','awaiting_requester_confirmation','accepted','rejected','cancelled','executing','completed','failed'));

CREATE INDEX IF NOT EXISTS ix_task_claim_requests_requester
  ON task_claim_requests(channel_id, requester_id, status, created_at DESC);
