//! Admin-only security settings endpoints.
//!
//! Controls instance-level security policy such as whether remote agent access
//! requires two-factor authentication.

use axum::{extract::State, Extension, Json};
use serde::Deserialize;
use serde_json::Value;

use crate::{
    api::middleware::Claims, app_state::AppState, domain::security_settings, errors::AppError,
};

fn is_admin(claims: &Claims) -> bool {
    matches!(claims.role.as_str(), "system_admin" | "admin")
}

fn settings_dto(settings: &security_settings::SecuritySettings) -> Value {
    serde_json::json!({
        "require_2fa_for_remote_agent_access": settings.require_2fa_for_remote_agent_access,
    })
}

/// GET /api/v1/admin/settings/security
pub async fn get_settings(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
) -> Result<Json<Value>, AppError> {
    if !is_admin(&claims) {
        return Err(AppError::Forbidden("admin only".into()));
    }
    let settings = security_settings::load(&state.db).await?;
    Ok(Json(settings_dto(&settings)))
}

#[derive(Deserialize)]
pub struct PutSettingsRequest {
    pub require_2fa_for_remote_agent_access: bool,
}

/// PUT /api/v1/admin/settings/security
pub async fn put_settings(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Json(req): Json<PutSettingsRequest>,
) -> Result<Json<Value>, AppError> {
    if !is_admin(&claims) {
        return Err(AppError::Forbidden("admin only".into()));
    }
    let settings = security_settings::SecuritySettings {
        require_2fa_for_remote_agent_access: req.require_2fa_for_remote_agent_access,
    };
    security_settings::save(&state.db, &settings).await?;
    Ok(Json(settings_dto(&settings)))
}
