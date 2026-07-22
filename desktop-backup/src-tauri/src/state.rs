use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use connectible_desktop_core::LocalDaemonClient;
use tokio::sync::{Mutex, Notify, RwLock};

/// Shared app state: the connected local daemon client (once the
/// background bridge establishes it) and the resolved data dir/port
/// used to reconnect. `None` client means "not yet connected"; the
/// frontend renders a connecting/offline state until it flips.
#[derive(Default)]
pub struct AppState {
    inner: Arc<RwLock<Option<LocalDaemonClient>>>,
    /// T-801: whether tray setup actually succeeded this run. The
    /// close-window handler in `lib.rs` only hides to tray (instead of
    /// letting the window close normally) when this is true -- on a
    /// tray-host-less session (e.g. bare Hyprland with no waybar tray
    /// module), hiding with no tray icon to click would strand the user
    /// with no way to bring the window back.
    has_tray: AtomicBool,
    /// Cancel handles for in-flight outgoing transfers, keyed by
    /// transfer_id, so `cancel_transfer` can abort a running send.
    transfers: Arc<Mutex<HashMap<String, Arc<Notify>>>>,
}

impl AppState {
    pub async fn set_client(&self, client: LocalDaemonClient) {
        *self.inner.write().await = Some(client);
    }

    /// Drops the stored client so `is_connected()` / `require_client`
    /// reflect a disconnected daemon instead of handing out a stale
    /// client whose calls would error until the bridge reconnects.
    pub async fn clear_client(&self) {
        *self.inner.write().await = None;
    }

    pub async fn client(&self) -> Option<LocalDaemonClient> {
        self.inner.read().await.clone()
    }

    pub async fn is_connected(&self) -> bool {
        self.inner.read().await.is_some()
    }

    /// Registers a cancel handle for an outgoing transfer and returns it
    /// to hand to `send_file`.
    pub async fn register_transfer(&self, transfer_id: String) -> Arc<Notify> {
        let notify = Arc::new(Notify::new());
        self.transfers.lock().await.insert(transfer_id, notify.clone());
        notify
    }

    /// Drops a transfer's cancel handle once the send finishes (whether
    /// it completed, failed, or was canceled).
    pub async fn finish_transfer(&self, transfer_id: &str) {
        self.transfers.lock().await.remove(transfer_id);
    }

    /// Signals a running transfer to abort. Returns false if no such
    /// transfer is in flight.
    pub async fn cancel_transfer(&self, transfer_id: &str) -> bool {
        match self.transfers.lock().await.get(transfer_id) {
            Some(notify) => {
                notify.notify_one();
                true
            }
            None => false,
        }
    }

    /// Records whether tray setup succeeded this run (T-801).
    pub fn set_has_tray(&self, has_tray: bool) {
        self.has_tray.store(has_tray, Ordering::Relaxed);
    }

    /// Whether the close-window handler should hide to tray (true) or
    /// let the window close normally (false, no tray to bring it back
    /// from) (T-801).
    pub fn has_tray(&self) -> bool {
        self.has_tray.load(Ordering::Relaxed)
    }
}
