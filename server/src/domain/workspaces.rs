//! Workspace helpers. A workspace is either a shared `team` space or a per-user
//! `personal` space (the user's private area + the FK anchor for DMs they start).
//! See docs/arch/CONVERSATION_MODEL.md.

use uuid::Uuid;

use crate::errors::AppError;
use sqlx::PgPool;

/// The user's personal workspace, creating it on first use (lazy provision — there is no
/// signup hook, and this also covers users that predate the personal-workspace concept).
/// Idempotent + race-safe via the `uq_workspaces_personal_owner` partial unique index.
pub async fn get_or_create_personal_workspace(
    db: &PgPool,
    user_id: Uuid,
) -> Result<Uuid, AppError> {
    let uid = user_id.to_string();

    if let Some(existing) = sqlx::query_scalar::<_, String>(
        "SELECT workspace_id FROM workspaces WHERE owner_user_id = $1 AND kind = 'personal' LIMIT 1",
    )
    .bind(&uid)
    .fetch_optional(db)
    .await
    .map_err(AppError::Db)?
    {
        return parse_ws(existing);
    }

    // Create; on a concurrent winner, DO NOTHING returns no row → re-select the winner.
    let inserted = sqlx::query_scalar::<_, String>(
        "INSERT INTO workspaces (workspace_id, name, kind, owner_user_id)
         VALUES ($1, 'Personal', 'personal', $2)
         ON CONFLICT (owner_user_id) WHERE kind = 'personal' DO NOTHING
         RETURNING workspace_id",
    )
    .bind(Uuid::new_v4().to_string())
    .bind(&uid)
    .fetch_optional(db)
    .await
    .map_err(AppError::Db)?;

    if let Some(id) = inserted {
        return parse_ws(id);
    }

    let existing = sqlx::query_scalar::<_, String>(
        "SELECT workspace_id FROM workspaces WHERE owner_user_id = $1 AND kind = 'personal' LIMIT 1",
    )
    .bind(&uid)
    .fetch_one(db)
    .await
    .map_err(AppError::Db)?;
    parse_ws(existing)
}

/// Decline a still-pending workspace invitation and consume any channel
/// invitations queued behind it. Keeping both deletes in one transaction makes
/// a stale decline harmless when another device has already accepted the
/// workspace invitation.
pub async fn decline_pending_invite(
    db: &PgPool,
    workspace_id: &str,
    user_id: &str,
) -> Result<Vec<String>, AppError> {
    let mut tx = db.begin().await.map_err(AppError::Db)?;
    let deleted = sqlx::query(
        "DELETE FROM workspace_memberships
         WHERE workspace_id = $1 AND user_id = $2 AND status = 'pending'",
    )
    .bind(workspace_id)
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(AppError::Db)?
    .rows_affected();
    if deleted == 0 {
        return Err(AppError::NotFound);
    }

    let channel_ids: Vec<String> = sqlx::query_scalar(
        "SELECT ci.channel_id
         FROM channel_invites ci
         JOIN channels c ON c.channel_id = ci.channel_id
         WHERE ci.user_id = $1 AND c.workspace_id = $2",
    )
    .bind(user_id)
    .bind(workspace_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(AppError::Db)?;
    sqlx::query(
        "DELETE FROM channel_invites
         WHERE user_id = $1
           AND channel_id IN (SELECT channel_id FROM channels WHERE workspace_id = $2)",
    )
    .bind(user_id)
    .bind(workspace_id)
    .execute(&mut *tx)
    .await
    .map_err(AppError::Db)?;
    tx.commit().await.map_err(AppError::Db)?;

    Ok(channel_ids)
}

fn parse_ws(s: String) -> Result<Uuid, AppError> {
    Uuid::parse_str(&s).map_err(|_| AppError::Internal("invalid workspace_id".into()))
}
