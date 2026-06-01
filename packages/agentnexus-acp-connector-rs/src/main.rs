mod bridge;
mod cli;
mod config;
mod daemon;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "agentnexus_acp_connector=info,info".into()),
        )
        .with_target(false)
        .init();

    cli::run().await
}
