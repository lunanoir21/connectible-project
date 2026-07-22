use connectibled::config;
use connectibled::diagnostics::cli::{self as doctor_cli, DoctorArgs};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();

    // `connectibled doctor [--json] [--check <id>]` (Phase F / T-F6): run
    // the system diagnostics and exit, scriptably, instead of starting the
    // daemon. Diagnostics print their own output, so keep logging quiet
    // unless the user asked for it via RUST_LOG.
    if args.get(1).map(String::as_str) == Some("doctor") {
        init_tracing_quiet();
        let config = config::Config::load()?;
        let doctor_args = DoctorArgs::parse(&args[2..]);
        let code = doctor_cli::run(config, doctor_args).await;
        std::process::exit(code);
    }

    // Layered subscriber: the usual fmt output plus a capture layer that
    // retains recent warn/error lines for the System Doctor (T-F11).
    use tracing_subscriber::layer::SubscriberExt;
    use tracing_subscriber::util::SubscriberInitExt;
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .with(tracing_subscriber::fmt::layer())
        .with(connectibled::diagnostics::logbuf::CaptureLayer)
        .init();

    let config = config::Config::load()?;
    tracing::info!(data_dir = %config.data_dir.display(), port = config.grpc_port, "starting connectibled");

    connectibled::run(config).await
}

/// Tracing for the `doctor` subcommand: silent by default (the report is
/// the output) but still honoring an explicit `RUST_LOG`.
fn init_tracing_quiet() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("warn")),
        )
        .init();
}
