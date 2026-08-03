CREATE TABLE IF NOT EXISTS channel_notification_preferences (
    user_id VARCHAR(36) NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    channel_id VARCHAR(36) NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    muted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, channel_id)
);
