//! Tauri shell for the Connectible desktop app.
//!
//! This layer is intentionally thin: it owns the webview window, the
//! system tray, and the Tauri command/event plumbing, delegating every
//! bit of daemon interaction to `connectible-desktop-core`. Keeping the
//! logic in the core crate means it is unit/integration tested without
//! a webview (see desktop/core/tests), which is important because the
//! Tauri build itself requires system webkit libraries that are not
//! present in every CI/build environment.

mod commands;
mod events;
mod state;
mod tray;

use state::AppState;
use tauri::Manager;

/// Entry point invoked by `main.rs`. Named `run` so the mobile/desktop
/// `tauri::mobile_entry_point` convention lines up if iOS/Android
/// targets are added later.
pub fn run() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_opener::init())
        .manage(AppState::default())
        .on_window_event(|window, event| {
            // Closing the window hides it to the tray rather than exiting,
            // so the daemon bridge (and its live event streams) stays
            // alive in the background, as tray.rs documents. But only if
            // a tray actually exists (T-801): on a tray-host-less session
            // (bare Hyprland with no waybar tray module), hiding with
            // nothing to click to bring the window back would strand the
            // user -- let the window (and app) close normally instead.
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let has_tray = window.state::<AppState>().has_tray();
                if has_tray {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .setup(|app| {
            // Tray creation can fail in environments with no tray host
            // (e.g. a bare Hyprland/wlroots session with no waybar tray
            // module). That must not take down the whole app -- degrade
            // to windowed-only mode with a logged warning instead of
            // propagating the error out of setup (which `.run().expect()`
            // below would turn into a startup crash).
            match tray::build_tray(app.handle()) {
                Ok(()) => app.state::<AppState>().set_has_tray(true),
                Err(err) => {
                    tracing::warn!(%err, "tray setup failed; continuing without a system tray");
                    app.state::<AppState>().set_has_tray(false);
                }
            }
            // Kick off the daemon connection + local-event pump in the
            // background so the window paints immediately; the frontend
            // shows a "connecting to daemon" state until it succeeds.
            events::spawn_daemon_bridge(app.handle().clone());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_local_state,
            commands::list_devices,
            commands::disconnect_device,
            commands::forget_device,
            commands::set_remote_input_enabled,
            commands::set_clipboard_sync_enabled,
            commands::ping_daemon,
            commands::run_diagnostics,
            commands::pre_arm_pairing_code,
            commands::local_addresses,
            commands::get_download_dir,
            commands::set_download_dir,
            commands::open_path,
            commands::pair_with_device,
            commands::confirm_pin,
            commands::send_file,
            commands::cancel_transfer,
            commands::list_transfer_history,
            commands::update_tray,
            commands::daemon_connected,
            commands::daemon_status,
            commands::start_daemon,
            commands::stop_daemon,
            commands::check_tcp_port,
            commands::check_tls_handshake,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Connectible desktop app");
}
