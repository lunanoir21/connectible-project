mod backend;
mod wayland_backend;

pub use backend::{detect_backend, ClipboardBackend, ClipboardContent, X11ClipboardBackend};
pub use wayland_backend::WaylandClipboardBackend;

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use sha2::{Digest, Sha256};
use tokio::sync::broadcast;

use crate::error::Result;
use crate::proto::connectible::v1::ClipboardData;

const HISTORY_CAPACITY: usize = 20;

/// T-L1: hard cap on synced clipboard content, chosen so clipboard
/// sync can't double as a backdoor bulk file-transfer channel --
/// anything bigger belongs in the dedicated file-transfer path. Text
/// essentially never approaches this; it exists for images (T-L3/L4).
pub const MAX_CLIPBOARD_BYTES: usize = 10 * 1024 * 1024; // 10 MiB

/// One entry in the clipboard ring buffer (T-023), shown by the
/// desktop UI's clipboard history panel.
#[derive(Debug, Clone)]
pub struct ClipboardHistoryEntry {
    /// Empty when `oversized` is true (T-L8) -- an oversized entry's
    /// bytes are never held in memory/history, only its metadata.
    pub content: Vec<u8>,
    pub mime_type: String,
    pub captured_at_ms: i64,
    /// "local" for changes captured from this machine's own clipboard,
    /// or the source device_id for changes applied from a peer.
    pub source: String,
    /// T-L8: true if this entry was observed locally but exceeded
    /// [MAX_CLIPBOARD_BYTES], so it was recorded for visibility but
    /// never sent to the peer.
    pub oversized: bool,
    /// Actual size in bytes; always set, but only meaningful to
    /// display when `oversized` is true (a normal entry's size is
    /// just `content.len()`).
    pub byte_size: i64,
}

/// Change-detection and echo-suppression engine (T-022) sitting on top
/// of a `ClipboardBackend`. Tracks the hash of the last locally-
/// captured content and the last content applied *from* a peer so
/// that applying an incoming update never gets re-broadcast back to
/// its sender as if it were a brand new local change.
pub struct ClipboardSync {
    backend: Arc<dyn ClipboardBackend>,
    last_local_hash: Mutex<Option<String>>,
    last_applied_hash: Mutex<Option<String>>,
    history: Mutex<VecDeque<ClipboardHistoryEntry>>,
    /// Live feed of history additions for the local UI's clipboard
    /// panel (consumed by SubscribeLocalEvents, T-037). Send errors are
    /// ignored -- no subscriber simply means no UI is attached.
    events: broadcast::Sender<ClipboardHistoryEntry>,
}

impl ClipboardSync {
    pub fn new(backend: Arc<dyn ClipboardBackend>) -> Self {
        let (events, _) = broadcast::channel(32);
        Self {
            backend,
            last_local_hash: Mutex::new(None),
            last_applied_hash: Mutex::new(None),
            history: Mutex::new(VecDeque::with_capacity(HISTORY_CAPACITY)),
            events,
        }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<ClipboardHistoryEntry> {
        self.events.subscribe()
    }

    /// Reads the current clipboard content and, if it differs from
    /// both the last locally-observed value and the last value this
    /// daemon itself applied from a peer, returns a `ClipboardData`
    /// frame ready to broadcast. Returns `Ok(None)` on no change (the
    /// common case, polled repeatedly), an unchanged/echoed value, or
    /// content exceeding `MAX_CLIPBOARD_BYTES` (T-L8: recorded to
    /// history for visibility -- see `oversized` -- but never sent).
    pub fn poll_local_change(&self) -> Result<Option<ClipboardData>> {
        let Some(content) = self.backend.get_content()? else {
            return Ok(None);
        };
        if content.bytes.is_empty() {
            return Ok(None);
        }

        let hash = hash_content(&content.bytes);

        {
            let last_local = self
                .last_local_hash
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            if last_local.as_deref() == Some(hash.as_str()) {
                return Ok(None);
            }
        }
        {
            let last_applied = self
                .last_applied_hash
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            if last_applied.as_deref() == Some(hash.as_str()) {
                // This is our own previously-applied peer update being
                // read back from the clipboard, not a new local change.
                *self
                    .last_local_hash
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(hash);
                return Ok(None);
            }
        }

        *self
            .last_local_hash
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(hash.clone());
        let captured_at_ms = now_ms();

        if content.bytes.len() > MAX_CLIPBOARD_BYTES {
            tracing::warn!(
                bytes = content.bytes.len(),
                cap = MAX_CLIPBOARD_BYTES,
                mime_type = %content.mime_type,
                "clipboard content exceeds the sync size cap; not sent to the peer"
            );
            self.push_history(ClipboardHistoryEntry {
                content: Vec::new(),
                mime_type: content.mime_type,
                captured_at_ms,
                source: "local".to_string(),
                oversized: true,
                byte_size: content.bytes.len() as i64,
            });
            return Ok(None);
        }

        self.push_history(ClipboardHistoryEntry {
            content: content.bytes.clone(),
            mime_type: content.mime_type.clone(),
            captured_at_ms,
            source: "local".to_string(),
            oversized: false,
            byte_size: content.bytes.len() as i64,
        });

        Ok(Some(ClipboardData {
            mime_type: content.mime_type,
            content: content.bytes,
            captured_at_ms,
            content_hash: hash,
        }))
    }

    /// Applies a `ClipboardData` frame received from `source_device_id`
    /// to the local clipboard, recording its hash so the next
    /// `poll_local_change` does not re-broadcast it as a new change.
    ///
    /// Per PLAN.md's clock-skew handling: `captured_at_ms` is used only
    /// for history display, never to reject the update -- a skewed
    /// clock on the peer logs a warning but the clipboard is still
    /// applied.
    pub fn apply_incoming(&self, data: &ClipboardData, source_device_id: &str) -> Result<()> {
        // Defense in depth (T-L8): a well-behaved peer never sends
        // oversized content (the sending side enforces the same cap
        // above), but this daemon must not trust that unconditionally.
        if data.content.len() > MAX_CLIPBOARD_BYTES {
            tracing::warn!(
                source_device_id,
                bytes = data.content.len(),
                cap = MAX_CLIPBOARD_BYTES,
                "rejecting an incoming clipboard update exceeding the size cap"
            );
            return Ok(());
        }

        if let Some(skew_ms) = clock_skew_ms(data.captured_at_ms) {
            if skew_ms.unsigned_abs() > 5 * 60 * 1000 {
                tracing::warn!(
                    source_device_id,
                    skew_ms,
                    "clipboard update timestamp differs from local clock by more than 5 minutes"
                );
            }
        }

        let mime_type = if data.mime_type.is_empty() {
            "text/plain".to_string()
        } else {
            data.mime_type.clone()
        };
        self.backend.set_content(&ClipboardContent {
            mime_type: mime_type.clone(),
            bytes: data.content.clone(),
        })?;

        *self
            .last_applied_hash
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(data.content_hash.clone());
        *self
            .last_local_hash
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(data.content_hash.clone());

        self.push_history(ClipboardHistoryEntry {
            content: data.content.clone(),
            mime_type,
            captured_at_ms: data.captured_at_ms,
            source: source_device_id.to_string(),
            oversized: false,
            byte_size: data.content.len() as i64,
        });

        Ok(())
    }

    pub fn history(&self) -> Vec<ClipboardHistoryEntry> {
        self.history
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .iter()
            .cloned()
            .collect()
    }

    fn push_history(&self, entry: ClipboardHistoryEntry) {
        let mut history = self
            .history
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if history.len() >= HISTORY_CAPACITY {
            history.pop_front();
        }
        history.push_back(entry.clone());
        drop(history);
        let _ = self.events.send(entry);
    }
}

fn hash_content(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex::encode(hasher.finalize())
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Returns `local_now_ms - captured_at_ms`, or `None` if the local
/// clock cannot be read (never treated as an error -- see PLAN.md edge
/// cases: clock skew is informational only).
fn clock_skew_ms(captured_at_ms: i64) -> Option<i64> {
    Some(now_ms() - captured_at_ms)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex as StdMutex;
    use tracing_test::traced_test;

    struct FakeBackend {
        content: StdMutex<Option<ClipboardContent>>,
    }

    impl FakeBackend {
        fn new(initial: Option<&str>) -> Arc<Self> {
            Arc::new(Self {
                content: StdMutex::new(initial.map(ClipboardContent::text)),
            })
        }

        /// Test convenience mirroring the old text-only API.
        fn set_text(&self, text: &str) {
            *self.content.lock().unwrap() = Some(ClipboardContent::text(text));
        }

        fn get_text(&self) -> Option<String> {
            self.content.lock().unwrap().as_ref().and_then(ClipboardContent::as_text)
        }
    }

    impl ClipboardBackend for FakeBackend {
        fn get_content(&self) -> Result<Option<ClipboardContent>> {
            Ok(self.content.lock().unwrap().clone())
        }

        fn set_content(&self, content: &ClipboardContent) -> Result<()> {
            *self.content.lock().unwrap() = Some(content.clone());
            Ok(())
        }
    }

    #[test]
    fn no_change_yields_no_frame() {
        let backend = FakeBackend::new(Some("hello"));
        let sync = ClipboardSync::new(backend);

        let first = sync.poll_local_change().unwrap();
        assert!(
            first.is_some(),
            "first observation of existing content is a change"
        );

        let second = sync.poll_local_change().unwrap();
        assert!(
            second.is_none(),
            "polling again with no change must yield None"
        );
    }

    #[test]
    fn new_local_content_is_detected_and_recorded_in_history() {
        let backend = FakeBackend::new(None);
        let sync = ClipboardSync::new(backend.clone());

        assert!(sync.poll_local_change().unwrap().is_none());

        backend.set_text("copied text");
        let change = sync
            .poll_local_change()
            .unwrap()
            .expect("new content must be detected");
        assert_eq!(change.content, b"copied text");
        assert_eq!(sync.history().len(), 1);
        assert_eq!(sync.history()[0].source, "local");
    }

    #[test]
    fn applying_incoming_update_does_not_echo_back_as_local_change() {
        let backend = FakeBackend::new(None);
        let sync = ClipboardSync::new(backend.clone());

        let incoming = ClipboardData {
            mime_type: "text/plain".to_string(),
            content: b"from peer".to_vec(),
            captured_at_ms: now_ms(),
            content_hash: hash_content(b"from peer"),
        };
        sync.apply_incoming(&incoming, "peer-device-1").unwrap();
        assert_eq!(backend.get_text().as_deref(), Some("from peer"));

        // Simulate the poll loop reading the clipboard back after the
        // backend applied the peer's update -- this must NOT be
        // reported as a new local change (no echo loop).
        let polled = sync.poll_local_change().unwrap();
        assert!(
            polled.is_none(),
            "applied peer content must not be re-broadcast"
        );

        assert_eq!(sync.history().len(), 1);
        assert_eq!(sync.history()[0].source, "peer-device-1");
    }

    #[test]
    fn history_is_capped_at_capacity() {
        let backend = FakeBackend::new(None);
        let sync = ClipboardSync::new(backend.clone());

        for i in 0..(HISTORY_CAPACITY + 5) {
            backend.set_text(&format!("entry-{i}"));
            sync.poll_local_change().unwrap();
        }

        assert_eq!(sync.history().len(), HISTORY_CAPACITY);
        assert_eq!(
            sync.history().last().unwrap().content,
            format!("entry-{}", HISTORY_CAPACITY + 4).into_bytes()
        );
    }

    #[test]
    fn oversized_local_content_is_recorded_but_not_sent() {
        let backend = FakeBackend::new(None);
        let sync = ClipboardSync::new(backend.clone());

        let huge = ClipboardContent {
            mime_type: "image/png".to_string(),
            bytes: vec![0u8; MAX_CLIPBOARD_BYTES + 1],
        };
        backend.set_content(&huge).unwrap();

        let change = sync.poll_local_change().unwrap();
        assert!(change.is_none(), "oversized content must never be sent");

        assert_eq!(sync.history().len(), 1);
        let entry = &sync.history()[0];
        assert!(entry.oversized);
        assert!(entry.content.is_empty(), "oversized bytes are not retained");
        assert_eq!(entry.byte_size, (MAX_CLIPBOARD_BYTES + 1) as i64);
    }

    #[test]
    fn oversized_incoming_content_is_rejected() {
        let backend = FakeBackend::new(None);
        let sync = ClipboardSync::new(backend.clone());

        let huge = vec![0u8; MAX_CLIPBOARD_BYTES + 1];
        let incoming = ClipboardData {
            mime_type: "image/png".to_string(),
            content: huge.clone(),
            captured_at_ms: now_ms(),
            content_hash: hash_content(&huge),
        };

        assert!(sync.apply_incoming(&incoming, "peer-device-4").is_ok());
        assert!(
            backend.get_content().unwrap().is_none(),
            "oversized incoming content must not be applied to the backend"
        );
        assert!(sync.history().is_empty());
    }

    #[traced_test]
    #[test]
    fn clock_skew_does_not_prevent_applying_the_update() {
        let backend = FakeBackend::new(None);
        let sync = ClipboardSync::new(backend.clone());

        let far_future = now_ms() + 10 * 60 * 1000; // 10 minutes ahead
        let incoming = ClipboardData {
            mime_type: "text/plain".to_string(),
            content: b"skewed".to_vec(),
            captured_at_ms: far_future,
            content_hash: hash_content(b"skewed"),
        };

        assert!(sync.apply_incoming(&incoming, "peer-device-2").is_ok());
        assert_eq!(backend.get_text().as_deref(), Some("skewed"));

        // T-902: applying still isn't enough on its own -- the
        // implementation is supposed to warn whenever it detects skew
        // beyond the 5-minute threshold (see clock_skew_ms's call site
        // in apply_incoming above), and this must actually fire, not
        // just "the update still applies despite skew". This assertion
        // fails if that tracing::warn! call is ever removed.
        assert!(
            logs_contain(
                "clipboard update timestamp differs from local clock by more than 5 minutes"
            ),
            "clock skew beyond the 5-minute threshold must be logged as a warning"
        );
    }

    /// T-902: the warning must NOT fire when there is no meaningful skew,
    /// so the assertion above is actually exercising the threshold check
    /// and not a warning that fires unconditionally on every update.
    #[traced_test]
    #[test]
    fn no_clock_skew_does_not_log_a_warning() {
        let backend = FakeBackend::new(None);
        let sync = ClipboardSync::new(backend.clone());

        let incoming = ClipboardData {
            mime_type: "text/plain".to_string(),
            content: b"in sync".to_vec(),
            captured_at_ms: now_ms(),
            content_hash: hash_content(b"in sync"),
        };

        assert!(sync.apply_incoming(&incoming, "peer-device-3").is_ok());
        assert!(!logs_contain("clipboard update timestamp differs"));
    }
}
