#![allow(dead_code)]

use std::time::Duration;

use anyhow::{anyhow, Context};
use futures_util::{SinkExt, StreamExt};
use rand::Rng;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::net::TcpStream;
use tokio_tungstenite::{
    connect_async,
    tungstenite::{client::IntoClientRequest, protocol::Message},
    MaybeTlsStream, WebSocketStream,
};

pub const BRIDGE_PROTOCOL_VERSION: u32 = 1;
pub const WS_CLOSE_AUTH_FAIL: u16 = 4401;
pub const WS_CLOSE_SUPERSEDED: u16 = 4402;
pub const WS_CLOSE_BOT_UNAVAILABLE: u16 = 4403;

pub fn is_fatal_close_code(code: u16) -> bool {
    matches!(
        code,
        WS_CLOSE_AUTH_FAIL | WS_CLOSE_SUPERSEDED | WS_CLOSE_BOT_UNAVAILABLE
    )
}

fn default_bridge_protocol_version() -> u32 {
    BRIDGE_PROTOCOL_VERSION
}

fn default_auth_frame_type() -> String {
    "auth".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectorInfo {
    pub name: String,
    pub version: String,
}

impl Default for ConnectorInfo {
    fn default() -> Self {
        Self {
            name: "cce-acp-connector".to_string(),
            version: env!("CARGO_PKG_VERSION").to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// 退避：指数增长但封顶 max_ms，再乘 [0.5, 1.0] 的 jitter。
    /// jitter 随机，故对每个 attempt 多取样验证结果恒落在 [0.5×cap, cap]。
    #[test]
    fn backoff_stays_within_jittered_cap() {
        let opts = ReconnectOptions {
            base_ms: 1_000,
            max_ms: 30_000,
            reset_after_ms: 30_000,
        };
        for attempt in 1..=10u32 {
            let uncapped = 1_000u64.saturating_mul(2u64.saturating_pow(attempt - 1));
            let cap = uncapped.min(opts.max_ms);
            let lower = (cap as f64 * 0.5).round() as u64;
            for _ in 0..64 {
                let ms = compute_backoff(attempt, opts).as_millis() as u64;
                assert!(
                    ms >= lower && ms <= cap,
                    "attempt {attempt}: {ms}ms 不在 [{lower}, {cap}]"
                );
            }
        }
    }

    /// 大 attempt 不溢出，稳定封顶在 max_ms（含 jitter 下界）。
    #[test]
    fn backoff_caps_at_max() {
        let opts = ReconnectOptions::default();
        let lower = (opts.max_ms as f64 * 0.5).round() as u64;
        for _ in 0..64 {
            let ms = compute_backoff(32, opts).as_millis() as u64;
            assert!(ms >= lower && ms <= opts.max_ms, "{ms}ms 超出封顶");
        }
    }

    #[test]
    fn control_task_deserializes_from_agent_bridge_v1_shape() {
        let frame: ControlInbound = serde_json::from_value(json!({
            "type": "task",
            "v": 1,
            "task_id": "task-1",
            "channel_id": "channel-1",
            "trigger_msg_id": "message-1",
            "msg_id": "message-1",
            "trigger_seq": 42,
            "depth": 0,
            "trigger": "user_message",
            "placeholder_msg_id": "placeholder-1",
            "provider_session_key": "cheers:workspace:w1:bot:b1",
            "session_id": "session-1",
            "session_policy": {
                "on_missing": "create",
                "on_paused": "resume",
                "after_task": "keep_active"
            },
            "trigger_message": {
                "msg_id": "message-1",
                "user": "user-1",
                "text": "@helper summarize this"
            },
            "attachments": [
                {
                    "file_id": "file-1",
                    "filename": "report.pdf",
                    "content_type": "application/pdf",
                    "size_bytes": 12345,
                    "is_image": false
                }
            ],
            "session": {
                "id": "session-1",
                "provider_session_key": "cheers:workspace:w1:bot:b1",
                "task_scope_id": "task-1"
            },
            "enqueued_at": "2026-06-01T10:15:30Z"
        }))
        .expect("task frame should deserialize");

        match frame {
            ControlInbound::Task {
                task_id,
                placeholder_msg_id,
                provider_session_key,
                session_policy,
                attachments,
                ..
            } => {
                assert_eq!(task_id, "task-1");
                assert_eq!(placeholder_msg_id, "placeholder-1");
                assert_eq!(provider_session_key, "cheers:workspace:w1:bot:b1");
                assert_eq!(
                    session_policy.expect("session_policy").after_task,
                    "keep_active"
                );
                assert_eq!(attachments.len(), 1);
            }
            other => panic!("unexpected frame: {other:?}"),
        }
    }

    #[test]
    fn control_task_carries_session_cwd_and_additional_dirs() {
        let frame: ControlInbound = serde_json::from_value(json!({
            "type": "task",
            "task_id": "task-1",
            "channel_id": "channel-1",
            "trigger_msg_id": "message-1",
            "placeholder_msg_id": "placeholder-1",
            "provider_session_key": "cheers:channel:c1:bot:b1",
            "cwd": "/repo/service",
            "additional_dirs": ["/repo/shared-lib", "/repo/docs"]
        }))
        .expect("task frame with cwd should deserialize");

        match frame {
            ControlInbound::Task {
                cwd,
                additional_dirs,
                ..
            } => {
                assert_eq!(cwd.as_deref(), Some("/repo/service"));
                assert_eq!(additional_dirs, vec!["/repo/shared-lib", "/repo/docs"]);
            }
            other => panic!("unexpected frame: {other:?}"),
        }
    }

    #[test]
    fn control_task_defaults_session_cwd_when_absent() {
        // Backward compatible: an older Backend that never sends cwd/additional_dirs
        // still deserializes, with the connector falling back to its default_cwd.
        let frame: ControlInbound = serde_json::from_value(json!({
            "type": "task",
            "task_id": "task-1",
            "channel_id": "channel-1",
            "trigger_msg_id": "message-1",
            "placeholder_msg_id": "placeholder-1",
            "provider_session_key": "cheers:channel:c1:bot:b1"
        }))
        .expect("task frame without cwd should deserialize");

        match frame {
            ControlInbound::Task {
                cwd,
                additional_dirs,
                ..
            } => {
                assert!(cwd.is_none());
                assert!(additional_dirs.is_empty());
            }
            other => panic!("unexpected frame: {other:?}"),
        }
    }

    #[test]
    fn runtime_session_control_deserializes() {
        let frame: ControlInbound = serde_json::from_value(json!({
            "type": "runtime_session_control",
            "v": 1,
            "request_id": "req-1",
            "action": "create",
            "session": {
                "id": "session-1",
                "provider_session_key": "provider-key",
                "primary_scope_type": "workspace",
                "primary_scope_id": "workspace-1"
            },
            "runtime": {
                "protocol": "acp",
                "provider_session_id": null,
                "config": {
                    "cwd": "/repo",
                    "model": "gpt-5"
                }
            },
            "reason": "user_opened_channel",
            "deadline_ms": 30000
        }))
        .expect("runtime_session_control should deserialize");

        match frame {
            ControlInbound::RuntimeSessionControl {
                request_id,
                action,
                session,
                runtime,
                deadline_ms,
                ..
            } => {
                assert_eq!(request_id, "req-1");
                assert_eq!(action, "create");
                assert_eq!(session.provider_session_key, "provider-key");
                assert_eq!(runtime.protocol, "acp");
                assert_eq!(deadline_ms, Some(30000));
            }
            other => panic!("unexpected frame: {other:?}"),
        }
    }

    #[test]
    fn data_done_serializes_with_v1_terminal_shape() {
        let frame = DataOutbound::Done {
            v: BRIDGE_PROTOCOL_VERSION,
            client_msg_id: "client-1".to_string(),
            msg_id: "placeholder-1".to_string(),
            file_ids: vec!["file-1".to_string()],
            mention_ids: vec!["user-1".to_string()],
            content: Some("final answer".to_string()),
            provider_session_key: Some("provider-key".to_string()),
            provider_session_id: Some("acp-session-1".to_string()),
            session_id: Some("session-1".to_string()),
            acp_capability: None,
        };
        let value = serde_json::to_value(frame).expect("done should serialize");
        assert_eq!(value["type"], "done");
        assert_eq!(value["v"], 1);
        assert_eq!(value["client_msg_id"], "client-1");
        assert_eq!(value["msg_id"], "placeholder-1");
        assert_eq!(value["mention_ids"][0], "user-1");
    }

    #[test]
    fn data_terminal_ack_deserializes() {
        let frame: DataInbound = serde_json::from_value(json!({
            "type": "terminal_ack",
            "v": 1,
            "client_msg_id": "client-1",
            "ok": true,
            "msg_id": "placeholder-1"
        }))
        .expect("terminal ack should deserialize");

        match frame {
            DataInbound::TerminalAck {
                client_msg_id,
                ok,
                msg_id,
                ..
            } => {
                assert_eq!(client_msg_id, "client-1");
                assert!(ok);
                assert_eq!(msg_id.as_deref(), Some("placeholder-1"));
            }
            other => panic!("unexpected frame: {other:?}"),
        }
    }

    #[test]
    fn resource_response_deserializes_by_req_id() {
        let frame: DataInbound = serde_json::from_value(json!({
            "type": "resource_res",
            "v": 1,
            "req_id": "r1",
            "ok": true,
            "data": {
                "channel_id": "channel-1"
            }
        }))
        .expect("resource response should deserialize");

        match frame {
            DataInbound::ResourceRes { response } => {
                assert_eq!(response.req_id, "r1");
                assert!(response.ok);
                assert_eq!(response.data.expect("data")["channel_id"], "channel-1");
            }
            other => panic!("unexpected frame: {other:?}"),
        }
    }

    #[test]
    fn realize_file_frame_deserializes() {
        let frame: DataInbound = serde_json::from_value(json!({
            "type": "realize_file",
            "file_id": "f-001",
            "remote_ref": "/home/user/report.pdf",
            "channel_id": "c-001"
        }))
        .expect("realize_file frame should deserialize");

        match frame {
            DataInbound::RealizeFile {
                file_id,
                remote_ref,
                channel_id,
                roots,
            } => {
                assert_eq!(file_id, "f-001");
                assert_eq!(remote_ref, "/home/user/report.pdf");
                assert_eq!(channel_id, "c-001");
                assert!(roots.is_empty(), "roots defaults to empty when absent");
            }
            other => panic!("unexpected frame: {other:?}"),
        }
    }

    #[test]
    fn realize_file_and_workspace_req_carry_session_roots() {
        let realize: DataInbound = serde_json::from_value(json!({
            "type": "realize_file",
            "file_id": "f", "remote_ref": "/repo/out.pdf", "channel_id": "c",
            "roots": ["/repo/service", "/repo/shared"]
        }))
        .expect("realize frame with roots");
        match realize {
            DataInbound::RealizeFile { roots, .. } => {
                assert_eq!(roots, vec!["/repo/service", "/repo/shared"]);
            }
            other => panic!("unexpected: {other:?}"),
        }

        let browse: DataInbound = serde_json::from_value(json!({
            "type": "workspace_req",
            "req_id": "r", "op": "ls", "path": "",
            "roots": ["/repo/service"]
        }))
        .expect("workspace_req with roots");
        match browse {
            DataInbound::WorkspaceReq { roots, .. } => {
                assert_eq!(roots, vec!["/repo/service"]);
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn workspace_req_watch_and_unwatch_deserialize() {
        let watch: DataInbound = serde_json::from_value(json!({
            "type": "workspace_req",
            "req_id": "r", "op": "watch", "path": "src",
            "roots": ["/repo/service"]
        }))
        .expect("watch workspace_req");
        match watch {
            DataInbound::WorkspaceReq {
                op, path, watch_id, ..
            } => {
                assert_eq!(op, "watch");
                assert_eq!(path, "src");
                assert!(watch_id.is_none(), "watch carries no watch_id");
            }
            other => panic!("unexpected: {other:?}"),
        }

        let unwatch: DataInbound = serde_json::from_value(json!({
            "type": "workspace_req",
            "req_id": "r2", "op": "unwatch", "watch_id": "w-123"
        }))
        .expect("unwatch workspace_req");
        match unwatch {
            DataInbound::WorkspaceReq { op, watch_id, .. } => {
                assert_eq!(op, "unwatch");
                assert_eq!(watch_id.as_deref(), Some("w-123"));
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn workspace_event_serializes_with_bot_scoped_shape() {
        let frame = DataOutbound::WorkspaceEvent {
            v: BRIDGE_PROTOCOL_VERSION,
            root: "/repo/service".to_string(),
            paths: vec!["src/main.rs".to_string(), "Cargo.toml".to_string()],
            kind: "change".to_string(),
        };
        let value = serde_json::to_value(frame).expect("workspace_event should serialize");
        assert_eq!(value["type"], "workspace_event");
        assert_eq!(value["root"], "/repo/service");
        assert_eq!(value["kind"], "change");
        assert_eq!(value["paths"][0], "src/main.rs");
        assert_eq!(value["paths"].as_array().expect("paths array").len(), 2);
        // Bot-scoped: the gateway maps bot → channels, so no channel_id is carried.
        assert!(value.get("channel_id").is_none());
    }

    #[test]
    fn unknown_data_frame_deserializes_as_unknown() {
        let frame: DataInbound = serde_json::from_value(json!({
            "type": "future_unknown_type",
            "some_field": "value"
        }))
        .expect("unknown frame should not fail");
        assert!(matches!(frame, DataInbound::Unknown));
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentBridgeAuth {
    #[serde(rename = "type", default = "default_auth_frame_type")]
    pub frame_type: String,
    #[serde(default = "default_bridge_protocol_version")]
    pub v: u32,
    pub token: String,
    #[serde(default = "default_bridge_protocol_version")]
    pub bridge_protocol_version: u32,
    #[serde(default)]
    pub connector: ConnectorInfo,
}

impl AgentBridgeAuth {
    pub fn new(token: impl Into<String>) -> Self {
        Self {
            frame_type: default_auth_frame_type(),
            v: BRIDGE_PROTOCOL_VERSION,
            token: token.into(),
            bridge_protocol_version: BRIDGE_PROTOCOL_VERSION,
            connector: ConnectorInfo::default(),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct ReconnectOptions {
    pub base_ms: u64,
    pub max_ms: u64,
    pub reset_after_ms: u64,
}

impl Default for ReconnectOptions {
    fn default() -> Self {
        Self {
            base_ms: 1_000,
            max_ms: 30_000,
            reset_after_ms: 30_000,
        }
    }
}

pub fn compute_backoff(attempt: u32, opts: ReconnectOptions) -> Duration {
    let exp = opts
        .base_ms
        .saturating_mul(2_u64.saturating_pow(attempt.saturating_sub(1)));
    let capped = exp.min(opts.max_ms);
    let jitter = rand::thread_rng().gen_range(0.5..=1.0);
    Duration::from_millis((capped as f64 * jitter).round() as u64)
}

#[derive(Debug, Clone)]
pub struct SessionConfig {
    pub bot_token: String,
    pub control_url: String,
    pub data_url: String,
    pub reconnect: ReconnectOptions,
    pub heartbeat_interval_ms: u64,
    pub send_ack_timeout_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelInfo {
    pub channel_id: String,
    #[serde(default)]
    pub channel_name: Option<String>,
    #[serde(default)]
    pub channel_type: Option<String>,
    #[serde(default)]
    pub workspace_id: Option<String>,
    #[serde(default)]
    pub joined_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AcpSecurityHello {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub mode: Option<String>,
    #[serde(default)]
    pub algorithm: Option<String>,
    #[serde(default)]
    pub require_capability: Option<bool>,
    #[serde(default)]
    pub allow_plaintext_fallback: Option<bool>,
    #[serde(default)]
    pub phase: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AcpCapabilityEnvelope {
    pub delegation_id: String,
    pub ts: i64,
    pub nonce: String,
    pub signature: String,
    #[serde(default)]
    pub request_id: Option<String>,
    #[serde(default)]
    pub algorithm: Option<String>,
    #[serde(default)]
    pub kid: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectorControlSettings {
    #[serde(default, rename = "agentNativePermissionMode")]
    pub agent_native_permission_mode: Option<String>,
    #[serde(default, rename = "permissionMode")]
    pub permission_mode: Option<String>,
    #[serde(default, rename = "requestTimeoutMs")]
    pub request_timeout_ms: Option<u64>,
    #[serde(default, rename = "promptTimeoutMs")]
    pub prompt_timeout_ms: Option<u64>,
    #[serde(default)]
    pub cwd: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default, rename = "configOptions")]
    pub config_options: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectorControlConfig {
    #[serde(default)]
    pub revision: Option<Value>,
    #[serde(default)]
    pub settings: Option<ConnectorControlSettings>,
    #[serde(default)]
    pub updated_at: Option<String>,
    #[serde(default)]
    pub last_status: Option<Value>,
    #[serde(default)]
    pub options: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerCapabilities {
    #[serde(default)]
    pub auth: Option<Value>,
    #[serde(default)]
    pub task_stream: Option<String>,
    #[serde(default)]
    pub runtime_session_control: Option<bool>,
    #[serde(default)]
    pub task: Option<bool>,
    #[serde(default)]
    pub cancel: Option<bool>,
    #[serde(default)]
    pub permission_resolution: Option<bool>,
    #[serde(default)]
    pub connector_config: Option<bool>,
    #[serde(default)]
    pub config_option_set: Option<bool>,
    #[serde(default)]
    pub membership_events: Option<bool>,
    #[serde(default)]
    pub resource_req: Option<bool>,
    #[serde(default)]
    pub file_upload: Option<Value>,
    #[serde(default)]
    pub send: Option<bool>,
    #[serde(default)]
    pub send_ack: Option<bool>,
    #[serde(default)]
    pub terminal_ack: Option<bool>,
    #[serde(default)]
    pub trace: Option<bool>,
    #[serde(default)]
    pub session_update: Option<bool>,
    #[serde(default)]
    pub resume: Option<Value>,
    #[serde(default)]
    pub acp_security: Option<bool>,
    /// Version of the connector release this gateway serves via its download
    /// proxy — the self-updater's trigger signal (see `self_update`). Absent on
    /// gateways that pin no release version.
    #[serde(default)]
    pub latest_connector_version: Option<String>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttachmentInfo {
    #[serde(default)]
    pub file_id: Option<String>,
    #[serde(default)]
    pub filename: Option<String>,
    #[serde(default)]
    pub content_type: Option<String>,
    #[serde(default)]
    pub size_bytes: Option<u64>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub is_image: Option<Value>,
    #[serde(default)]
    pub image_b64: Option<String>,
    #[serde(default)]
    pub is_audio: Option<Value>,
    #[serde(default)]
    pub audio_b64: Option<String>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeSessionRef {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub provider_session_key: Option<String>,
    #[serde(default)]
    pub provider_session_id: Option<String>,
    #[serde(default)]
    pub provider_account_id: Option<String>,
    #[serde(default)]
    pub provider_agent_id: Option<String>,
    #[serde(default)]
    pub primary_scope_type: Option<String>,
    #[serde(default)]
    pub primary_scope_id: Option<String>,
    #[serde(default)]
    pub task_scope_id: Option<String>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionPolicy {
    pub on_missing: String,
    pub on_paused: String,
    pub after_task: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeDescriptor {
    pub protocol: String,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub version: Option<String>,
    #[serde(default)]
    pub provider_session_id: Option<String>,
    #[serde(default)]
    pub config: Option<Value>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeSessionControlSession {
    pub id: String,
    pub provider_session_key: String,
    #[serde(default)]
    pub primary_scope_type: Option<String>,
    #[serde(default)]
    pub primary_scope_id: Option<String>,
    #[serde(default)]
    pub task_scope_id: Option<String>,
    /// The session's ACP `cwd` (absolute), if the Backend pinned one for an
    /// eager create/resume. Re-validated against `allowed_roots` by the connector.
    #[serde(default)]
    pub cwd: Option<String>,
    /// The session's ACP `additionalDirectories`, re-validated against `allowed_roots`.
    #[serde(default)]
    pub additional_dirs: Vec<String>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeSessionAckSession {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub provider_session_key: Option<String>,
    #[serde(default)]
    pub provider_session_id: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PermissionOption {
    pub option_id: String,
    #[serde(default)]
    pub kind: Option<String>,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PermissionResolution {
    pub request_id: String,
    #[serde(default)]
    pub message_id: Option<String>,
    pub resolution: String,
    #[serde(default)]
    pub option_id: Option<String>,
    #[serde(default)]
    pub resolved_by: Option<String>,
    #[serde(default)]
    pub resolved_at: Option<String>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigStatusRejectedField {
    pub field: String,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceResponse {
    #[serde(default = "default_bridge_protocol_version")]
    pub v: u32,
    pub req_id: String,
    pub ok: bool,
    #[serde(default)]
    pub data: Option<Value>,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub code: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeErrorFrame {
    #[serde(default = "default_bridge_protocol_version")]
    pub v: u32,
    pub code: String,
    #[serde(default)]
    pub detail: Option<String>,
    #[serde(default)]
    pub request_id: Option<String>,
    #[serde(default)]
    pub client_msg_id: Option<String>,
    #[serde(default)]
    pub retryable: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ControlInbound {
    #[serde(rename = "hello")]
    Hello {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        #[serde(default = "default_bridge_protocol_version")]
        bridge_protocol_version: u32,
        #[serde(default)]
        stream: Option<String>,
        bot_id: String,
        bot_username: String,
        #[serde(default)]
        bot_display_name: Option<String>,
        #[serde(default)]
        connection_id: Option<String>,
        session_id: String,
        #[serde(default)]
        memberships: Vec<ChannelInfo>,
        #[serde(default)]
        acp_security: Option<AcpSecurityHello>,
        #[serde(default)]
        connector_config: Option<ConnectorControlConfig>,
        #[serde(default)]
        server_capabilities: Option<ServerCapabilities>,
    },
    #[serde(rename = "runtime_session_control")]
    RuntimeSessionControl {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        request_id: String,
        action: String,
        session: RuntimeSessionControlSession,
        runtime: RuntimeDescriptor,
        #[serde(default)]
        reason: Option<String>,
        #[serde(default)]
        deadline_ms: Option<u64>,
    },
    #[serde(rename = "task")]
    Task {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        task_id: String,
        channel_id: String,
        trigger_msg_id: String,
        #[serde(default)]
        msg_id: Option<String>,
        #[serde(default)]
        trigger_seq: Option<i64>,
        #[serde(default)]
        depth: Option<i32>,
        #[serde(default)]
        trigger: Option<String>,
        placeholder_msg_id: String,
        provider_session_key: String,
        #[serde(default)]
        session_id: Option<String>,
        #[serde(default)]
        session_policy: Option<SessionPolicy>,
        #[serde(default)]
        trigger_message: Option<Value>,
        #[serde(default)]
        attachments: Vec<AttachmentInfo>,
        /// Pinned context blocks (already formatted strings) prepended to the prompt
        /// every request — the channel's "convention prompt" (e.g. a prompt template).
        #[serde(default)]
        pinned: Vec<String>,
        /// The session's primary working directory (ACP `cwd`), if the Backend
        /// pinned one for this session. Absolute; the connector re-validates it
        /// against `allowed_roots` and falls back to `default_cwd` when unset or
        /// rejected. Immutable for the session's lifetime.
        #[serde(default)]
        cwd: Option<String>,
        /// Extra roots for this session's effective root set (ACP
        /// `additionalDirectories`). Each is re-validated against `allowed_roots`;
        /// out-of-policy entries are dropped.
        #[serde(default)]
        additional_dirs: Vec<String>,
        #[serde(default)]
        binding_config: Option<Value>,
        #[serde(default)]
        session: Option<RuntimeSessionRef>,
        #[serde(default)]
        enqueued_at: Option<String>,
    },
    #[serde(rename = "channel_joined")]
    ChannelJoined {
        channel: ChannelInfo,
        #[serde(default)]
        invited_by: Option<String>,
    },
    #[serde(rename = "channel_left")]
    ChannelLeft { channel_id: String, reason: String },
    #[serde(rename = "cancel")]
    Cancel {
        msg_id: String,
        #[serde(default)]
        reason: Option<String>,
    },
    #[serde(rename = "config_update")]
    ConfigUpdate {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        #[serde(default)]
        revision: Option<Value>,
        #[serde(default)]
        settings: Option<ConnectorControlSettings>,
        #[serde(default)]
        updated_at: Option<String>,
    },
    #[serde(rename = "config_option_set")]
    ConfigOptionSet {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        request_id: String,
        #[serde(default)]
        session_id: Option<String>,
        #[serde(default)]
        provider_session_key: Option<String>,
        config_id: String,
        value: String,
        #[serde(default)]
        updated_at: Option<String>,
    },
    // Session-targeted mode change (ACP session/set_mode). Distinct from the
    // bot-wide config_update.agentNativePermissionMode AND from config_option_set:
    // it value-gates on the L0 allowed_modes envelope (config_option_set checks
    // only the config id), so a delegated mode change can't escape the clamp.
    #[serde(rename = "mode_set")]
    ModeSet {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        request_id: String,
        #[serde(default)]
        session_id: Option<String>,
        #[serde(default)]
        provider_session_key: Option<String>,
        mode: String,
        #[serde(default)]
        updated_at: Option<String>,
    },
    #[serde(rename = "permission_resolution")]
    PermissionResolution {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        #[serde(flatten)]
        resolution: PermissionResolution,
    },
    #[serde(rename = "pong")]
    Pong,
    #[serde(rename = "error")]
    Error {
        #[serde(flatten)]
        error: BridgeErrorFrame,
    },
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ControlOutbound {
    #[serde(rename = "auth")]
    Auth {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        token: String,
        #[serde(default = "default_bridge_protocol_version")]
        bridge_protocol_version: u32,
        #[serde(default)]
        connector: ConnectorInfo,
    },
    #[serde(rename = "ready")]
    Ready {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        /// Optional only for PARSING legacy frames (the retired TS connector
        /// sent `plugin_version` instead) — this connector always sets it.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        connector_version: Option<String>,
        // wire-compat: legacy alias for connector_version, kept so a typed
        // gateway parse still accepts the retired TS connector's ready frame
        // (pinned by fixtures/compat/ready_plugin_version.json).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        plugin_version: Option<String>,
        runtime: RuntimeDescriptor,
        #[serde(default)]
        connector_capabilities: Option<Value>,
    },
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "runtime_session_control_ack")]
    RuntimeSessionControlAck {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        request_id: String,
        action: String,
        ok: bool,
        #[serde(default)]
        session: Option<RuntimeSessionAckSession>,
        #[serde(default)]
        applied_at: Option<String>,
        #[serde(default)]
        code: Option<String>,
        #[serde(default)]
        error: Option<String>,
        #[serde(default)]
        retryable: Option<bool>,
    },
    #[serde(rename = "config_status")]
    ConfigStatus {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        #[serde(default)]
        revision: Option<Value>,
        ok: bool,
        #[serde(default)]
        applied: Vec<String>,
        #[serde(default)]
        rejected: Vec<ConfigStatusRejectedField>,
    },
    #[serde(rename = "config_options")]
    ConfigOptions {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        options: Value,
    },
    #[serde(rename = "config_option_status")]
    ConfigOptionStatus {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        request_id: String,
        ok: bool,
        #[serde(default)]
        session_id: Option<String>,
        #[serde(default)]
        provider_session_key: Option<String>,
        #[serde(default)]
        config_id: Option<String>,
        #[serde(default)]
        value: Option<String>,
        #[serde(default)]
        options: Option<Value>,
        #[serde(default)]
        error: Option<String>,
        #[serde(default)]
        code: Option<String>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum DataInbound {
    #[serde(rename = "hello")]
    Hello {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        #[serde(default = "default_bridge_protocol_version")]
        bridge_protocol_version: u32,
        stream: String,
        bot_id: String,
        #[serde(default)]
        connection_id: Option<String>,
        session_id: String,
        #[serde(default)]
        last_event_seq: u64,
        #[serde(default)]
        acp_security: Option<AcpSecurityHello>,
        #[serde(default)]
        server_capabilities: Option<ServerCapabilities>,
    },
    #[serde(rename = "pong")]
    Pong,
    #[serde(rename = "resume_ack")]
    ResumeAck {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        replayed: u64,
        up_to_seq: u64,
    },
    #[serde(rename = "send_ack")]
    SendAck {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        client_msg_id: String,
        ok: bool,
        #[serde(default)]
        message_id: Option<String>,
        #[serde(default)]
        finalized_placeholder: Option<bool>,
        #[serde(default)]
        permission_resolution: Option<Value>,
        #[serde(default)]
        error: Option<String>,
        #[serde(default)]
        code: Option<String>,
    },
    #[serde(rename = "terminal_ack")]
    TerminalAck {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        client_msg_id: String,
        ok: bool,
        #[serde(default)]
        msg_id: Option<String>,
        #[serde(default)]
        queued: Option<bool>,
        #[serde(default)]
        job_id: Option<String>,
        #[serde(default)]
        error: Option<String>,
        #[serde(default)]
        code: Option<String>,
    },
    #[serde(rename = "file_upload_ack")]
    FileUploadAck {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        #[serde(default)]
        client_file_id: Option<String>,
        ok: bool,
        #[serde(default)]
        file_id: Option<String>,
        #[serde(default)]
        filename: Option<String>,
        #[serde(default)]
        content_type: Option<String>,
        #[serde(default)]
        size_bytes: Option<u64>,
        #[serde(default)]
        preview_url: Option<String>,
        #[serde(default)]
        download_url: Option<String>,
        #[serde(default)]
        error: Option<String>,
        #[serde(default)]
        code: Option<String>,
    },
    #[serde(rename = "resource_res")]
    ResourceRes {
        #[serde(flatten)]
        response: ResourceResponse,
    },
    #[serde(rename = "error")]
    Error {
        #[serde(flatten)]
        error: BridgeErrorFrame,
    },
    /// Gateway → connector: realize a staged file. Connector reads the local path,
    /// base64-encodes it, and calls channel.files.realize to upload to S3.
    #[serde(rename = "realize_file")]
    RealizeFile {
        file_id: String,
        remote_ref: String,
        channel_id: String,
        /// The owning session's ACP root set (`cwd` + `additionalDirectories`). The
        /// connector confines `remote_ref` to these (∩ `allowed_roots`); empty ⇒
        /// the session's implicit root is the connector `default_cwd`.
        #[serde(default)]
        roots: Vec<String>,
    },
    /// Gateway → connector: browse/read/write the agent's real workspace, confined
    /// to `policy.workspace.allowed_roots`. Connector replies with `workspace_res`
    /// correlated by `req_id`. `op` ∈ { "ls", "read", "write", "validate_cwd",
    /// "git_status", "git_diff", "git_log", "git_show", "git_commit_files",
    /// "workspace_meta", "watch", "unwatch" }. The git ops are READ-ONLY.
    /// `workspace_meta` describes the workspace policy (allowed/effective roots,
    /// default_cwd, git availability) without touching the filesystem. `watch`
    /// starts a debounced recursive fs watcher on the resolved (clamped) dir and
    /// streams unsolicited `workspace_event` frames; `unwatch` (by `watch_id`)
    /// stops it.
    #[serde(rename = "workspace_req")]
    WorkspaceReq {
        req_id: String,
        op: String,
        #[serde(default)]
        path: String,
        /// Which allowed root to resolve `path` against (absolute path string).
        /// Defaults to the connector's default_cwd / first allowed root.
        #[serde(default)]
        root: Option<String>,
        /// base64 file bytes for `op == "write"`.
        #[serde(default)]
        content_b64: Option<String>,
        /// `op == "write"` precondition (safe remote writes). Absent/null ⇒
        /// unconditional overwrite (back-compat). `""` ⇒ create-only (fail if the
        /// file already exists). A 64-char lowercase-hex SHA-256 ⇒ overwrite only
        /// if the current file's bytes hash to it, else `E_CONFLICT`.
        #[serde(default)]
        if_etag: Option<String>,
        /// Optional session root set to scope this browse to (`cwd` +
        /// `additionalDirectories`). Empty ⇒ the full `allowed_roots` (bot-wide
        /// browse). When set, the effective roots are these ∩ `allowed_roots`.
        #[serde(default)]
        roots: Vec<String>,
        /// `op == "git_diff"`: diff the staged index (`--staged`) instead of the
        /// working tree.
        #[serde(default)]
        staged: Option<bool>,
        /// `op == "git_log"`: max commits to return (clamped to ≤100 by the
        /// connector).
        #[serde(default)]
        limit: Option<u32>,
        /// `op == "git_log"`: commits to skip before collecting (`--skip`), for
        /// pagination (clamped to ≤100000 by the connector).
        #[serde(default)]
        skip: Option<u32>,
        /// `op == "git_show" | "git_commit_files"`: the commit ref (a hex hash, as
        /// emitted by `git_log`; validated `^[0-9a-fA-F]{7,64}$` before use as argv).
        #[serde(default)]
        commit: Option<String>,
        /// `op == "git_show"`: optional repo-root-relative path filter — limits the
        /// commit diff to one file (as listed by `git_commit_files`). Validated
        /// (relative, no `..`, no leading `-`/`:`) and passed as a `:(top)`-anchored
        /// pathspec after `--`, never as a flag.
        #[serde(default)]
        commit_path: Option<String>,
        /// `op == "unwatch"`: the `watch_id` returned by a prior `watch` reply,
        /// identifying the fs watcher to stop.
        #[serde(default)]
        watch_id: Option<String>,
    },
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum DataOutbound {
    #[serde(rename = "auth")]
    Auth {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        token: String,
        #[serde(default = "default_bridge_protocol_version")]
        bridge_protocol_version: u32,
        #[serde(default)]
        connector: ConnectorInfo,
    },
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "resume")]
    Resume {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        last_event_seq: u64,
    },
    #[serde(rename = "delta")]
    Delta {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        msg_id: String,
        seq: u64,
        delta: String,
        #[serde(default)]
        provider_session_key: Option<String>,
        #[serde(default)]
        provider_session_id: Option<String>,
        #[serde(default)]
        session_id: Option<String>,
        #[serde(default)]
        acp_capability: Option<AcpCapabilityEnvelope>,
    },
    #[serde(rename = "done")]
    Done {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        client_msg_id: String,
        msg_id: String,
        #[serde(default)]
        file_ids: Vec<String>,
        #[serde(default)]
        mention_ids: Vec<String>,
        #[serde(default)]
        content: Option<String>,
        #[serde(default)]
        provider_session_key: Option<String>,
        #[serde(default)]
        provider_session_id: Option<String>,
        #[serde(default)]
        session_id: Option<String>,
        #[serde(default)]
        acp_capability: Option<AcpCapabilityEnvelope>,
    },
    #[serde(rename = "error")]
    Error {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        client_msg_id: String,
        msg_id: String,
        message: String,
        #[serde(default)]
        provider_session_key: Option<String>,
        #[serde(default)]
        provider_session_id: Option<String>,
        #[serde(default)]
        session_id: Option<String>,
        #[serde(default)]
        acp_capability: Option<AcpCapabilityEnvelope>,
    },
    #[serde(rename = "send")]
    Send {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        client_msg_id: String,
        channel_id: String,
        text: String,
        #[serde(default)]
        in_reply_to_msg_id: Option<String>,
        #[serde(default)]
        file_ids: Vec<String>,
        #[serde(default)]
        mention_ids: Vec<String>,
        #[serde(default)]
        session_id: Option<String>,
        #[serde(default)]
        provider_session_key: Option<String>,
        #[serde(default)]
        provider_session_id: Option<String>,
        #[serde(default)]
        acp_capability: Option<AcpCapabilityEnvelope>,
    },
    #[serde(rename = "file_upload")]
    FileUpload {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        client_file_id: String,
        channel_id: String,
        filename: String,
        #[serde(default)]
        content_type: Option<String>,
        data_b64: String,
    },
    #[serde(rename = "resource_req")]
    ResourceReq {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        req_id: String,
        resource: String,
        #[serde(default)]
        params: Option<Value>,
        #[serde(default)]
        encrypted: Option<bool>,
        #[serde(default)]
        encrypted_payload: Option<Value>,
        #[serde(default)]
        acp_capability: Option<AcpCapabilityEnvelope>,
    },
    /// Connector → gateway: reply to a `workspace_req`, correlated by `req_id`.
    #[serde(rename = "workspace_res")]
    WorkspaceRes {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        req_id: String,
        ok: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        data: Option<Value>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        error: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        code: Option<String>,
    },
    /// Connector → gateway: UNSOLICITED filesystem-change notification for an active
    /// `watch`. Bot-scoped (no channel_id — the gateway maps bot → channels and
    /// fans out to the workspace panels). `root` is the browse root the paths are
    /// relative to; `paths` is the coalesced, de-duplicated, capped (≤50) set of
    /// changed entries; `kind` is the change class (currently always "change").
    #[serde(rename = "workspace_event")]
    WorkspaceEvent {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        root: String,
        paths: Vec<String>,
        kind: String,
    },
    #[serde(rename = "permission_request")]
    PermissionRequest {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        client_msg_id: String,
        channel_id: String,
        request_id: String,
        #[serde(default)]
        task_id: Option<String>,
        #[serde(default)]
        msg_id: Option<String>,
        #[serde(default)]
        acp_session_id: Option<String>,
        #[serde(default)]
        provider_session_key: Option<String>,
        #[serde(default)]
        provider_session_id: Option<String>,
        #[serde(default)]
        session_id: Option<String>,
        #[serde(default)]
        title: Option<String>,
        body: String,
        /// Structured tool detail derived from the ACP `toolCall`
        /// (title / kind / raw_input / locations) so the channel card can show
        /// WHAT is being approved + a risk badge. None when the agent sent no
        /// toolCall (e.g. a plain message permission).
        #[serde(default)]
        tool: Option<Value>,
        #[serde(default)]
        options: Vec<PermissionOption>,
        #[serde(default)]
        acp_capability: Option<AcpCapabilityEnvelope>,
    },
    /// Tell the gateway a previously-forwarded permission request reached a
    /// terminal state locally (timeout / agent cancel) with no human decision,
    /// so the channel card stops hanging "pending" forever.
    #[serde(rename = "permission_cancel")]
    PermissionCancel {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        request_id: String,
        /// "timeout" | "cancelled"
        reason: String,
    },
    #[serde(rename = "session_update")]
    SessionUpdate {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        #[serde(default)]
        provider_session_key: Option<String>,
        #[serde(default)]
        provider_session_id: Option<String>,
        #[serde(default)]
        metadata: Option<Value>,
        #[serde(default)]
        acp_capability: Option<AcpCapabilityEnvelope>,
    },
    #[serde(rename = "trace")]
    Trace {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        msg_id: String,
        #[serde(default)]
        task_id: Option<String>,
        #[serde(default)]
        channel_id: Option<String>,
        #[serde(default)]
        run_id: Option<String>,
        #[serde(default)]
        session_key: Option<String>,
        #[serde(default)]
        provider_session_key: Option<String>,
        #[serde(default)]
        provider_session_id: Option<String>,
        #[serde(default)]
        session_id: Option<String>,
        stream: String,
        #[serde(default)]
        seq: Option<u64>,
        #[serde(default)]
        ts: Option<i64>,
        #[serde(default)]
        phase: Option<String>,
        #[serde(default)]
        status: Option<String>,
        #[serde(default)]
        title: Option<String>,
        #[serde(default)]
        message: Option<String>,
        #[serde(default)]
        data: Option<Value>,
        #[serde(default)]
        acp_capability: Option<AcpCapabilityEnvelope>,
    },
    /// Generic ACP-event passthrough (docs/arch/ACP_EVENT_TAXONOMY.md): forwards an
    /// ACP `session/update` verbatim so Cheers sees the full event surface. `name`
    /// is the registry name (e.g. `session/update:tool_call`); `payload` is the raw
    /// update. The connector stays ACP-generic — it never interprets the payload.
    #[serde(rename = "acp_event")]
    AcpEvent {
        #[serde(default = "default_bridge_protocol_version")]
        v: u32,
        name: String,
        #[serde(default)]
        channel_id: Option<String>,
        #[serde(default)]
        task_id: Option<String>,
        #[serde(default)]
        msg_id: Option<String>,
        #[serde(default)]
        session_id: Option<String>,
        #[serde(default)]
        provider_session_key: Option<String>,
        payload: Value,
    },
}

pub struct BridgeWebSocket {
    stream: WebSocketStream<MaybeTlsStream<TcpStream>>,
}

impl BridgeWebSocket {
    pub async fn connect(url: &str, bot_token: &str) -> anyhow::Result<Self> {
        let request = url
            .into_client_request()
            .with_context(|| format!("invalid websocket URL: {url}"))?;
        let (stream, _response) = connect_async(request)
            .await
            .with_context(|| format!("failed to connect websocket: {url}"))?;
        let mut socket = Self { stream };
        socket.send_json(&AgentBridgeAuth::new(bot_token)).await?;
        Ok(socket)
    }

    pub async fn send_json<T: Serialize>(&mut self, frame: &T) -> anyhow::Result<()> {
        let text = serde_json::to_string(frame)?;
        self.stream.send(Message::Text(text)).await?;
        Ok(())
    }

    pub async fn next_json(&mut self) -> anyhow::Result<Option<Value>> {
        while let Some(next) = self.stream.next().await {
            match next? {
                Message::Text(text) => return Ok(Some(serde_json::from_str(&text)?)),
                Message::Binary(bytes) => return Ok(Some(serde_json::from_slice(&bytes)?)),
                Message::Close(frame) => {
                    if let Some(frame) = frame {
                        let code = u16::from(frame.code);
                        if is_fatal_close_code(code) {
                            return Err(anyhow!(
                                "websocket closed with fatal code={} reason={}",
                                code,
                                frame.reason
                            ));
                        }
                    }
                    return Ok(None);
                }
                Message::Ping(payload) => {
                    self.stream.send(Message::Pong(payload)).await?;
                }
                Message::Pong(_) | Message::Frame(_) => {}
            }
        }
        Ok(None)
    }
}

/// Golden-fixture contract tests against `bridge-protocol/fixtures/` — the
/// same files the gateway's constructor tests are pinned to, so both ends
/// prove they agree on the exact wire bytes.
///
/// - `*/to_connector/*`: written by the GATEWAY's regen (`CHEERS_REGEN_FIXTURES=1
///   cargo test` in server/); here we prove they parse into the expected typed
///   variant (a rename/typo would fall through to `Unknown` and fail).
/// - `*/to_gateway/*`: written by THIS module's regen from typed values; the
///   assert mode proves parse→serialize round-trips to identical bytes.
/// - `tolerance/*`, `compat/*`: hand-frozen; only change with a version gate.
#[cfg(test)]
mod fixture_tests {
    use super::*;
    use serde_json::json;
    use std::path::PathBuf;

    fn fixtures_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("bridge-protocol/fixtures")
    }

    fn load(rel: &str) -> Value {
        let path = fixtures_root().join(rel);
        let raw = std::fs::read_to_string(&path).unwrap_or_else(|e| {
            panic!(
                "missing fixture {} ({e}); to_connector fixtures regen from server/ \
                 (CHEERS_REGEN_FIXTURES=1 cargo test), to_gateway ones from this crate",
                path.display()
            )
        });
        serde_json::from_str(&raw).expect("fixture is valid JSON")
    }

    /// to_gateway golden check: `frame` serializes to exactly the fixture, and
    /// the fixture parses back to a value that re-serializes identically.
    /// `CHEERS_REGEN_FIXTURES=1` rewrites the fixture from the typed value.
    fn assert_round_trips<T>(frame: &T, rel: &str)
    where
        T: Serialize + serde::de::DeserializeOwned,
    {
        let value = serde_json::to_value(frame).expect("frame serializes");
        let path = fixtures_root().join(rel);
        if std::env::var_os("CHEERS_REGEN_FIXTURES").is_some() {
            std::fs::create_dir_all(path.parent().unwrap()).expect("create fixtures dir");
            let pretty = serde_json::to_string_pretty(&value).expect("serialize fixture");
            std::fs::write(&path, format!("{pretty}\n")).expect("write fixture");
            return;
        }
        let expected = load(rel);
        assert_eq!(
            value, expected,
            "typed frame drifted from fixture {rel}; if intentional, prove wire-safety and regen"
        );
        let reparsed: T = serde_json::from_value(expected.clone())
            .unwrap_or_else(|e| panic!("fixture {rel} no longer parses: {e}"));
        let reserialized = serde_json::to_value(&reparsed).expect("reserialize");
        assert_eq!(reserialized, expected, "fixture {rel} does not round-trip");
    }

    // ── to_connector: every gateway-emitted frame parses to its variant ──────

    #[test]
    fn control_hello_fixture_parses() {
        let frame: ControlInbound =
            serde_json::from_value(load("control/to_connector/hello.json")).expect("hello parses");
        match frame {
            ControlInbound::Hello {
                bot_id,
                memberships,
                server_capabilities,
                connector_config,
                ..
            } => {
                assert_eq!(bot_id, "6f9619ff-8b86-4d01-b42d-00c04fc964ff");
                assert_eq!(memberships.len(), 1);
                let caps = server_capabilities.expect("caps present");
                assert_eq!(caps.latest_connector_version.as_deref(), Some("0.1.27"));
                assert!(connector_config.is_some());
            }
            other => panic!("expected Hello, got {other:?}"),
        }
    }

    #[test]
    fn task_fixture_parses() {
        let frame: ControlInbound =
            serde_json::from_value(load("control/to_connector/task.json")).expect("task parses");
        match frame {
            ControlInbound::Task {
                task_id,
                trigger_msg_id,
                msg_id,
                cwd,
                additional_dirs,
                attachments,
                pinned,
                session,
                session_policy,
                session_id,
                ..
            } => {
                assert_eq!(task_id, "99999999-aaaa-4bbb-8ccc-dddddddddddd");
                // wire-compat: msg_id duplicates trigger_msg_id by contract.
                assert_eq!(msg_id.as_deref(), Some(trigger_msg_id.as_str()));
                assert_eq!(cwd.as_deref(), Some("/workspace"));
                assert_eq!(additional_dirs, vec!["/data".to_string()]);
                assert_eq!(attachments.len(), 1);
                assert_eq!(attachments[0].filename.as_deref(), Some("notes.md"));
                assert_eq!(pinned.len(), 1);
                assert!(session_id.is_none(), "fixture pins session_id: null");
                let policy = session_policy.expect("session_policy present");
                assert_eq!(policy.on_missing, "create");
                let session = session.expect("nested session ref present");
                assert!(session.provider_session_key.is_some());
            }
            other => panic!("expected Task, got {other:?}"),
        }
    }

    #[test]
    fn remaining_control_to_connector_fixtures_parse() {
        for (rel, want) in [
            ("control/to_connector/cancel.json", "Cancel"),
            ("control/to_connector/config_update.json", "ConfigUpdate"),
            (
                "control/to_connector/config_option_set.json",
                "ConfigOptionSet",
            ),
            ("control/to_connector/mode_set.json", "ModeSet"),
            (
                "control/to_connector/permission_resolution.json",
                "PermissionResolution",
            ),
        ] {
            let frame: ControlInbound = serde_json::from_value(load(rel))
                .unwrap_or_else(|e| panic!("{rel} failed to parse: {e}"));
            let got = match &frame {
                ControlInbound::Cancel { .. } => "Cancel",
                ControlInbound::ConfigUpdate { settings, .. } => {
                    assert!(settings.is_some(), "{rel}: settings parsed");
                    "ConfigUpdate"
                }
                ControlInbound::ConfigOptionSet { .. } => "ConfigOptionSet",
                ControlInbound::ModeSet { .. } => "ModeSet",
                ControlInbound::PermissionResolution { resolution, .. } => {
                    assert_eq!(resolution.resolution, "allow", "{rel}");
                    "PermissionResolution"
                }
                other => panic!("{rel}: unexpected variant {other:?}"),
            };
            assert_eq!(got, want, "{rel}");
        }
    }

    #[test]
    fn data_to_connector_fixtures_parse() {
        use DataInbound as D;
        for (rel, want) in [
            ("data/to_connector/hello.json", "Hello"),
            ("data/to_connector/pong.json", "Pong"),
            ("data/to_connector/resume_ack.json", "ResumeAck"),
            ("data/to_connector/send_ack_ok.json", "SendAck"),
            ("data/to_connector/send_ack_err.json", "SendAck"),
            ("data/to_connector/terminal_ack_ok.json", "TerminalAck"),
            ("data/to_connector/terminal_ack_err.json", "TerminalAck"),
            ("data/to_connector/error.json", "Error"),
            ("data/to_connector/resource_res_ok.json", "ResourceRes"),
            ("data/to_connector/resource_res_err.json", "ResourceRes"),
            ("data/to_connector/realize_file.json", "RealizeFile"),
            ("data/to_connector/workspace_req_read.json", "WorkspaceReq"),
            ("data/to_connector/workspace_req_write.json", "WorkspaceReq"),
            (
                "data/to_connector/workspace_req_git_log.json",
                "WorkspaceReq",
            ),
            ("data/to_connector/workspace_req_watch.json", "WorkspaceReq"),
        ] {
            let frame: D = serde_json::from_value(load(rel))
                .unwrap_or_else(|e| panic!("{rel} failed to parse: {e}"));
            let got = match &frame {
                D::Hello { last_event_seq, .. } => {
                    assert_eq!(*last_event_seq, 0, "{rel}");
                    "Hello"
                }
                D::Pong => "Pong",
                D::ResumeAck { up_to_seq, .. } => {
                    assert_eq!(*up_to_seq, 42, "{rel}");
                    "ResumeAck"
                }
                D::SendAck { .. } => "SendAck",
                D::TerminalAck { .. } => "TerminalAck",
                D::Error { error } => {
                    assert_eq!(error.code, "CAPABILITY_DENIED", "{rel}");
                    "Error"
                }
                D::ResourceRes { .. } => "ResourceRes",
                D::RealizeFile { roots, .. } => {
                    assert_eq!(roots.len(), 1, "{rel}");
                    "RealizeFile"
                }
                D::WorkspaceReq {
                    op,
                    if_etag,
                    limit,
                    skip,
                    content_b64,
                    ..
                } => {
                    match op.as_str() {
                        "write" => {
                            assert!(if_etag.is_some(), "{rel}: write carries if_etag");
                            assert!(content_b64.is_some(), "{rel}: write carries content_b64");
                        }
                        "git_log" => {
                            assert_eq!(*limit, Some(20), "{rel}");
                            assert_eq!(*skip, Some(40), "{rel}");
                        }
                        _ => {}
                    }
                    "WorkspaceReq"
                }
                other => panic!("{rel}: unexpected variant {other:?}"),
            };
            assert_eq!(got, want, "{rel}");
        }
    }

    // ── dormant to_connector frames (no gateway emitter today) ──────────────

    #[test]
    fn dormant_control_frames_round_trip() {
        assert_round_trips(
            &ControlInbound::RuntimeSessionControl {
                v: BRIDGE_PROTOCOL_VERSION,
                request_id: "99999999-aaaa-4bbb-8ccc-dddddddddddd".into(),
                action: "terminate".into(),
                session: RuntimeSessionControlSession {
                    id: "eeeeeeee-ffff-4000-8111-222222222222".into(),
                    provider_session_key:
                        "cheers:channel:77777777-8888-4999-8aaa-bbbbbbbbbbbb:bot:6f9619ff-8b86-4d01-b42d-00c04fc964ff"
                            .into(),
                    primary_scope_type: Some("channel".into()),
                    primary_scope_id: Some("77777777-8888-4999-8aaa-bbbbbbbbbbbb".into()),
                    task_scope_id: None,
                    cwd: Some("/workspace".into()),
                    additional_dirs: vec![],
                    extra: Default::default(),
                },
                runtime: RuntimeDescriptor {
                    protocol: "acp".into(),
                    name: None,
                    version: None,
                    provider_session_id: None,
                    config: None,
                    extra: Default::default(),
                },
                reason: Some("user closed session".into()),
                deadline_ms: None,
            },
            "control/to_connector/runtime_session_control.json",
        );
        assert_round_trips(
            &ControlInbound::ChannelJoined {
                channel: ChannelInfo {
                    channel_id: "77777777-8888-4999-8aaa-bbbbbbbbbbbb".into(),
                    channel_name: Some("general".into()),
                    channel_type: Some("public".into()),
                    workspace_id: Some("cccccccc-dddd-4eee-8fff-000000000000".into()),
                    joined_at: Some("2026-06-01T10:15:30Z".into()),
                },
                invited_by: Some("33333333-4444-4555-8666-777777777777".into()),
            },
            "control/to_connector/channel_joined.json",
        );
        assert_round_trips(
            &ControlInbound::ChannelLeft {
                channel_id: "77777777-8888-4999-8aaa-bbbbbbbbbbbb".into(),
                reason: "removed_by_admin".into(),
            },
            "control/to_connector/channel_left.json",
        );
    }

    // ── to_gateway: one round-trip fixture per outbound variant ─────────────

    const KEY: &str =
        "cheers:channel:77777777-8888-4999-8aaa-bbbbbbbbbbbb:bot:6f9619ff-8b86-4d01-b42d-00c04fc964ff";

    #[test]
    fn control_to_gateway_fixtures_round_trip() {
        assert_round_trips(
            &ControlOutbound::Auth {
                v: BRIDGE_PROTOCOL_VERSION,
                token: "agb_fixture_token".into(),
                bridge_protocol_version: BRIDGE_PROTOCOL_VERSION,
                connector: ConnectorInfo {
                    name: "cce-acp-connector".into(),
                    version: "0.1.27".into(),
                },
            },
            "control/to_gateway/auth.json",
        );
        assert_round_trips(
            &ControlOutbound::Ready {
                v: BRIDGE_PROTOCOL_VERSION,
                connector_version: Some("0.1.27".into()),
                plugin_version: None,
                runtime: RuntimeDescriptor {
                    protocol: "acp".into(),
                    name: Some("claude-agent-acp".into()),
                    version: Some("1.4.2".into()),
                    provider_session_id: None,
                    config: None,
                    extra: Default::default(),
                },
                connector_capabilities: Some(json!({
                    "runtime_protocols": ["acp"],
                    "streaming": true,
                })),
            },
            "control/to_gateway/ready.json",
        );
        assert_round_trips(&ControlOutbound::Ping, "control/to_gateway/ping.json");
        assert_round_trips(
            &ControlOutbound::RuntimeSessionControlAck {
                v: BRIDGE_PROTOCOL_VERSION,
                request_id: "99999999-aaaa-4bbb-8ccc-dddddddddddd".into(),
                action: "terminate".into(),
                ok: true,
                session: Some(RuntimeSessionAckSession {
                    id: Some("eeeeeeee-ffff-4000-8111-222222222222".into()),
                    session_id: None,
                    provider_session_key: Some(KEY.into()),
                    provider_session_id: Some("acp-session-1".into()),
                    status: Some("terminated".into()),
                    extra: Default::default(),
                }),
                applied_at: Some("2026-06-01T10:15:30+00:00".into()),
                code: None,
                error: None,
                retryable: None,
            },
            "control/to_gateway/runtime_session_control_ack.json",
        );
        assert_round_trips(
            &ControlOutbound::ConfigStatus {
                v: BRIDGE_PROTOCOL_VERSION,
                revision: Some(json!(3)),
                ok: false,
                applied: vec!["model".into()],
                rejected: vec![ConfigStatusRejectedField {
                    field: "cwd".into(),
                    reason: "outside allowed_roots".into(),
                }],
            },
            "control/to_gateway/config_status.json",
        );
        assert_round_trips(
            &ControlOutbound::ConfigOptions {
                v: BRIDGE_PROTOCOL_VERSION,
                options: json!({
                    "configOptions": [{"id": "model", "value": "claude-sonnet-5"}],
                    "currentModeId": "default",
                }),
            },
            "control/to_gateway/config_options.json",
        );
        assert_round_trips(
            &ControlOutbound::ConfigOptionStatus {
                v: BRIDGE_PROTOCOL_VERSION,
                request_id: "99999999-aaaa-4bbb-8ccc-dddddddddddd".into(),
                ok: true,
                session_id: None,
                provider_session_key: Some(KEY.into()),
                config_id: Some("model".into()),
                value: Some("claude-sonnet-5".into()),
                options: None,
                error: None,
                code: None,
            },
            "control/to_gateway/config_option_status.json",
        );
    }

    #[test]
    fn data_to_gateway_fixtures_round_trip() {
        assert_round_trips(
            &DataOutbound::Auth {
                v: BRIDGE_PROTOCOL_VERSION,
                token: "agb_fixture_token".into(),
                bridge_protocol_version: BRIDGE_PROTOCOL_VERSION,
                connector: ConnectorInfo {
                    name: "cce-acp-connector".into(),
                    version: "0.1.27".into(),
                },
            },
            "data/to_gateway/auth.json",
        );
        assert_round_trips(&DataOutbound::Ping, "data/to_gateway/ping.json");
        assert_round_trips(
            &DataOutbound::Resume {
                v: BRIDGE_PROTOCOL_VERSION,
                last_event_seq: 42,
            },
            "data/to_gateway/resume.json",
        );
        assert_round_trips(
            &DataOutbound::Delta {
                v: BRIDGE_PROTOCOL_VERSION,
                msg_id: "33333333-4444-4555-8666-777777777777".into(),
                seq: 7,
                delta: "Hello, wor".into(),
                provider_session_key: Some(KEY.into()),
                provider_session_id: Some("acp-session-1".into()),
                session_id: None,
                acp_capability: None,
            },
            "data/to_gateway/delta.json",
        );
        assert_round_trips(
            &DataOutbound::Done {
                v: BRIDGE_PROTOCOL_VERSION,
                client_msg_id: "client-msg-2".into(),
                msg_id: "33333333-4444-4555-8666-777777777777".into(),
                file_ids: vec!["file-1".into()],
                mention_ids: vec![],
                content: Some("Hello, world!".into()),
                provider_session_key: Some(KEY.into()),
                provider_session_id: Some("acp-session-1".into()),
                session_id: None,
                acp_capability: None,
            },
            "data/to_gateway/done.json",
        );
        assert_round_trips(
            &DataOutbound::Error {
                v: BRIDGE_PROTOCOL_VERSION,
                client_msg_id: "client-msg-2".into(),
                msg_id: "33333333-4444-4555-8666-777777777777".into(),
                message: "prompt timed out".into(),
                provider_session_key: Some(KEY.into()),
                provider_session_id: None,
                session_id: None,
                acp_capability: None,
            },
            "data/to_gateway/error.json",
        );
        assert_round_trips(
            &DataOutbound::Send {
                v: BRIDGE_PROTOCOL_VERSION,
                client_msg_id: "client-msg-3".into(),
                channel_id: "77777777-8888-4999-8aaa-bbbbbbbbbbbb".into(),
                text: "Proactive update: build finished.".into(),
                in_reply_to_msg_id: None,
                file_ids: vec![],
                mention_ids: vec![],
                session_id: None,
                provider_session_key: Some(KEY.into()),
                provider_session_id: None,
                acp_capability: None,
            },
            "data/to_gateway/send.json",
        );
        assert_round_trips(
            &DataOutbound::FileUpload {
                v: BRIDGE_PROTOCOL_VERSION,
                client_file_id: "client-file-1".into(),
                channel_id: "77777777-8888-4999-8aaa-bbbbbbbbbbbb".into(),
                filename: "report.pdf".into(),
                content_type: Some("application/pdf".into()),
                data_b64: "aGVsbG8=".into(),
            },
            "data/to_gateway/file_upload.json",
        );
        assert_round_trips(
            &DataOutbound::ResourceReq {
                v: BRIDGE_PROTOCOL_VERSION,
                req_id: "req-1".into(),
                resource: "channel.activity.read".into(),
                params: Some(json!({"channel_id": "77777777-8888-4999-8aaa-bbbbbbbbbbbb"})),
                encrypted: None,
                encrypted_payload: None,
                acp_capability: None,
            },
            "data/to_gateway/resource_req.json",
        );
        assert_round_trips(
            &DataOutbound::WorkspaceRes {
                v: BRIDGE_PROTOCOL_VERSION,
                req_id: "req-2".into(),
                ok: true,
                data: Some(
                    json!({"etag": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}),
                ),
                error: None,
                code: None,
            },
            "data/to_gateway/workspace_res.json",
        );
        assert_round_trips(
            &DataOutbound::WorkspaceEvent {
                v: BRIDGE_PROTOCOL_VERSION,
                root: "/workspace".into(),
                paths: vec!["src/main.rs".into()],
                kind: "change".into(),
            },
            "data/to_gateway/workspace_event.json",
        );
        assert_round_trips(
            &DataOutbound::PermissionRequest {
                v: BRIDGE_PROTOCOL_VERSION,
                client_msg_id: "client-msg-4".into(),
                channel_id: "77777777-8888-4999-8aaa-bbbbbbbbbbbb".into(),
                request_id: "99999999-aaaa-4bbb-8ccc-dddddddddddd".into(),
                task_id: Some("99999999-aaaa-4bbb-8ccc-dddddddddddd".into()),
                msg_id: Some("33333333-4444-4555-8666-777777777777".into()),
                acp_session_id: Some("acp-session-1".into()),
                provider_session_key: Some(KEY.into()),
                provider_session_id: Some("acp-session-1".into()),
                session_id: None,
                title: Some("Run command".into()),
                body: "The agent wants to run `cargo test`.".into(),
                tool: Some(json!({"kind": "execute", "title": "cargo test"})),
                options: vec![PermissionOption {
                    option_id: "allow_once".into(),
                    kind: Some("allow_once".into()),
                    name: Some("Allow once".into()),
                    description: None,
                }],
                acp_capability: None,
            },
            "data/to_gateway/permission_request.json",
        );
        assert_round_trips(
            &DataOutbound::PermissionCancel {
                v: BRIDGE_PROTOCOL_VERSION,
                request_id: "99999999-aaaa-4bbb-8ccc-dddddddddddd".into(),
                reason: "timeout".into(),
            },
            "data/to_gateway/permission_cancel.json",
        );
        assert_round_trips(
            &DataOutbound::SessionUpdate {
                v: BRIDGE_PROTOCOL_VERSION,
                provider_session_key: Some(KEY.into()),
                provider_session_id: Some("acp-session-1".into()),
                metadata: Some(json!({"model": "claude-sonnet-5"})),
                acp_capability: None,
            },
            "data/to_gateway/session_update.json",
        );
        assert_round_trips(
            &DataOutbound::Trace {
                v: BRIDGE_PROTOCOL_VERSION,
                msg_id: "33333333-4444-4555-8666-777777777777".into(),
                task_id: Some("99999999-aaaa-4bbb-8ccc-dddddddddddd".into()),
                channel_id: Some("77777777-8888-4999-8aaa-bbbbbbbbbbbb".into()),
                run_id: Some("run-1".into()),
                session_key: None,
                provider_session_key: Some(KEY.into()),
                provider_session_id: None,
                session_id: None,
                stream: "progress".into(),
                seq: Some(3),
                ts: Some(1_780_000_000_000),
                phase: Some("tool_call".into()),
                status: Some("running".into()),
                title: Some("Reading files".into()),
                message: None,
                data: None,
                acp_capability: None,
            },
            "data/to_gateway/trace.json",
        );
        assert_round_trips(
            &DataOutbound::AcpEvent {
                v: BRIDGE_PROTOCOL_VERSION,
                name: "session/update:plan".into(),
                channel_id: Some("77777777-8888-4999-8aaa-bbbbbbbbbbbb".into()),
                task_id: None,
                msg_id: Some("33333333-4444-4555-8666-777777777777".into()),
                session_id: None,
                provider_session_key: Some(KEY.into()),
                payload: json!({"entries": [{"content": "Fix the bug", "status": "pending"}]}),
            },
            "data/to_gateway/acp_event.json",
        );
    }

    // ── tolerance + compat (hand-frozen fixtures) ────────────────────────────

    #[test]
    fn unknown_frame_type_parses_to_unknown() {
        let raw = load("tolerance/unknown_frame_type.json");
        let control: ControlInbound =
            serde_json::from_value(raw.clone()).expect("control tolerates unknown type");
        assert!(matches!(control, ControlInbound::Unknown));
        let data: DataInbound = serde_json::from_value(raw).expect("data tolerates unknown type");
        assert!(matches!(data, DataInbound::Unknown));
    }

    #[test]
    fn extra_unknown_field_is_ignored() {
        let frame: ControlInbound =
            serde_json::from_value(load("tolerance/extra_unknown_field.json"))
                .expect("unknown fields are ignored");
        match frame {
            ControlInbound::Cancel { msg_id, reason } => {
                assert_eq!(msg_id, "33333333-4444-4555-8666-777777777777");
                assert_eq!(reason.as_deref(), Some("user_cancelled"));
            }
            other => panic!("expected Cancel, got {other:?}"),
        }
    }

    /// The retired TS connector's `ready` (plugin_version, no connector_version)
    /// must keep parsing forever — the gateway's typed inbound parse (Phase 3)
    /// relies on this. Frozen; only change with an explicit version gate.
    #[test]
    fn legacy_ready_plugin_version_parses() {
        let frame: ControlOutbound =
            serde_json::from_value(load("compat/ready_plugin_version.json"))
                .expect("legacy ready parses");
        match frame {
            ControlOutbound::Ready {
                connector_version,
                plugin_version,
                runtime,
                ..
            } => {
                assert!(connector_version.is_none());
                assert_eq!(plugin_version.as_deref(), Some("0.9.3"));
                assert_eq!(runtime.protocol, "acp");
            }
            other => panic!("expected Ready, got {other:?}"),
        }
    }
}
