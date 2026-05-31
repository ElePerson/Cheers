use axum::{
    extract::{Path, State, Extension, Query},
    Json,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::{
    api::middleware::Claims,
    app_state::AppState,
    domain::acp_capability,
    errors::AppError,
};

#[derive(Deserialize)]
pub struct CreateCapabilityDelegationRequest {
    pub scope_type: Option<String>,
    pub scope_id: Option<String>,
    pub session_id: Option<String>,
    pub allowed_actions: Vec<String>,
    pub allowed_resources: Vec<String>,
    pub max_uses: Option<i32>,
    pub expires_at: Option<DateTime<Utc>>,
    pub public_key: String,
    pub algorithm: Option<String>,
    pub delegated_to: Option<String>,
    pub note: Option<String>,
}

#[derive(Serialize)]
pub struct DelegationItem {
    pub delegation_id: String,
    pub bot_id: String,
    pub scope_type: String,
    pub scope_id: Option<String>,
    pub session_id: Option<String>,
    pub allowed_actions: Vec<String>,
    pub allowed_resources: Vec<String>,
    pub max_uses: Option<i64>,
    pub use_count: i64,
    pub expires_at: Option<DateTime<Utc>>,
    pub public_key: String,
    pub algorithm: String,
    pub delegated_to: Option<String>,
    pub status: String,
    pub revoked: bool,
    pub revoked_at: Option<DateTime<Utc>>,
    pub granted_by: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub note: Option<String>,
}

#[derive(Deserialize)]
pub struct DelegationListQuery {
    #[serde(default)]
    pub include_inactive: bool,
}

pub async fn list_delegations(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(bot_id): Path<Uuid>,
    Query(query): Query<DelegationListQuery>,
) -> Result<Json<Vec<DelegationItem>>, AppError> {
    let include_inactive = query.include_inactive;
    ensure_bot_owner_or_admin(&state.db, &bot_id, &claims).await?;

    let rows = if include_inactive {
        sqlx::query(
            "SELECT delegation_id, bot_id, scope_type, scope_id, session_id, allowed_actions,
                    allowed_resources, max_uses, use_count, expires_at, public_key,
                    algorithm, delegated_to, status, revoked, revoked_at, granted_by, created_at,
                    updated_at, note
             FROM acp_capability_delegations
             WHERE bot_id = $1
             ORDER BY created_at DESC",
        )
        .bind(bot_id.to_string())
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query(
            "SELECT delegation_id, bot_id, scope_type, scope_id, session_id, allowed_actions,
                    allowed_resources, max_uses, use_count, expires_at, public_key,
                    algorithm, delegated_to, status, revoked, revoked_at, granted_by, created_at,
                    updated_at, note
             FROM acp_capability_delegations
             WHERE bot_id = $1 AND status = 'active' AND revoked = FALSE
             ORDER BY created_at DESC",
        )
        .bind(bot_id.to_string())
        .fetch_all(&state.db)
        .await?
    };

    let mut items = Vec::with_capacity(rows.len());
    for row in rows {
        items.push(DelegationItem {
            delegation_id: row.try_get("delegation_id").unwrap_or_default(),
            bot_id: row.try_get("bot_id").unwrap_or_default(),
            scope_type: row.try_get("scope_type").unwrap_or_default(),
            scope_id: row.try_get("scope_id").ok(),
            session_id: row.try_get("session_id").ok(),
            allowed_actions: row.try_get("allowed_actions").unwrap_or_default(),
            allowed_resources: row.try_get("allowed_resources").unwrap_or_default(),
            max_uses: row
                .try_get::<Option<i32>, _>("max_uses")
                .ok()
                .flatten()
                .map(i64::from),
            use_count: row.try_get::<i32, _>("use_count").unwrap_or_default() as i64,
            expires_at: row.try_get("expires_at").ok(),
            public_key: row.try_get("public_key").unwrap_or_default(),
            algorithm: row.try_get("algorithm").unwrap_or_else(|_| acp_capability::CAPABILITY_SUPPORTED_ALGORITHM.to_string()),
            delegated_to: row.try_get("delegated_to").ok(),
            status: row.try_get("status").unwrap_or_else(|_| "active".into()),
            revoked: row.try_get("revoked").unwrap_or(false),
            revoked_at: row.try_get("revoked_at").ok(),
            granted_by: row.try_get("granted_by").unwrap_or_default(),
            created_at: row.try_get("created_at").unwrap_or_else(|_| Utc::now()),
            updated_at: row.try_get("updated_at").unwrap_or_else(|_| Utc::now()),
            note: row.try_get("note").ok(),
        });
    }

    Ok(Json(items))
}

pub async fn create_delegation(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path(bot_id): Path<Uuid>,
    Json(body): Json<CreateCapabilityDelegationRequest>,
) -> Result<Json<DelegationItem>, AppError> {
    ensure_bot_owner_or_admin(&state.db, &bot_id, &claims).await?;

    let scope_type = normalize_scope_type(body.scope_type.unwrap_or_else(|| acp_capability::CAPABILITY_SCOPE_CHANNEL.to_string()))?;
    let scope_id = trim_optional(body.scope_id);
    let session_id = trim_optional(body.session_id);
    let public_key = trim(body.public_key)?;
    let algorithm = body.algorithm.unwrap_or_else(|| acp_capability::CAPABILITY_SUPPORTED_ALGORITHM.to_string());
    let allowed_actions = normalize_strings(body.allowed_actions);
    let allowed_resources = normalize_strings(body.allowed_resources);

    if allowed_actions.is_empty() {
        return Err(AppError::BadRequest("allowed_actions cannot be empty".into()));
    }
    if allowed_resources.is_empty() {
        return Err(AppError::BadRequest("allowed_resources cannot be empty".into()));
    }

    if scope_type == acp_capability::CAPABILITY_SCOPE_SESSION && session_id.is_none() {
        return Err(AppError::BadRequest("session scope requires session_id".into()));
    }

    if scope_type != acp_capability::CAPABILITY_SCOPE_SESSION && session_id.is_some() {
        return Err(AppError::BadRequest("session_id is only valid for session scope".into()));
    }

    if matches!(
        scope_type.as_str(),
        acp_capability::CAPABILITY_SCOPE_CHANNEL
            | acp_capability::CAPABILITY_SCOPE_SESSION
            | acp_capability::CAPABILITY_SCOPE_USER
            | acp_capability::CAPABILITY_SCOPE_WORKSPACE
    ) && scope_id.is_none()
    {
        return Err(AppError::BadRequest(format!("scope_id required for scope_type={scope_type}")));
    }

    if scope_type == acp_capability::CAPABILITY_SCOPE_USER && body.delegated_to.as_deref().map(str::trim).filter(|v| !v.is_empty()).is_none() {
        return Err(AppError::BadRequest("delegated_to is required for user scope".into()));
    }

    if scope_type != acp_capability::CAPABILITY_SCOPE_USER && body.delegated_to.is_some() {
        return Err(AppError::BadRequest(
            "delegated_to can only be used with user scope".into(),
        ));
    }

    if let Some(max_uses) = body.max_uses {
        if max_uses <= 0 {
            return Err(AppError::BadRequest("max_uses must be positive".into()));
        }
    }

    if let Some(expires_at) = body.expires_at {
        if expires_at < Utc::now() {
            return Err(AppError::BadRequest("expires_at must be in the future".into()));
        }
    }

    acp_capability::validate_public_key(&algorithm, &public_key)
        .map_err(|err| AppError::BadRequest(err.to_string()))?;

    let delegation_id = Uuid::new_v4();
    let row = sqlx::query(
        "INSERT INTO acp_capability_delegations (
            delegation_id, bot_id, scope_type, scope_id, session_id,
            allowed_actions, allowed_resources, max_uses, use_count, expires_at,
            public_key, algorithm, delegated_to, status, revoked, revoked_at,
            granted_by, note, created_at, updated_at
         ) VALUES (
            $1, $2, $3, $4, $5,
            $6, $7, $8, 0, $9,
            $10, $11, $12, 'active', FALSE, NULL,
            $13, $14, NOW(), NOW()
         ) RETURNING delegation_id, bot_id, scope_type, scope_id, session_id, allowed_actions,
                   allowed_resources, max_uses, use_count, expires_at, public_key,
                   algorithm, delegated_to, status, revoked, revoked_at, granted_by, created_at,
                   updated_at, note",
    )
    .bind(delegation_id.to_string())
    .bind(bot_id.to_string())
    .bind(scope_type)
    .bind(scope_id)
    .bind(session_id)
    .bind(&allowed_actions)
    .bind(&allowed_resources)
    .bind(body.max_uses)
    .bind(body.expires_at)
    .bind(public_key)
    .bind(algorithm)
    .bind(body.delegated_to)
    .bind(&claims.sub)
    .bind(body.note)
    .fetch_one(&state.db)
    .await?;

    Ok(Json(DelegationItem {
        delegation_id: row.try_get("delegation_id").unwrap_or_default(),
        bot_id: row.try_get("bot_id").unwrap_or_default(),
        scope_type: row.try_get("scope_type").unwrap_or_default(),
        scope_id: row.try_get("scope_id").ok(),
        session_id: row.try_get("session_id").ok(),
        allowed_actions: row.try_get("allowed_actions").unwrap_or_default(),
        allowed_resources: row.try_get("allowed_resources").unwrap_or_default(),
            max_uses: row
                .try_get::<Option<i32>, _>("max_uses")
                .ok()
                .flatten()
                .map(i64::from),
        use_count: row.try_get::<i32, _>("use_count").unwrap_or_default() as i64,
        expires_at: row.try_get("expires_at").ok(),
        public_key: row.try_get("public_key").unwrap_or_default(),
        algorithm: row.try_get("algorithm").unwrap_or_else(|_| acp_capability::CAPABILITY_SUPPORTED_ALGORITHM.to_string()),
        delegated_to: row.try_get("delegated_to").ok(),
        status: row.try_get("status").unwrap_or_else(|_| "active".into()),
        revoked: row.try_get("revoked").unwrap_or(false),
        revoked_at: row.try_get("revoked_at").ok(),
        granted_by: row.try_get("granted_by").unwrap_or_default(),
        created_at: row.try_get("created_at").unwrap_or_else(|_| Utc::now()),
        updated_at: row.try_get("updated_at").unwrap_or_else(|_| Utc::now()),
        note: row.try_get("note").ok(),
    }))
}

pub async fn revoke_delegation(
    State(state): State<AppState>,
    Extension(claims): Extension<Claims>,
    Path((bot_id, delegation_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<serde_json::Value>, AppError> {
    ensure_bot_owner_or_admin(&state.db, &bot_id, &claims).await?;

    let row = sqlx::query(
        "UPDATE acp_capability_delegations
         SET status = 'revoked', revoked = TRUE, revoked_at = NOW(), updated_at = NOW()
         WHERE bot_id = $1 AND delegation_id = $2
         RETURNING delegation_id",
    )
    .bind(bot_id.to_string())
    .bind(delegation_id.to_string())
    .fetch_optional(&state.db)
    .await?;

    if row.is_none() {
        return Err(AppError::NotFound);
    }

    Ok(Json(json!({
        "ok": true,
        "delegation_id": delegation_id.to_string(),
    })))
}

fn normalize_scope_type(raw: String) -> Result<String, AppError> {
    match raw.trim().to_lowercase().as_str() {
        acp_capability::CAPABILITY_SCOPE_GLOBAL
        | acp_capability::CAPABILITY_SCOPE_WORKSPACE
        | acp_capability::CAPABILITY_SCOPE_CHANNEL
        | acp_capability::CAPABILITY_SCOPE_SESSION
        | acp_capability::CAPABILITY_SCOPE_USER => Ok(raw.trim().to_lowercase()),
        _ => Err(AppError::BadRequest(
            "scope_type must be one of global|workspace|channel|session|user".into(),
        )),
    }
}

fn normalize_strings(values: Vec<String>) -> Vec<String> {
    values
        .into_iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect()
}

fn trim(raw: String) -> Result<String, AppError> {
    let value = raw.trim().to_string();
    if value.is_empty() {
        return Err(AppError::BadRequest("public_key cannot be empty".into()));
    }
    Ok(value)
}

fn trim_optional(value: Option<String>) -> Option<String> {
    value
        .map(|raw| raw.trim().to_string())
        .filter(|value| !value.is_empty())
}

async fn ensure_bot_owner_or_admin(
    db: &PgPool,
    bot_id: &Uuid,
    claims: &Claims,
) -> Result<(), AppError> {
    let row = sqlx::query("SELECT created_by FROM bot_accounts WHERE bot_id = $1")
        .bind(bot_id.to_string())
        .fetch_optional(db)
        .await?
        .ok_or(AppError::NotFound)?;

    if matches!(claims.role.as_str(), "admin" | "system_admin") {
        return Ok(());
    }

    let created_by = row.try_get::<Option<String>, _>("created_by").ok().flatten();
    if created_by.as_deref() == Some(claims.sub.as_str()) {
        return Ok(());
    }

    Err(AppError::Forbidden("only bot owner or admin can manage capability delegations".into()))
}
