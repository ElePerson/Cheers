use std::env;
use std::fs::{self, File, OpenOptions};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use tokio::signal;
use tokio::time::sleep;

#[cfg(unix)]
use std::os::unix::process::CommandExt;

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct DaemonPaths {
    pub home_dir: PathBuf,
    pub service_dir: PathBuf,
    pub metadata_path: PathBuf,
    pub stdout_log_path: PathBuf,
    pub stderr_log_path: PathBuf,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonMetadata {
    pub name: String,
    pub pid: u32,
    pub config_path: PathBuf,
    pub started_at: String,
    pub cwd: PathBuf,
    pub argv: Vec<String>,
    pub stdout_log_path: PathBuf,
    pub stderr_log_path: PathBuf,
}

#[derive(Debug, Clone)]
pub struct DaemonStatus {
    pub name: String,
    pub running: bool,
    pub metadata: Option<DaemonMetadata>,
    pub paths: DaemonPaths,
}

#[derive(Debug, Clone)]
pub struct StartDaemonOptions {
    pub name: String,
    pub config_path: PathBuf,
    pub home_dir: Option<PathBuf>,
}

pub fn resolve_daemon_paths(name: &str, home_dir: Option<&Path>) -> anyhow::Result<DaemonPaths> {
    let root = match home_dir {
        Some(path) => path.to_path_buf(),
        None => default_home_dir()?,
    };
    let home_dir = root.canonicalize().unwrap_or(root);
    let service_dir = home_dir.join(safe_name(name));
    Ok(DaemonPaths {
        home_dir,
        metadata_path: service_dir.join("daemon.json"),
        stdout_log_path: service_dir.join("stdout.log"),
        stderr_log_path: service_dir.join("stderr.log"),
        service_dir,
    })
}

pub async fn daemon_status(name: &str, home_dir: Option<&Path>) -> anyhow::Result<DaemonStatus> {
    let name = safe_name(name);
    let paths = resolve_daemon_paths(&name, home_dir)?;
    let metadata = read_metadata(&paths).await?;
    let running = metadata
        .as_ref()
        .map(|metadata| pid_is_running(metadata.pid))
        .unwrap_or(false);
    Ok(DaemonStatus {
        name,
        running,
        metadata,
        paths,
    })
}

pub async fn start_daemon(options: StartDaemonOptions) -> anyhow::Result<DaemonMetadata> {
    let name = safe_name(&options.name);
    let paths = resolve_daemon_paths(&name, options.home_dir.as_deref())?;
    let existing = daemon_status(&name, options.home_dir.as_deref()).await?;
    if existing.running {
        if let Some(metadata) = existing.metadata {
            return Ok(metadata);
        }
    }
    if existing.metadata.is_some() {
        remove_metadata(&paths).await?;
    }

    let config_path = fs::canonicalize(&options.config_path).with_context(|| {
        format!(
            "config file does not exist: {}",
            options.config_path.display()
        )
    })?;
    fs::create_dir_all(&paths.service_dir)
        .with_context(|| format!("failed to create {}", paths.service_dir.display()))?;

    let stdout = append_log(&paths.stdout_log_path)?;
    let stderr = append_log(&paths.stderr_log_path)?;
    let executable = env::current_exe().context("failed to resolve current executable")?;
    let cwd = env::current_dir().context("failed to resolve current directory")?;
    let argv = vec![
        executable.display().to_string(),
        "run".to_string(),
        "--config".to_string(),
        config_path.display().to_string(),
        "--name".to_string(),
        name.clone(),
    ];

    let mut command = Command::new(&executable);
    command
        .arg("run")
        .arg("--config")
        .arg(&config_path)
        .arg("--name")
        .arg(&name)
        .current_dir(&cwd)
        .stdin(Stdio::null())
        .stdout(Stdio::from(stdout))
        .stderr(Stdio::from(stderr))
        .env("AGENTNEXUS_ACP_DAEMON", "1")
        .env("AGENTNEXUS_ACP_DAEMON_NAME", &name);
    set_process_group(&mut command);
    let child = command.spawn().context("failed to start daemon process")?;
    let pid = child.id();
    drop(child);

    let metadata = DaemonMetadata {
        name,
        pid,
        config_path,
        started_at: Utc::now().to_rfc3339(),
        cwd,
        argv,
        stdout_log_path: paths.stdout_log_path.clone(),
        stderr_log_path: paths.stderr_log_path.clone(),
    };
    write_metadata(&paths, &metadata).await?;

    sleep(Duration::from_millis(1200)).await;
    if !pid_is_running(pid) {
        let err_tail = tail_file(&paths.stderr_log_path, 80)
            .await
            .unwrap_or_default();
        remove_metadata(&paths).await?;
        return Err(anyhow!(
            "daemon exited during startup{}",
            if err_tail.is_empty() {
                String::new()
            } else {
                format!(":\n{err_tail}")
            }
        ));
    }
    Ok(metadata)
}

pub async fn stop_daemon(
    name: &str,
    home_dir: Option<&Path>,
    timeout: Option<Duration>,
) -> anyhow::Result<DaemonStatus> {
    let name = safe_name(name);
    let paths = resolve_daemon_paths(&name, home_dir)?;
    let before = daemon_status(&name, home_dir).await?;
    let Some(metadata) = before.metadata else {
        return Ok(before);
    };
    if !before.running {
        remove_metadata(&paths).await?;
        return daemon_status(&name, home_dir).await;
    }

    signal_process(metadata.pid, libc::SIGTERM);
    signal_process_group(metadata.pid, libc::SIGTERM);
    let deadline = Instant::now() + timeout.unwrap_or_else(|| Duration::from_secs(10));
    while Instant::now() < deadline {
        if !pid_is_running(metadata.pid) {
            remove_metadata(&paths).await?;
            return daemon_status(&name, home_dir).await;
        }
        sleep(Duration::from_millis(250)).await;
    }

    signal_process(metadata.pid, libc::SIGKILL);
    signal_process_group(metadata.pid, libc::SIGKILL);
    sleep(Duration::from_millis(500)).await;
    remove_metadata(&paths).await?;
    daemon_status(&name, home_dir).await
}

pub async fn restart_daemon(options: StartDaemonOptions) -> anyhow::Result<DaemonMetadata> {
    stop_daemon(&options.name, options.home_dir.as_deref(), None).await?;
    start_daemon(options).await
}

pub async fn daemon_logs(
    name: &str,
    home_dir: Option<&Path>,
    lines: usize,
) -> anyhow::Result<String> {
    let paths = resolve_daemon_paths(name, home_dir)?;
    let lines = lines.max(1);
    let stdout = tail_file(&paths.stdout_log_path, lines)
        .await
        .unwrap_or_default();
    let stderr = tail_file(&paths.stderr_log_path, lines)
        .await
        .unwrap_or_default();
    Ok(format!(
        "==> {} <==\n{}\n\n==> {} <==\n{}",
        paths.stdout_log_path.display(),
        if stdout.is_empty() {
            "(empty)"
        } else {
            stdout.trim_end()
        },
        paths.stderr_log_path.display(),
        if stderr.is_empty() {
            "(empty)"
        } else {
            stderr.trim_end()
        },
    ))
}

pub async fn run_foreground_connector(config_path: &Path) -> anyhow::Result<()> {
    let config_path = fs::canonicalize(config_path)
        .with_context(|| format!("config file does not exist: {}", config_path.display()))?;
    let ts_cli = resolve_typescript_cli()?;
    let mut command = Command::new(resolve_node_command());
    command
        .arg(&ts_cli)
        .arg("run")
        .arg("--config")
        .arg(&config_path)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    set_process_group(&mut command);

    tracing::info!(
        runner = %ts_cli.display(),
        config = %config_path.display(),
        "starting TypeScript foreground connector runtime"
    );
    let mut child = command.spawn().with_context(|| {
        format!(
            "failed to start TypeScript foreground connector with {}",
            ts_cli.display()
        )
    })?;
    wait_for_foreground_child(&mut child).await
}

async fn wait_for_foreground_child(child: &mut Child) -> anyhow::Result<()> {
    #[cfg(unix)]
    let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .context("failed to install SIGTERM handler")?;

    loop {
        if let Some(status) = child
            .try_wait()
            .context("failed to wait for connector runtime")?
        {
            return exit_status_to_result(status);
        }

        #[cfg(unix)]
        tokio::select! {
            _ = sleep(Duration::from_millis(250)) => {}
            _ = signal::ctrl_c() => {
                return terminate_foreground_child(child).await;
            }
            _ = sigterm.recv() => {
                return terminate_foreground_child(child).await;
            }
        }

        #[cfg(not(unix))]
        tokio::select! {
            _ = sleep(Duration::from_millis(250)) => {}
            _ = signal::ctrl_c() => {
                return terminate_foreground_child(child).await;
            }
        }
    }
}

async fn terminate_foreground_child(child: &mut Child) -> anyhow::Result<()> {
    let pid = child.id();
    signal_process(pid, libc::SIGTERM);
    signal_process_group(pid, libc::SIGTERM);
    let deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < deadline {
        if let Some(status) = child
            .try_wait()
            .context("failed to wait for connector runtime")?
        {
            return exit_status_to_result(status);
        }
        sleep(Duration::from_millis(200)).await;
    }

    signal_process(pid, libc::SIGKILL);
    signal_process_group(pid, libc::SIGKILL);
    let status = child
        .wait()
        .context("failed to wait for killed connector runtime")?;
    exit_status_to_result(status)
}

fn exit_status_to_result(status: ExitStatus) -> anyhow::Result<()> {
    if status.success() {
        Ok(())
    } else {
        Err(anyhow!("connector runtime exited with {status}"))
    }
}

fn append_log(path: &Path) -> anyhow::Result<File> {
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .with_context(|| format!("failed to open log {}", path.display()))
}

async fn read_metadata(paths: &DaemonPaths) -> anyhow::Result<Option<DaemonMetadata>> {
    let text = match tokio::fs::read_to_string(&paths.metadata_path).await {
        Ok(text) => text,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(err) => {
            return Err(err)
                .with_context(|| format!("failed to read {}", paths.metadata_path.display()))
        }
    };
    let metadata: DaemonMetadata = serde_json::from_str(&text)
        .with_context(|| format!("failed to parse {}", paths.metadata_path.display()))?;
    if metadata.name.trim().is_empty() || metadata.pid == 0 {
        return Ok(None);
    }
    Ok(Some(metadata))
}

async fn write_metadata(paths: &DaemonPaths, metadata: &DaemonMetadata) -> anyhow::Result<()> {
    tokio::fs::create_dir_all(&paths.service_dir).await?;
    let text = serde_json::to_string_pretty(metadata)?;
    tokio::fs::write(&paths.metadata_path, format!("{text}\n"))
        .await
        .with_context(|| format!("failed to write {}", paths.metadata_path.display()))
}

async fn remove_metadata(paths: &DaemonPaths) -> anyhow::Result<()> {
    match tokio::fs::remove_file(&paths.metadata_path).await {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => {
            Err(err).with_context(|| format!("failed to remove {}", paths.metadata_path.display()))
        }
    }
}

async fn tail_file(path: &Path, lines: usize) -> anyhow::Result<String> {
    let text = match tokio::fs::read_to_string(path).await {
        Ok(text) => text,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(String::new()),
        Err(err) => return Err(err).with_context(|| format!("failed to read {}", path.display())),
    };
    let split: Vec<&str> = text.lines().collect();
    let start = split.len().saturating_sub(lines.max(1));
    Ok(split[start..].join("\n"))
}

fn resolve_typescript_cli() -> anyhow::Result<PathBuf> {
    if let Ok(path) = env::var("AGENTNEXUS_ACP_TS_CLI") {
        let path = PathBuf::from(path);
        if path.exists() {
            return Ok(path);
        }
        return Err(anyhow!(
            "AGENTNEXUS_ACP_TS_CLI points to a missing file: {}",
            path.display()
        ));
    }

    let mut candidates = Vec::new();
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    if let Some(packages_dir) = manifest_dir.parent() {
        candidates.push(packages_dir.join("agentnexus-acp-connector/dist/cli.js"));
    }
    if let Ok(exe) = env::current_exe() {
        if let Some(dir) = exe.parent() {
            candidates.push(dir.join("dist/cli.js"));
            candidates.push(dir.join("../dist/cli.js"));
        }
    }
    if let Ok(cwd) = env::current_dir() {
        candidates.push(cwd.join("dist/cli.js"));
        candidates.push(cwd.join("packages/agentnexus-acp-connector/dist/cli.js"));
    }

    for candidate in candidates {
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    Err(anyhow!(
        "could not locate the TypeScript foreground connector runner; run `npm run build` in packages/agentnexus-acp-connector or set AGENTNEXUS_ACP_TS_CLI"
    ))
}

fn resolve_node_command() -> String {
    env::var("AGENTNEXUS_ACP_NODE").unwrap_or_else(|_| "node".to_string())
}

fn default_home_dir() -> anyhow::Result<PathBuf> {
    if let Ok(home) = env::var("AGENTNEXUS_ACP_HOME") {
        return Ok(PathBuf::from(home));
    }
    let home = env::var("HOME").map_err(|_| anyhow!("HOME is not set"))?;
    Ok(PathBuf::from(home).join(".agentnexus/acp-connector"))
}

fn safe_name(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    let mut previous_dash = false;
    for ch in name.trim().chars() {
        let valid = ch.is_ascii_alphanumeric() || ch == '_' || ch == '.' || ch == '-';
        if valid {
            out.push(ch);
            previous_dash = false;
        } else if !previous_dash {
            out.push('-');
            previous_dash = true;
        }
    }
    let trimmed = out.trim_matches('-').to_string();
    if trimmed.is_empty() {
        "default".to_string()
    } else {
        trimmed
    }
}

fn pid_is_running(pid: u32) -> bool {
    if pid == 0 {
        return false;
    }

    #[cfg(unix)]
    {
        let result = unsafe { libc::kill(pid as i32, 0) };
        if result == 0 {
            return true;
        }
        let err = std::io::Error::last_os_error();
        return err.raw_os_error() == Some(libc::EPERM);
    }

    #[cfg(not(unix))]
    {
        false
    }
}

fn signal_process(pid: u32, signal: i32) {
    if pid == 0 {
        return;
    }
    #[cfg(unix)]
    unsafe {
        libc::kill(pid as i32, signal);
    }
    #[cfg(not(unix))]
    let _ = (pid, signal);
}

fn signal_process_group(pid: u32, signal: i32) {
    if pid == 0 {
        return;
    }
    #[cfg(unix)]
    unsafe {
        libc::kill(-(pid as i32), signal);
    }
    #[cfg(not(unix))]
    let _ = (pid, signal);
}

fn set_process_group(command: &mut Command) {
    #[cfg(unix)]
    {
        command.process_group(0);
    }
    #[cfg(not(unix))]
    let _ = command;
}
