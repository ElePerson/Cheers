//! Per-channel session management (docs/arch/SESSION_MODEL.md): a channel has one
//! PRIMARY (default) session per bot plus any number of "other" sessions, each
//! addressed by its `session_id` — topic-free. Channel members may list a bot's
//! sessions and start a new "other" one.

use axum::{
    extract::{Path, State},
    Extension, Json,
};
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::{api::middleware::Claims, app_state::AppState, domain::sessions, errors::AppError};

/// Channel-member gate (platform admins bypass), mirroring messages.rs.
async fn ensure_channel_member(state: &AppState, channel_id: Uuid, claims: &Claims) -> Result<Uuid, AppError> {
    let user_id: Uuid = claims
        .sub
        .parse()
        .map_err(|_| AppError::Unauthorized("invalid user_id".into()))?;
    if matches!(claims.role.as_str(), "system_admin" | "admin") {
        return Ok(user_id);
    }
    let ok = sqlx::query(
        "SELECT EXISTS(
            SELECT 1 FROM channel_memberships
            WHERE channel_id = $1 AND member_id = $2 AND member_type = 'user'
        ) AS ok",
    )
    .bind(channel_id.to_string())
    .bind(user_id.to_string())
    .fetch_one(&state.db)
    .await?
    .try_get::<bool, _>("ok")
    .unwrap_or(false);
    if ok {
        Ok(user_id)
    } else {
        Err(AppError::Forbidden("not a channel member".into()))
    }
}

// ── GET /api/v1/channels/:channel_id/bots/:bot_id/sessions ───────────────────

pub async fn list_sessions(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path((channel_id, bot_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<Value>, AppError> {
    ensure_channel_member(&state, channel_id, &claims).await?;
    let sessions = sessions::list_channel_sessions(&state.db, bot_id, &channel_id.to_string()).await?;
    Ok(Json(json!({ "sessions": sessions })))
}

// ── POST /api/v1/channels/:channel_id/bots/:bot_id/sessions ──────────────────

pub async fn create_session(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path((channel_id, bot_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<Value>, AppError> {
    ensure_channel_member(&state, channel_id, &claims).await?;
    let provider_account_id = crate::domain::messages::resolve_provider_account_id_for_bot(&state.db, bot_id)
        .await
        .unwrap_or_else(|_| bot_id.to_string());
    let handle = sessions::create_channel_session(
        &state.db,
        bot_id,
        &provider_account_id,
        &channel_id.to_string(),
        "other",
    )
    .await?;
    Ok(Json(json!({
        "session_id": handle.session_id.to_string(),
        "provider_session_key": handle.provider_session_key,
        "role": "other",
    })))
}
