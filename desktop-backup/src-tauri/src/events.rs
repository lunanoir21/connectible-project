use std::time::Duration;

use connectible_desktop_core::dto::LocalEventDto;
use connectible_desktop_core::LocalDaemonClient;
use tauri::{AppHandle, Emitter, Manager};

use crate::commands::daemon_endpoint;
use crate::state::AppState;

/// Reconnect backoff bounds for the daemon connection (PLAN.md edge
/// case: "daemon restart during an open SyncStream" -> exponential
/// backoff, 500ms initial, capped at 30s).
const BACKOFF_INITIAL: Duration = Duration::from_millis(500);
const BACKOFF_MAX: Duration = Duration::from_secs(30);

/// Spawns the background task that connects to the local daemon,
/// stores the client in shared state, forwards local events to the
/// frontend as Tauri "local-event" emissions, and reconnects with
/// exponential backoff if the daemon restarts.
pub fn spawn_daemon_bridge(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let mut backoff = BACKOFF_INITIAL;
        loop {
            match connect_and_pump(&app).await {
                Ok(()) => {
                    // Stream ended cleanly (daemon closed it); reset
                    // backoff and reconnect promptly.
                    backoff = BACKOFF_INITIAL;
                }
                Err(e) => {
                    tracing::warn!(error = %e, "daemon bridge disconnected; will retry");
                }
            }

            // Drop the (now dead) client so the shared state matches the
            // status we are about to emit; require_client will report
            // "not connected" rather than hand out a stale client.
            app.state::<AppState>().clear_client().await;
            let _ = app.emit("daemon-status", serde_json::json!({ "connected": false }));
            tokio::time::sleep(backoff).await;
            backoff = (backoff * 2).min(BACKOFF_MAX);
        }
    });
}

async fn connect_and_pump(app: &AppHandle) -> connectible_desktop_core::Result<()> {
    let (data_dir, port) = daemon_endpoint();
    let client = LocalDaemonClient::connect(data_dir, port).await?;

    app.state::<AppState>().set_client(client.clone()).await;
    let _ = app.emit("daemon-status", serde_json::json!({ "connected": true }));
    tracing::info!("connected to local daemon");

    let mut stream = client.subscribe_local_events().await?;
    while let Some(event) = stream.message().await? {
        if let Some(dto) = LocalEventDto::from_proto(event) {
            let _ = app.emit("local-event", dto);
        }
    }

    Ok(())
}
