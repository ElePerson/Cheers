#![allow(dead_code)]

use std::collections::BTreeMap;
use std::env;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context};
use serde_json::Value;
use tokio::fs;

#[derive(Debug, Clone)]
pub struct ConnectorConfig {
    pub accounts: BTreeMap<String, AccountConfig>,
    pub state_path: PathBuf,
}

#[derive(Debug, Clone)]
pub struct AccountConfig {
    pub bot_token: String,
    pub control_url: String,
    pub data_url: String,
    pub advanced: AdvancedConfig,
    pub agent: StdioAgentConfig,
    pub acp_capability: Option<AcpCapabilityConfig>,
}

#[derive(Debug, Clone)]
pub struct AdvancedConfig {
    pub reconnect_base_ms: u64,
    pub reconnect_max_ms: u64,
    pub heartbeat_interval_ms: u64,
    pub send_ack_timeout_ms: u64,
}

impl Default for AdvancedConfig {
    fn default() -> Self {
        Self {
            reconnect_base_ms: 500,
            reconnect_max_ms: 30_000,
            heartbeat_interval_ms: 25_000,
            send_ack_timeout_ms: 10 * 60_000,
        }
    }
}

#[derive(Debug, Clone)]
pub struct StdioAgentConfig {
    pub command: String,
    pub args: Vec<String>,
    pub model: Option<String>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<String, String>,
    pub request_timeout_ms: u64,
    pub prompt_timeout_ms: u64,
    pub agentnexus_approval_mode: PermissionMode,
    pub agent_native_permission_mode: Option<String>,
    pub mcp_servers: Value,
    pub client_capabilities: Option<Value>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PermissionMode {
    Ask,
    Reject,
    Allow,
    Cancel,
}

impl PermissionMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Ask => "ask",
            Self::Reject => "reject",
            Self::Allow => "allow",
            Self::Cancel => "cancel",
        }
    }
}

#[derive(Debug, Clone)]
pub struct AcpCapabilityConfig {
    pub delegation_id: String,
    pub private_key: String,
    pub kid: Option<String>,
    pub algorithm: String,
    pub request_id_prefix: Option<String>,
}

pub async fn load_config(config_path: &Path) -> anyhow::Result<ConnectorConfig> {
    let abs = std::fs::canonicalize(config_path)
        .with_context(|| format!("config file does not exist: {}", config_path.display()))?;
    let base_dir = abs
        .parent()
        .ok_or_else(|| anyhow!("config path has no parent: {}", abs.display()))?;
    let text = fs::read_to_string(&abs).await?;
    let parsed: Value = serde_json::from_str(&text)?;
    let root = parsed
        .as_object()
        .ok_or_else(|| anyhow!("config must be a JSON object"))?;
    let raw_accounts = root
        .get("accounts")
        .and_then(Value::as_object)
        .ok_or_else(|| anyhow!("config.accounts is required"))?;
    let mut accounts = BTreeMap::new();
    for (id, raw) in raw_accounts {
        accounts.insert(id.clone(), normalize_account(id, raw, base_dir).await?);
    }
    if accounts.is_empty() {
        return Err(anyhow!("config.accounts must include at least one account"));
    }
    let state_path = root
        .get("statePath")
        .and_then(Value::as_str)
        .map(|value| resolve_path(value, base_dir))
        .transpose()?
        .unwrap_or_else(|| base_dir.join(".agentnexus-acp-state.json"));

    Ok(ConnectorConfig {
        accounts,
        state_path,
    })
}

async fn normalize_account(
    id: &str,
    raw: &Value,
    base_dir: &Path,
) -> anyhow::Result<AccountConfig> {
    let obj = raw
        .as_object()
        .ok_or_else(|| anyhow!("accounts.{id} must be an object"))?;
    let agent = obj
        .get("agent")
        .and_then(Value::as_object)
        .ok_or_else(|| anyhow!("accounts.{id}.agent must be an object"))?;
    if agent.get("transport").and_then(Value::as_str) != Some("stdio") {
        return Err(anyhow!("accounts.{id}.agent.transport must be \"stdio\""));
    }
    let command = required_string(
        agent.get("command"),
        &format!("accounts.{id}.agent.command"),
    )?;
    let bot_token = required_string(obj.get("botToken"), &format!("accounts.{id}.botToken"))?;
    let control_url = required_string(obj.get("controlUrl"), &format!("accounts.{id}.controlUrl"))?;
    let data_url = required_string(obj.get("dataUrl"), &format!("accounts.{id}.dataUrl"))?;
    let cwd = match agent
        .get("cwd")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
    {
        Some(raw_cwd) => {
            let path = resolve_path(raw_cwd, base_dir)
                .with_context(|| format!("accounts.{id}.agent.cwd is invalid"))?;
            let metadata = fs::metadata(&path).await.with_context(|| {
                format!("accounts.{id}.agent.cwd does not exist: {}", path.display())
            })?;
            if !metadata.is_dir() {
                return Err(anyhow!(
                    "accounts.{id}.agent.cwd is not a directory: {}",
                    path.display()
                ));
            }
            Some(path)
        }
        None => None,
    };
    let env = match agent.get("env").and_then(Value::as_object) {
        Some(values) => values
            .iter()
            .map(|(key, value)| {
                Ok((
                    key.clone(),
                    expand_env_value(value.as_str().unwrap_or_default(), false)?,
                ))
            })
            .collect::<anyhow::Result<BTreeMap<_, _>>>()?,
        None => BTreeMap::new(),
    };

    Ok(AccountConfig {
        bot_token,
        control_url,
        data_url,
        advanced: normalize_advanced(obj.get("advanced")),
        acp_capability: normalize_acp_capability(id, obj, base_dir)?,
        agent: StdioAgentConfig {
            command,
            args: agent
                .get("args")
                .and_then(Value::as_array)
                .map(|items| items.iter().map(stringify_json_value).collect())
                .unwrap_or_default(),
            model: optional_string(agent.get("model")),
            cwd,
            env,
            request_timeout_ms: agent
                .get("requestTimeoutMs")
                .and_then(Value::as_u64)
                .unwrap_or(120_000),
            prompt_timeout_ms: agent
                .get("promptTimeoutMs")
                .and_then(Value::as_u64)
                .unwrap_or(900_000),
            agentnexus_approval_mode: normalize_permission_mode(
                agent
                    .get("agentnexusApprovalMode")
                    .or_else(|| agent.get("permissionMode")),
                PermissionMode::Ask,
            ),
            agent_native_permission_mode: optional_string(agent.get("agentNativePermissionMode")),
            mcp_servers: agent
                .get("mcpServers")
                .cloned()
                .unwrap_or_else(|| Value::Array(Vec::new())),
            client_capabilities: agent.get("clientCapabilities").cloned(),
        },
    })
}

fn normalize_advanced(value: Option<&Value>) -> AdvancedConfig {
    let mut out = AdvancedConfig::default();
    let Some(obj) = value.and_then(Value::as_object) else {
        return out;
    };
    if let Some(v) = obj.get("reconnectBaseMs").and_then(Value::as_u64) {
        out.reconnect_base_ms = v;
    }
    if let Some(v) = obj.get("reconnectMaxMs").and_then(Value::as_u64) {
        out.reconnect_max_ms = v;
    }
    if let Some(v) = obj.get("heartbeatIntervalMs").and_then(Value::as_u64) {
        out.heartbeat_interval_ms = v;
    }
    if let Some(v) = obj.get("sendAckTimeoutMs").and_then(Value::as_u64) {
        out.send_ack_timeout_ms = v;
    }
    out
}

fn normalize_acp_capability(
    id: &str,
    obj: &serde_json::Map<String, Value>,
    base_dir: &Path,
) -> anyhow::Result<Option<AcpCapabilityConfig>> {
    let Some(raw) = obj
        .get("acpCapability")
        .or_else(|| obj.get("acp_capability"))
    else {
        return Ok(None);
    };
    let cap = raw
        .as_object()
        .ok_or_else(|| anyhow!("accounts.{id}.acpCapability must be an object"))?;
    let delegation_id =
        optional_string(cap.get("delegationId").or_else(|| cap.get("delegation_id")))
            .ok_or_else(|| anyhow!("accounts.{id}.acpCapability.delegationId is required"))?;
    let private_key = optional_string(cap.get("privateKey").or_else(|| cap.get("private_key")))
        .ok_or_else(|| anyhow!("accounts.{id}.acpCapability.privateKey is required"))?;
    let private_key = if let Some(rest) = private_key.strip_prefix("file:") {
        format!("file:{}", resolve_path(rest.trim(), base_dir)?.display())
    } else {
        expand_env_value(&private_key, false)?
    };
    Ok(Some(AcpCapabilityConfig {
        delegation_id,
        private_key,
        kid: optional_string(cap.get("kid")),
        algorithm: optional_string(cap.get("algorithm")).unwrap_or_else(|| "ed25519".to_string()),
        request_id_prefix: optional_string(
            cap.get("requestIdPrefix")
                .or_else(|| cap.get("request_id_prefix")),
        ),
    }))
}

fn required_string(value: Option<&Value>, field: &str) -> anyhow::Result<String> {
    optional_string(value).ok_or_else(|| anyhow!("{field} is required"))
}

fn optional_string(value: Option<&Value>) -> Option<String> {
    value
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
}

fn normalize_permission_mode(value: Option<&Value>, fallback: PermissionMode) -> PermissionMode {
    match value.and_then(Value::as_str) {
        Some("allow") => PermissionMode::Allow,
        Some("cancel") => PermissionMode::Cancel,
        Some("reject") => PermissionMode::Reject,
        Some("ask") => PermissionMode::Ask,
        _ => fallback,
    }
}

fn stringify_json_value(value: &Value) -> String {
    value
        .as_str()
        .map(ToString::to_string)
        .unwrap_or_else(|| value.to_string())
}

fn resolve_path(value: &str, base_dir: &Path) -> anyhow::Result<PathBuf> {
    let mut expanded = expand_env_value(value.trim(), true)?;
    if expanded == "~" {
        expanded = home_dir()?;
    } else if let Some(rest) = expanded.strip_prefix("~/") {
        expanded = format!("{}/{}", home_dir()?, rest);
    }
    let path = PathBuf::from(expanded);
    Ok(if path.is_absolute() {
        path
    } else {
        base_dir.join(path)
    })
}

fn expand_env_value(value: &str, strict: bool) -> anyhow::Result<String> {
    if let Some(name) = value.strip_prefix('$') {
        if !name.is_empty()
            && name
                .chars()
                .all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
        {
            return lookup_env(name, strict);
        }
    }

    let mut out = String::new();
    let mut rest = value;
    while let Some(start) = rest.find("${") {
        out.push_str(&rest[..start]);
        let after = &rest[start + 2..];
        let Some(end) = after.find('}') else {
            out.push_str(&rest[start..]);
            return Ok(out);
        };
        let name = &after[..end];
        out.push_str(&lookup_env(name, strict)?);
        rest = &after[end + 1..];
    }
    out.push_str(rest);
    Ok(out)
}

fn lookup_env(name: &str, strict: bool) -> anyhow::Result<String> {
    if name == "PWD" {
        if let Ok(cwd) = env::current_dir() {
            return Ok(cwd.display().to_string());
        }
    }
    match env::var(name) {
        Ok(value) => Ok(value),
        Err(_) if strict => Err(anyhow!("environment variable {name} is not set")),
        Err(_) => Ok(String::new()),
    }
}

fn home_dir() -> anyhow::Result<String> {
    env::var("HOME").map_err(|_| anyhow!("HOME is not set"))
}
