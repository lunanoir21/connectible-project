use tauri::menu::{CheckMenuItem, Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager};

use crate::state::AppState;

/// Builds the system tray icon and menu (T-034): show/hide the main
/// window, toggle clipboard sync (T-310), and quit. Closing the window
/// hides it to tray rather than exiting (see the window close handler
/// wired in the frontend / the default Tauri behavior), keeping the
/// daemon bridge alive.
///
/// Falls back gracefully rather than panicking: a missing default
/// window icon (rare, but possible depending on how the bundle was
/// built) skips `.icon(...)` and lets Tauri use its own default rather
/// than `.expect()`-panicking the whole setup; see lib.rs's `.setup()`
/// for how a failure from this function itself is handled (logged, not
/// fatal, so a host with no tray (bare Hyprland/wlroots, no waybar tray
/// module) still gets a windowed app).
pub fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "Show Connectible", true, None::<&str>)?;
    let hide = MenuItem::with_id(app, "hide", "Hide to Tray", true, None::<&str>)?;
    // Optimistically checked (matches ClipboardSync's own default-
    // enabled state); corrected to whatever the daemon actually reports
    // the moment it connects, and again after every toggle click below.
    let clipboard_sync = CheckMenuItem::with_id(
        app,
        "clipboard-sync",
        "Sync Clipboard",
        true,
        true,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &hide, &clipboard_sync, &quit])?;

    let clipboard_sync_item = clipboard_sync.clone();
    let mut builder = TrayIconBuilder::with_id("connectible-tray")
        .tooltip("Connectible")
        .menu(&menu)
        .on_menu_event(move |app, event| match event.id.as_ref() {
            "show" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
                // The webview does not unmount/remount on hide/show, so
                // nudge the frontend to re-fetch local state (T-310):
                // otherwise a clipboard-sync toggle flipped from the
                // tray while the window was hidden would not show up
                // until some other event happened to trigger a refresh.
                let _ = app.emit("request-refresh", ());
            }
            "hide" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.hide();
                }
            }
            "clipboard-sync" => {
                let app = app.clone();
                let item = clipboard_sync_item.clone();
                tauri::async_runtime::spawn(async move {
                    toggle_clipboard_sync(&app, &item).await;
                });
            }
            "quit" => app.exit(0),
            _ => {}
        });

    match app.default_window_icon() {
        Some(icon) => builder = builder.icon(icon.clone()),
        None => tracing::warn!("no default window icon resolved; tray will use the platform default icon"),
    }

    builder.build(app)?;

    Ok(())
}

/// Flips clipboard sync through the same `LocalDaemonClient::
/// set_clipboard_sync_enabled` the main window's Tauri command
/// (`commands::set_clipboard_sync_enabled`) calls, so the tray and the
/// window always agree on one underlying daemon-side flag rather than
/// each tracking their own state (T-310). Corrects the menu checkmark
/// to whatever the daemon actually applied, and nudges the frontend to
/// refresh so the window reflects it next time it is shown.
async fn toggle_clipboard_sync(app: &AppHandle, item: &CheckMenuItem<tauri::Wry>) {
    let state = app.state::<AppState>();
    let Some(client) = state.client().await else {
        tracing::warn!("clipboard-sync tray toggle clicked but the daemon is not connected");
        return;
    };

    let requested = !item.is_checked().unwrap_or(true);
    match client.set_clipboard_sync_enabled(requested).await {
        Ok(actual) => {
            if let Err(e) = item.set_checked(actual) {
                tracing::warn!(error = %e, "failed to update clipboard-sync tray checkbox");
            }
            let _ = app.emit("request-refresh", ());
        }
        Err(e) => {
            tracing::warn!(error = %e, "failed to toggle clipboard sync from the tray");
        }
    }
}
