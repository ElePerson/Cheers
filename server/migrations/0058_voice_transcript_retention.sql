-- Retention + audit for voice transcript segments (design §12).
--
-- Soft-delete: removing a final segment sets `deleted_at` instead of dropping
-- the row, so collaborating claim audit facts keep their sequence/id
-- attribution and can display "source content was deleted". The unique indexes
-- use a partial predicate so a soft-deleted row no longer blocks re-insert of
-- the same provider_event_id/channel_seq (defensive; ids are UUIDs).
--
-- Audit: every export / delete / policy_change / consent_withdrawn action
-- writes a row that never gets rewritten by later segment operations.

ALTER TABLE voice_transcript_segments
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Soft-deleted rows are excluded from the default (non-audited) reads.
CREATE INDEX IF NOT EXISTS ix_voice_transcript_not_deleted
    ON voice_transcript_segments(channel_id, channel_seq)
    WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS transcript_audit_events (
    id              BIGSERIAL PRIMARY KEY,
    channel_id      VARCHAR(36) NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    voice_session_id VARCHAR(36) REFERENCES voice_sessions(voice_session_id) ON DELETE SET NULL,
    segment_id      VARCHAR(36) REFERENCES voice_transcript_segments(segment_id) ON DELETE SET NULL,
    actor_user_id   VARCHAR(36) NOT NULL REFERENCES users(user_id),
    action          VARCHAR(24) NOT NULL CHECK (action IN ('export','delete','policy_change','consent_withdrawn')),
    details         JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_transcript_audit_action CHECK (action IN ('export','delete','policy_change','consent_withdrawn'))
);

CREATE INDEX IF NOT EXISTS ix_transcript_audit_channel_time
    ON transcript_audit_events(channel_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_transcript_audit_segment
    ON transcript_audit_events(segment_id) WHERE segment_id IS NOT NULL;
