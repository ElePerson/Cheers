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
    tungstenite::{client::IntoClientRequest, http::header::AUTHORIZATION, protocol::Message},
    MaybeTlsStream, WebSocketStream,
};

pub const WS_CLOSE_AUTH_FAIL: u16 = 4401;
pub const WS_CLOSE_SUPERSEDED: u16 = 4402;
pub const WS_CLOSE_BOT_UNAVAILABLE: u16 = 4403;

pub fn is_fatal_close_code(code: u16) -> bool {
    matches!(
        code,
        WS_CLOSE_AUTH_FAIL | WS_CLOSE_SUPERSEDED | WS_CLOSE_BOT_UNAVAILABLE
    )
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
    #[serde(default, rename = "agentnexusApprovalMode")]
    pub agentnexus_approval_mode: Option<String>,
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
#[serde(tag = "type")]
pub enum ControlInbound {
    #[serde(rename = "hello")]
    Hello {
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
        #[serde(default)]
        revision: Option<Value>,
        #[serde(default)]
        settings: Option<ConnectorControlSettings>,
        #[serde(default)]
        updated_at: Option<String>,
    },
    #[serde(rename = "pong")]
    Pong,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum DataOutbound {
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "resume")]
    Resume { last_event_seq: u64 },
    #[serde(rename = "delta")]
    Delta {
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
        client_msg_id: String,
        msg_id: String,
        #[serde(default)]
        file_ids: Vec<String>,
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
    #[serde(rename = "send")]
    Send {
        client_msg_id: String,
        channel_id: String,
        text: String,
        #[serde(default)]
        in_reply_to_msg_id: Option<String>,
        #[serde(default)]
        file_ids: Vec<String>,
        #[serde(default)]
        session_id: Option<String>,
        #[serde(default)]
        provider_session_key: Option<String>,
        #[serde(default)]
        provider_session_id: Option<String>,
        #[serde(default)]
        acp_capability: Option<AcpCapabilityEnvelope>,
    },
}

pub struct BridgeWebSocket {
    stream: WebSocketStream<MaybeTlsStream<TcpStream>>,
}

impl BridgeWebSocket {
    pub async fn connect(url: &str, bot_token: &str) -> anyhow::Result<Self> {
        let mut request = url
            .into_client_request()
            .with_context(|| format!("invalid websocket URL: {url}"))?;
        request.headers_mut().insert(
            AUTHORIZATION,
            format!("Bearer {bot_token}")
                .parse()
                .context("failed to build Authorization header")?,
        );
        let (stream, _response) = connect_async(request)
            .await
            .with_context(|| format!("failed to connect websocket: {url}"))?;
        Ok(Self { stream })
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
