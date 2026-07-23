//! Instance-level security settings (admin-configured, stored in
//! `system_settings` under key `security`).
//!
//! Currently governs whether remote agent access (bot creation and bot session
//! creation) requires the user to have enabled TOTP two-factor authentication.

use serde_json::{json, Value};
use sqlx::PgPool;

use crate::errors::AppError;

const SETTINGS_KEY: &str = "security";

#[derive(Debug, Clone)]
pub struct SecuritySettings {
    pub require_2fa_for_remote_agent_access: bool,
}

/// Load the security settings. Returns defaults when never configured.
pub async fn load(db: &PgPool) -> Result<SecuritySettings, AppError> {
    let value = sqlx::query_scalar::<_, Value>("SELECT value FROM system_settings WHERE key = $1")
        .bind(SETTINGS_KEY)
        .fetch_optional(db)
        .await?;

    Ok(SecuritySettings {
        require_2fa_for_remote_agent_access: value
            .and_then(|v| {
                v.get("require_2fa_for_remote_agent_access")
                    .and_then(Value::as_bool)
            })
            .unwrap_or(true),
    })
}

/// Persist the settings (upsert).
pub async fn save(db: &PgPool, settings: &SecuritySettings) -> Result<(), AppError> {
    let value = json!({
        "require_2fa_for_remote_agent_access": settings.require_2fa_for_remote_agent_access,
    });

    sqlx::query(
        "INSERT INTO system_settings (key, value) VALUES ($1, $2)
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value",
    )
    .bind(SETTINGS_KEY)
    .bind(&value)
    .execute(db)
    .await?;

    Ok(())
}

/// Convenience helper used by the remote-agent access gate.
pub async fn require_2fa_for_remote_agent_access(db: &PgPool) -> Result<bool, AppError> {
    let settings = load(db).await?;
    Ok(settings.require_2fa_for_remote_agent_access)
}
