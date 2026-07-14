//! Every frame the gateway sends to a connector over the Agent Bridge WS,
//! as named constructors in one place.
//!
//! These used to be inline `json!` blocks scattered across ws/agent_bridge.rs,
//! dispatcher.rs and the api/ handlers, which is how field-name drift crept in
//! (the connector sent `ready.connector_version`, the gateway read
//! `plugin_version`). Each constructor is pinned to a golden fixture under
//! `packages/cheers-acp-connector-rs/bridge-protocol/fixtures/` — the same
//! files the connector's serde tests parse — so both ends agree on the exact
//! bytes. Change a frame ⇒ the fixture test fails ⇒ regen with
//! `CHEERS_REGEN_FIXTURES=1 cargo test` and prove wire-safety in the PR.
//!
//! Wire-compat notes (do NOT "normalize" without a fleet version floor):
//! - `cancel` / `realize_file` / `workspace_req` / `pong` carry no `v` field.
//! - `hello` carries both `v` and `bridge_protocol_version` (same value), and
//!   `session_id` == `connection_id`.
//! - `config_update.settings` keys are camelCase — that IS the contract
//!   (`ConnectorControlSettings` on the connector side).
//! - the `task` frame intentionally duplicates `msg_id`==`trigger_msg_id` and
//!   repeats session identifiers in the nested `session{}` ref.

use serde_json::{json, Value};
use uuid::Uuid;

/// Agent Bridge protocol version stamped into (most) gateway frames and
/// validated against the connector's `auth` frame.
pub(crate) const BRIDGE_PROTOCOL_VERSION: u32 = 1;

/// Control-stream `hello` — the first frame after auth, carrying the bot's
/// identity, channel membership snapshot, persisted connector_control config
/// and the gateway's capability advertisement.
#[allow(clippy::too_many_arguments)]
pub(crate) fn control_hello_frame(
    bot_id: Uuid,
    bot_username: &str,
    bot_display_name: Option<&str>,
    connection_id: Uuid,
    memberships: Value,
    connector_config: Option<&Value>,
    server_capabilities: Value,
    acp_security: Option<&Value>,
) -> Value {
    let mut hello = json!({
        "type": "hello",
        "v": BRIDGE_PROTOCOL_VERSION,
        "bridge_protocol_version": BRIDGE_PROTOCOL_VERSION,
        "stream": "control",
        "bot_id": bot_id,
        "bot_username": bot_username,
        "bot_display_name": bot_display_name,
        "connection_id": connection_id,
        "session_id": connection_id,
        "memberships": memberships,
        "connector_config": connector_config,
        "server_capabilities": server_capabilities,
    });
    if let Some(acp_security) = acp_security {
        hello["acp_security"] = acp_security.clone();
    }
    hello
}

/// Data-stream `hello`. `last_event_seq` is fixed 0 until event-log replay
/// exists (resume is ack-only, see `resume_ack_frame`).
pub(crate) fn data_hello_frame(
    bot_id: Uuid,
    connection_id: Uuid,
    server_capabilities: Value,
    acp_security: Option<&Value>,
) -> Value {
    let mut hello = json!({
        "type": "hello",
        "v": BRIDGE_PROTOCOL_VERSION,
        "bridge_protocol_version": BRIDGE_PROTOCOL_VERSION,
        "stream": "data",
        "bot_id": bot_id,
        "connection_id": connection_id,
        "session_id": connection_id,
        "last_event_seq": 0,
        "server_capabilities": server_capabilities,
    });
    if let Some(acp_security) = acp_security {
        hello["acp_security"] = acp_security.clone();
    }
    hello
}

/// Bot-wide `config_update` push (owner posture / config-option overrides).
/// `settings` keys are camelCase by contract (`agentNativePermissionMode`,
/// `configOptions`); the connector re-clamps via its L0 policy.
pub(crate) fn config_update_frame(settings: Value) -> Value {
    json!({
        "type": "config_update",
        "v": BRIDGE_PROTOCOL_VERSION,
        "settings": settings,
    })
}

/// App-level heartbeat reply. Deliberately version-less (wire-compat).
pub(crate) fn pong_frame() -> Value {
    json!({ "type": "pong" })
}

/// Resume acknowledgement: no event-log replay exists, so `replayed` is always
/// 0 and the connector re-syncs via channel.activity.read.
pub(crate) fn resume_ack_frame(up_to_seq: i64) -> Value {
    json!({
        "type": "resume_ack",
        "v": BRIDGE_PROTOCOL_VERSION,
        "replayed": 0,
        "up_to_seq": up_to_seq,
    })
}

pub(crate) fn send_ack_ok(
    client_msg_id: &str,
    message_id: Uuid,
    finalized_placeholder: bool,
) -> Value {
    json!({
        "type": "send_ack",
        "v": BRIDGE_PROTOCOL_VERSION,
        "client_msg_id": client_msg_id,
        "ok": true,
        "message_id": message_id,
        "finalized_placeholder": finalized_placeholder,
    })
}

pub(crate) fn send_ack_err(client_msg_id: &str, code: &str, error: &str) -> Value {
    json!({
        "type": "send_ack",
        "v": BRIDGE_PROTOCOL_VERSION,
        "client_msg_id": client_msg_id,
        "ok": false,
        "code": code,
        "error": error,
    })
}

pub(crate) fn terminal_ack_ok(client_msg_id: &str, msg_id: Uuid) -> Value {
    json!({
        "type": "terminal_ack",
        "v": BRIDGE_PROTOCOL_VERSION,
        "client_msg_id": client_msg_id,
        "ok": true,
        "msg_id": msg_id,
    })
}

pub(crate) fn terminal_ack_err(client_msg_id: &str, code: &str, error: &str) -> Value {
    json!({
        "type": "terminal_ack",
        "v": BRIDGE_PROTOCOL_VERSION,
        "client_msg_id": client_msg_id,
        "ok": false,
        "code": code,
        "error": error,
    })
}

pub(crate) fn bridge_error(code: &str, detail: &str) -> Value {
    json!({
        "type": "error",
        "v": BRIDGE_PROTOCOL_VERSION,
        "code": code,
        "detail": detail,
    })
}

/// `resource_res` success reply, correlated by `req_id`.
pub(crate) fn resource_res_ok(req_id: &str, data: Value) -> Value {
    json!({
        "type": "resource_res",
        "v": BRIDGE_PROTOCOL_VERSION,
        "req_id": req_id,
        "ok": true,
        "data": data,
    })
}

/// `resource_res` failure reply.
pub(crate) fn resource_res_err(req_id: &str, code: &str, msg: &str) -> Value {
    json!({
        "type": "resource_res",
        "v": BRIDGE_PROTOCOL_VERSION,
        "req_id": req_id,
        "ok": false,
        "code": code,
        "error": msg,
    })
}

/// Interrupt an in-flight turn (⏹). Version-less by contract.
pub(crate) fn cancel_frame(placeholder_msg_id: Uuid, reason: &str) -> Value {
    json!({
        "type": "cancel",
        "msg_id": placeholder_msg_id,
        "reason": reason,
    })
}

/// Session-targeted ACP `session/set_mode` (value-gated by the connector's L0
/// allowed_modes envelope).
pub(crate) fn mode_set_frame(request_id: &str, provider_session_key: &str, mode: &str) -> Value {
    json!({
        "type": "mode_set",
        "v": BRIDGE_PROTOCOL_VERSION,
        "request_id": request_id,
        "provider_session_key": provider_session_key,
        "mode": mode,
    })
}

/// Session-targeted ACP `session/set_config_option`.
pub(crate) fn config_option_set_frame(
    request_id: &str,
    provider_session_key: &str,
    config_id: &str,
    value: &str,
) -> Value {
    json!({
        "type": "config_option_set",
        "v": BRIDGE_PROTOCOL_VERSION,
        "request_id": request_id,
        "provider_session_key": provider_session_key,
        "config_id": config_id,
        "value": value,
    })
}

/// Human decision on a forwarded `permission_request`, correlated by
/// `request_id`.
pub(crate) fn permission_resolution_frame(
    request_id: &str,
    message_id: &str,
    resolution: &str,
    option_id: &str,
    resolved_by: &str,
    resolved_at: &str,
) -> Value {
    json!({
        "type": "permission_resolution",
        "v": BRIDGE_PROTOCOL_VERSION,
        "request_id": request_id,
        "message_id": message_id,
        "resolution": resolution,
        "option_id": option_id,
        "resolved_by": resolved_by,
        "resolved_at": resolved_at,
    })
}

/// Ask the connector to upload a staged workspace file to S3. Version-less by
/// contract.
pub(crate) fn realize_file_frame(
    file_id: &str,
    remote_ref: &str,
    channel_id: &str,
    roots: &[String],
) -> Value {
    json!({
        "type": "realize_file",
        "file_id": file_id,
        "remote_ref": remote_ref,
        "channel_id": channel_id,
        "roots": roots,
    })
}

/// Workspace RPC request, correlated by `req_id`; replies arrive as
/// `workspace_res`. Version-less by contract. `extra` carries op-specific keys
/// (`content_b64`, `staged`, `limit`, `skip`, `commit`, `commit_path`,
/// `watch_id`) merged flat into the frame — Phase 2 replaces this splice with
/// a typed struct.
#[allow(clippy::too_many_arguments)]
pub(crate) fn workspace_req_frame(
    req_id: &str,
    op: &str,
    path: &str,
    root: Option<&str>,
    if_etag: Option<&str>,
    roots: &[String],
    extra: Value,
) -> Value {
    let mut frame = json!({
        "type": "workspace_req",
        "req_id": req_id,
        "op": op,
        "path": path,
        "root": root,
        "if_etag": if_etag,
        "roots": roots,
    });
    if let (Value::Object(dst), Value::Object(src)) = (&mut frame, extra) {
        for (k, v) in src {
            dst.insert(k, v);
        }
    }
    frame
}

// ── golden-fixture test infrastructure ────────────────────────────────────────

/// Shared by this module's tests and dispatcher.rs's task-frame test.
#[cfg(test)]
pub(crate) mod fixture {
    use serde_json::Value;
    use std::path::PathBuf;

    pub(crate) fn fixtures_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../packages/cheers-acp-connector-rs/bridge-protocol/fixtures")
    }

    /// Golden check: `frame` must equal the fixture at `rel` as a
    /// `serde_json::Value` (key order irrelevant). `volatile` keys (e.g. a
    /// now() timestamp) are stripped before comparing. Run with
    /// `CHEERS_REGEN_FIXTURES=1` to (re)write the fixture from the constructor
    /// instead of asserting — any regen diff needs a wire-safety proof in the PR.
    pub(crate) fn assert_matches_fixture(frame: &Value, rel: &str, volatile: &[&str]) {
        let mut frame = frame.clone();
        if let Value::Object(map) = &mut frame {
            for key in volatile {
                map.remove(*key);
            }
        }
        let path = fixtures_root().join(rel);
        if std::env::var_os("CHEERS_REGEN_FIXTURES").is_some() {
            std::fs::create_dir_all(path.parent().expect("fixture path has parent"))
                .expect("create fixtures dir");
            let pretty = serde_json::to_string_pretty(&frame).expect("serialize fixture");
            std::fs::write(&path, format!("{pretty}\n")).expect("write fixture");
            return;
        }
        let raw = std::fs::read_to_string(&path).unwrap_or_else(|e| {
            panic!(
                "missing fixture {} ({e}); generate with CHEERS_REGEN_FIXTURES=1 cargo test",
                path.display()
            )
        });
        let expected: Value = serde_json::from_str(&raw).expect("fixture is valid JSON");
        assert_eq!(
            frame, expected,
            "frame drifted from fixture {rel}; if intentional, prove wire-safety in the PR and regen"
        );
    }
}

#[cfg(test)]
mod tests {
    use super::fixture::assert_matches_fixture;
    use super::*;

    fn bot_id() -> Uuid {
        Uuid::parse_str("6f9619ff-8b86-4d01-b42d-00c04fc964ff").unwrap()
    }

    fn conn_id() -> Uuid {
        Uuid::parse_str("11111111-2222-4333-8444-555555555555").unwrap()
    }

    #[test]
    fn control_hello_matches_fixture() {
        let frame = control_hello_frame(
            bot_id(),
            "helper",
            Some("Helper"),
            conn_id(),
            json!([{
                "channel_id": "77777777-8888-4999-8aaa-bbbbbbbbbbbb",
                "channel_name": "general",
                "channel_type": "public",
                "workspace_id": "cccccccc-dddd-4eee-8fff-000000000000",
                "joined_at": "2026-06-01T10:15:30Z",
            }]),
            Some(&json!({"agentNativePermissionMode": "default"})),
            json!({
                "auth": ["authorization_bearer", "auth_frame"],
                "task_stream": "control",
                "runtime_session_control": true,
                "resource_req": true,
                "send_ack": true,
                "terminal_ack": true,
                "resume": "ack_only",
                "file_upload": false,
                "acp_security": true,
                "latest_connector_version": "0.1.27",
            }),
            None,
        );
        assert_matches_fixture(&frame, "control/to_connector/hello.json", &[]);
    }

    #[test]
    fn data_hello_matches_fixture() {
        let frame = data_hello_frame(
            bot_id(),
            conn_id(),
            json!({
                "auth": ["authorization_bearer", "auth_frame"],
                "task_stream": "control",
                "runtime_session_control": true,
                "resource_req": true,
                "send_ack": true,
                "terminal_ack": true,
                "resume": "ack_only",
                "file_upload": false,
                "acp_security": true,
                "latest_connector_version": "0.1.27",
            }),
            None,
        );
        assert_matches_fixture(&frame, "data/to_connector/hello.json", &[]);
    }

    #[test]
    fn config_update_matches_fixture() {
        let frame = config_update_frame(json!({"agentNativePermissionMode": "acceptEdits"}));
        assert_matches_fixture(&frame, "control/to_connector/config_update.json", &[]);
    }

    #[test]
    fn pong_matches_fixture() {
        assert_matches_fixture(&pong_frame(), "data/to_connector/pong.json", &[]);
    }

    #[test]
    fn resume_ack_matches_fixture() {
        assert_matches_fixture(
            &resume_ack_frame(42),
            "data/to_connector/resume_ack.json",
            &[],
        );
    }

    #[test]
    fn send_ack_ok_matches_fixture() {
        let frame = send_ack_ok("client-msg-1", bot_id(), true);
        assert_matches_fixture(&frame, "data/to_connector/send_ack_ok.json", &[]);
    }

    #[test]
    fn send_ack_err_matches_fixture() {
        let frame = send_ack_err("client-msg-1", "SEND_FAILED", "channel not writable");
        assert_matches_fixture(&frame, "data/to_connector/send_ack_err.json", &[]);
    }

    #[test]
    fn terminal_ack_ok_matches_fixture() {
        let frame = terminal_ack_ok("client-msg-2", bot_id());
        assert_matches_fixture(&frame, "data/to_connector/terminal_ack_ok.json", &[]);
    }

    #[test]
    fn terminal_ack_err_matches_fixture() {
        let frame = terminal_ack_err("client-msg-2", "TERMINAL_REJECTED", "not the owner of msg");
        assert_matches_fixture(&frame, "data/to_connector/terminal_ack_err.json", &[]);
    }

    #[test]
    fn bridge_error_matches_fixture() {
        let frame = bridge_error("CAPABILITY_DENIED", "signature verification failed");
        assert_matches_fixture(&frame, "data/to_connector/error.json", &[]);
    }

    #[test]
    fn resource_res_ok_matches_fixture() {
        let frame = resource_res_ok("req-1", json!({"messages": []}));
        assert_matches_fixture(&frame, "data/to_connector/resource_res_ok.json", &[]);
    }

    #[test]
    fn resource_res_err_matches_fixture() {
        let frame = resource_res_err("req-1", "E_FORBIDDEN", "SEE denied for this event");
        assert_matches_fixture(&frame, "data/to_connector/resource_res_err.json", &[]);
    }

    #[test]
    fn cancel_matches_fixture() {
        let frame = cancel_frame(conn_id(), "user_cancelled");
        assert_matches_fixture(&frame, "control/to_connector/cancel.json", &[]);
    }

    #[test]
    fn mode_set_matches_fixture() {
        let frame = mode_set_frame(
            "99999999-aaaa-4bbb-8ccc-dddddddddddd",
            "cheers:channel:77777777-8888-4999-8aaa-bbbbbbbbbbbb:bot:6f9619ff-8b86-4d01-b42d-00c04fc964ff",
            "acceptEdits",
        );
        assert_matches_fixture(&frame, "control/to_connector/mode_set.json", &[]);
    }

    #[test]
    fn config_option_set_matches_fixture() {
        let frame = config_option_set_frame(
            "99999999-aaaa-4bbb-8ccc-dddddddddddd",
            "cheers:channel:77777777-8888-4999-8aaa-bbbbbbbbbbbb:bot:6f9619ff-8b86-4d01-b42d-00c04fc964ff",
            "model",
            "claude-sonnet-5",
        );
        assert_matches_fixture(&frame, "control/to_connector/config_option_set.json", &[]);
    }

    #[test]
    fn permission_resolution_matches_fixture() {
        let frame = permission_resolution_frame(
            "99999999-aaaa-4bbb-8ccc-dddddddddddd",
            "eeeeeeee-ffff-4000-8111-222222222222",
            "allow",
            "allow_once",
            "33333333-4444-4555-8666-777777777777",
            "2026-06-01T10:15:30+00:00",
        );
        assert_matches_fixture(
            &frame,
            "control/to_connector/permission_resolution.json",
            &[],
        );
    }

    #[test]
    fn realize_file_matches_fixture() {
        let frame = realize_file_frame(
            "file-1",
            "/workspace/report.pdf",
            "77777777-8888-4999-8aaa-bbbbbbbbbbbb",
            &["/workspace".to_string()],
        );
        assert_matches_fixture(&frame, "data/to_connector/realize_file.json", &[]);
    }

    #[test]
    fn workspace_req_read_matches_fixture() {
        let frame = workspace_req_frame(
            "req-1",
            "read",
            "src/main.rs",
            Some("/workspace"),
            None,
            &["/workspace".to_string()],
            json!({}),
        );
        assert_matches_fixture(&frame, "data/to_connector/workspace_req_read.json", &[]);
    }

    #[test]
    fn workspace_req_write_matches_fixture() {
        let frame = workspace_req_frame(
            "req-2",
            "write",
            "notes.md",
            Some("/workspace"),
            Some("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            &["/workspace".to_string()],
            json!({"content_b64": "aGVsbG8="}),
        );
        assert_matches_fixture(&frame, "data/to_connector/workspace_req_write.json", &[]);
    }

    #[test]
    fn workspace_req_git_log_matches_fixture() {
        let frame = workspace_req_frame(
            "req-3",
            "git_log",
            "",
            Some("/workspace"),
            None,
            &[],
            json!({"limit": 20, "skip": 40}),
        );
        assert_matches_fixture(&frame, "data/to_connector/workspace_req_git_log.json", &[]);
    }

    #[test]
    fn workspace_req_watch_matches_fixture() {
        let frame = workspace_req_frame(
            "req-4",
            "watch",
            "",
            Some("/workspace"),
            None,
            &["/workspace".to_string()],
            json!({}),
        );
        assert_matches_fixture(&frame, "data/to_connector/workspace_req_watch.json", &[]);
    }
}
