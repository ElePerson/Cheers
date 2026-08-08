use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

use super::{resource_error, Principal, PrincipalType, ResourceResult};

/// Bot-authenticated DM creation.  Eligibility is deliberately narrow: owner
/// or a human who currently shares a non-DM channel with the bot.
pub async fn handle_open(db: &PgPool, principal: &Principal, params: &Value) -> ResourceResult {
    if principal.principal_type != PrincipalType::Bot {
        return Err(resource_error("FORBIDDEN", "dm.open is bot-only"));
    }
    let target_user_id = params
        .get("target_user_id")
        .and_then(Value::as_str)
        .and_then(|value| Uuid::parse_str(value).ok())
        .ok_or_else(|| resource_error("INVALID_PARAMS", "target_user_id must be a uuid"))?;
    let eligible: bool = sqlx::query_scalar(
        "SELECT EXISTS(
            SELECT 1 FROM users u
            JOIN bot_accounts b ON b.bot_id = $1
            WHERE u.user_id = $2 AND u.is_deleted = FALSE AND b.is_disabled = FALSE
              AND (
                  b.created_by = u.user_id
                  OR EXISTS (
                      SELECT 1 FROM channel_memberships bm
                      JOIN channel_memberships um ON um.channel_id = bm.channel_id
                      JOIN channels c ON c.channel_id = bm.channel_id
                      WHERE bm.member_id = b.bot_id AND bm.member_type = 'bot'
                        AND um.member_id = u.user_id AND um.member_type = 'user'
                        AND c.type <> 'dm' AND c.archived_at IS NULL
                  )
              )
         )",
    )
    .bind(principal.principal_id.to_string())
    .bind(target_user_id.to_string())
    .fetch_one(db)
    .await
    .map_err(super::db_err("dm.open eligibility"))?;
    if !eligible {
        return Err(resource_error(
            "FORBIDDEN",
            "bot may DM only its owner or a user from a shared channel",
        ));
    }
    let opened = crate::domain::dms::open_dm(
        db,
        crate::domain::dms::Participant::Bot(principal.principal_id),
        crate::domain::dms::Participant::User(target_user_id),
    )
    .await
    .map_err(|error| resource_error("DM_OPEN_FAILED", error.to_string()))?;
    Ok(json!({
        "channel_id": opened.channel_id,
        "target_user_id": target_user_id,
        "created": opened.created,
    }))
}
