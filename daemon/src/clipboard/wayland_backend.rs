use std::io::{Read, Write};
use std::os::fd::AsFd;
use std::sync::{Arc, Mutex};
use std::thread;

use wayland_client::protocol::{wl_registry, wl_seat};
use wayland_client::{event_created_child, Connection, Dispatch, Proxy, QueueHandle};
use wayland_protocols_wlr::data_control::v1::client::zwlr_data_control_device_v1::{
    self, ZwlrDataControlDeviceV1,
};
use wayland_protocols_wlr::data_control::v1::client::zwlr_data_control_manager_v1::{
    self, ZwlrDataControlManagerV1,
};
use wayland_protocols_wlr::data_control::v1::client::zwlr_data_control_offer_v1::{
    self, ZwlrDataControlOfferV1,
};
use wayland_protocols_wlr::data_control::v1::client::zwlr_data_control_source_v1::{
    self, ZwlrDataControlSourceV1,
};

use crate::clipboard::backend::{ClipboardBackend, ClipboardContent};
use crate::error::{DaemonError, Result};

/// Mime types this backend offers when it owns the selection, and
/// accepts (in preference order) when reading an incoming selection
/// (T-L3): an image target is listed first so a screenshot copy that
/// also offers a text fallback (rare, but seen from some apps) reads
/// as the image, not the fallback text. The three text variants exist
/// because different apps advertise different ones for the same plain
/// text.
const SUPPORTED_MIME_TYPES: &[&str] = &[
    "image/png",
    "text/plain;charset=utf-8",
    "UTF8_STRING",
    "text/plain",
];

/// Maps one of [SUPPORTED_MIME_TYPES]'s text variants to the proto's
/// canonical "text/plain"; an image mime type (already canonical) maps
/// to itself.
fn canonical_mime(offered: &str) -> String {
    if offered.starts_with("image/") {
        offered.to_string()
    } else {
        "text/plain".to_string()
    }
}

/// State shared between the background Wayland event-loop thread and
/// the `ClipboardBackend` methods called from the daemon's clipboard
/// poll loop (T-301). All fields use interior mutability so the
/// backend can implement `get_content`/`set_content` on `&self`.
#[derive(Default)]
struct Shared {
    /// Most recently observed CLIPBOARD selection content, updated
    /// asynchronously whenever the compositor announces a new
    /// `selection` event on our data-control device.
    latest_selection: Mutex<Option<ClipboardContent>>,
    /// True once the compositor has torn down our data-control device
    /// (`finished` event, e.g. the seat went away). Once set, further
    /// calls report a clear error instead of silently no-op'ing.
    finished: Mutex<bool>,
    /// The write-side source currently offering our local clipboard
    /// content, if any. Replaced (and the previous one destroyed) each
    /// time `set_text` is called; kept alive here so the compositor can
    /// still service `send` requests against the most recent one.
    active_source: Mutex<Option<ZwlrDataControlSourceV1>>,
}

/// Dispatch target for the background event-loop thread.
#[derive(Default)]
struct EventLoopState {
    shared: Arc<Shared>,
    manager: Option<ZwlrDataControlManagerV1>,
    seat: Option<wl_seat::WlSeat>,
    device: Option<ZwlrDataControlDeviceV1>,
}

/// Per-offer collected mime types (T-301): the compositor sends zero or
/// more `offer` events for a `zwlr_data_control_offer_v1` object before
/// referencing it in a `selection` event, so these accumulate here as
/// the object's user-data.
#[derive(Default)]
struct OfferMimeTypes(Mutex<Vec<String>>);

/// T-301: Wayland-native clipboard backend using the compositor-side
/// `wlr-data-control-unstable-v1` protocol -- the same mechanism
/// `wl-copy`/`wl-paste` use -- which (unlike the core `wl_data_device`
/// protocol) does not require this client to hold keyboard focus or a
/// visible surface, making it suitable for a headless background
/// daemon.
pub struct WaylandClipboardBackend {
    shared: Arc<Shared>,
    manager: ZwlrDataControlManagerV1,
    device: ZwlrDataControlDeviceV1,
    conn: Connection,
    qh: QueueHandle<EventLoopState>,
}

impl WaylandClipboardBackend {
    /// Connects to the compositor, binds `zwlr_data_control_manager_v1`
    /// and a `wl_seat`, and spawns the background thread that keeps the
    /// connection alive and reacts to selection changes. Returns an
    /// error (never panics) if the display cannot be reached or the
    /// compositor does not support the protocol, so callers can fall
    /// through to another backend or disable clipboard sync entirely.
    pub fn new() -> Result<Self> {
        let conn = Connection::connect_to_env().map_err(|e| {
            DaemonError::Clipboard(format!("failed to connect to wayland display: {e}"))
        })?;

        let mut event_queue = conn.new_event_queue::<EventLoopState>();
        let qh = event_queue.handle();
        let display = conn.display();
        display.get_registry(&qh, ());

        let shared = Arc::new(Shared::default());
        let mut state = EventLoopState {
            shared: shared.clone(),
            ..Default::default()
        };

        // One roundtrip is enough to receive every currently-advertised
        // `wl_registry::Global` event and bind the ones we need.
        event_queue.roundtrip(&mut state).map_err(|e| {
            DaemonError::Clipboard(format!("initial wayland roundtrip failed: {e}"))
        })?;

        let manager = state.manager.clone().ok_or_else(|| {
            DaemonError::Clipboard(
                "compositor does not advertise zwlr_data_control_manager_v1 (wlr-data-control unsupported)"
                    .to_string(),
            )
        })?;
        let seat = state.seat.clone().ok_or_else(|| {
            DaemonError::Clipboard(
                "no wl_seat available to create a data-control device".to_string(),
            )
        })?;
        let device = manager.get_data_device(&seat, &qh, ());
        state.device = Some(device.clone());

        // A second roundtrip picks up the initial `selection` event (if
        // the clipboard already has content when we start).
        let _ = event_queue.roundtrip(&mut state);

        thread::Builder::new()
            .name("wayland-clipboard".to_string())
            .spawn(move || run_event_loop(event_queue, state))
            .map_err(|e| {
                DaemonError::Clipboard(format!("failed to spawn clipboard event-loop thread: {e}"))
            })?;

        Ok(Self {
            shared,
            manager,
            device,
            conn,
            qh,
        })
    }
}

impl ClipboardBackend for WaylandClipboardBackend {
    fn get_content(&self) -> Result<Option<ClipboardContent>> {
        if *self
            .shared
            .finished
            .lock()
            .unwrap_or_else(|p| p.into_inner())
        {
            return Err(DaemonError::Clipboard(
                "wayland data-control device was torn down by the compositor".to_string(),
            ));
        }
        Ok(self
            .shared
            .latest_selection
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone())
    }

    fn set_content(&self, content: &ClipboardContent) -> Result<()> {
        if *self
            .shared
            .finished
            .lock()
            .unwrap_or_else(|p| p.into_inner())
        {
            return Err(DaemonError::Clipboard(
                "wayland data-control device was torn down by the compositor".to_string(),
            ));
        }

        // Only offer mime types that actually match the content: an
        // image's bytes aren't valid text, so offering the text
        // variants alongside it (as every `set_content` used to,
        // unconditionally, back when this only ever handled text)
        // would let a paste-side app request "text/plain" and receive
        // raw PNG bytes.
        let offer_mimes: Vec<String> = if content.mime_type == "text/plain" {
            vec![
                "text/plain;charset=utf-8".to_string(),
                "UTF8_STRING".to_string(),
                "text/plain".to_string(),
            ]
        } else {
            vec![content.mime_type.clone()]
        };

        let bytes = Arc::new(content.bytes.clone());
        let source = self.manager.create_data_source(&self.qh, bytes);
        for mime in offer_mimes {
            source.offer(mime);
        }
        self.device.set_selection(Some(&source));

        self.conn.flush().map_err(|e| {
            DaemonError::Clipboard(format!("failed to flush wayland connection: {e}"))
        })?;

        let mut guard = self
            .shared
            .active_source
            .lock()
            .unwrap_or_else(|p| p.into_inner());
        if let Some(previous) = guard.replace(source) {
            previous.destroy();
        }

        Ok(())
    }
}

/// Runs forever on a dedicated OS thread, blocking on Wayland socket
/// I/O. Not a tokio task: the pipe reads performed while handling
/// `selection` events are ordinary blocking syscalls, and giving this
/// its own thread keeps them off the async runtime's worker threads.
fn run_event_loop(
    mut event_queue: wayland_client::EventQueue<EventLoopState>,
    mut state: EventLoopState,
) {
    loop {
        if let Err(e) = event_queue.blocking_dispatch(&mut state) {
            tracing::warn!(error = %e, "wayland clipboard event loop terminated");
            *state
                .shared
                .finished
                .lock()
                .unwrap_or_else(|p| p.into_inner()) = true;
            return;
        }
    }
}

/// Issues the `receive` request for a just-announced data-control
/// offer and returns the chosen mime type (in [SUPPORTED_MIME_TYPES]'s
/// preference order -- image first, T-L3) plus the read end of the
/// pipe the compositor will forward the offering client's data into.
/// Returns `Ok(None)` if the offer advertised none of our supported
/// mime types (nothing to request). Deliberately does *not* read the
/// pipe itself -- see `read_offer_pipe`'s doc comment for why that
/// must happen off this function's caller's thread.
fn request_offer_read(
    conn: &Connection,
    offer: &ZwlrDataControlOfferV1,
    mime_types: &[String],
) -> Result<Option<(&'static str, std::os::fd::OwnedFd)>> {
    let Some(mime) = SUPPORTED_MIME_TYPES
        .iter()
        .find(|supported| mime_types.iter().any(|m| m == *supported))
    else {
        return Ok(None);
    };

    let (read_fd, write_fd) = rustix::pipe::pipe().map_err(|e| {
        DaemonError::Clipboard(format!("failed to create pipe for clipboard read: {e}"))
    })?;
    offer.receive((*mime).to_string(), write_fd.as_fd());
    // The write end must reach the compositor before anything tries to
    // read the read end, or the two ends of the pipe would just
    // deadlock waiting on each other.
    conn.flush()
        .map_err(|e| DaemonError::Clipboard(format!("failed to flush wayland connection: {e}")))?;
    // Our own copy of the write end must be closed before reading, or
    // the pipe will never report EOF (a pipe only signals EOF once
    // every write-end file descriptor referencing it -- including this
    // process's own, distinct from the copy the compositor forwarded
    // to the offering client -- has been closed).
    drop(write_fd);

    Ok(Some((mime, read_fd)))
}

/// Blocks reading a clipboard-offer pipe to EOF, returning the raw
/// bytes (T-L3: no longer decoded as UTF-8 here -- the caller pairs
/// these bytes with whichever mime type `request_offer_read` chose, so
/// image bytes are never mangled through a lossy text decode). MUST be
/// called off the Wayland event-loop thread (`run_event_loop`'s
/// `blocking_dispatch` loop), never from inside a `Dispatch::event`
/// callback: the offering client only writes data into this pipe in
/// response to its *own* `send` event, which for a same-process
/// offerer (this daemon reading a selection it just set itself, or
/// two of this daemon's own backend instances in a test) is serviced
/// by that same event-loop thread. Reading synchronously inside the
/// `Selection` event handler would therefore block the very thread
/// that needs to keep dispatching in order to ever service that `send`
/// event -- a self-deadlock. Running the read on its own thread lets
/// `run_event_loop` return to `blocking_dispatch` immediately and
/// service the pending `send` event while this thread waits on it.
fn read_offer_pipe(read_fd: std::os::fd::OwnedFd) -> Result<Vec<u8>> {
    let mut file = std::fs::File::from(read_fd);
    let mut buf = Vec::new();
    file.read_to_end(&mut buf)
        .map_err(|e| DaemonError::Clipboard(format!("failed to read clipboard pipe: {e}")))?;
    Ok(buf)
}

impl Dispatch<wl_registry::WlRegistry, ()> for EventLoopState {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        let wl_registry::Event::Global {
            name,
            interface,
            version,
        } = event
        else {
            return;
        };

        match interface.as_str() {
            "zwlr_data_control_manager_v1" if state.manager.is_none() => {
                let bound_version = version.min(2);
                let manager =
                    registry.bind::<ZwlrDataControlManagerV1, _, _>(name, bound_version, qh, ());
                state.manager = Some(manager);
            }
            // Multi-seat setups are out of scope for MVP; the first
            // seat advertised is used.
            "wl_seat" if state.seat.is_none() => {
                let seat = registry.bind::<wl_seat::WlSeat, _, _>(name, version.min(1), qh, ());
                state.seat = Some(seat);
            }
            _ => {}
        }
    }
}

impl Dispatch<ZwlrDataControlManagerV1, ()> for EventLoopState {
    fn event(
        _: &mut Self,
        _: &ZwlrDataControlManagerV1,
        _: zwlr_data_control_manager_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        // zwlr_data_control_manager_v1 has no events.
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for EventLoopState {
    fn event(
        _: &mut Self,
        _: &wl_seat::WlSeat,
        _: wl_seat::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        // We only need the seat object's id to create a data-control
        // device; capability events are irrelevant here.
    }
}

impl Dispatch<ZwlrDataControlDeviceV1, ()> for EventLoopState {
    fn event(
        state: &mut Self,
        _: &ZwlrDataControlDeviceV1,
        event: zwlr_data_control_device_v1::Event,
        _: &(),
        conn: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match event {
            zwlr_data_control_device_v1::Event::Selection { id } => {
                let Some(offer) = id else {
                    *state
                        .shared
                        .latest_selection
                        .lock()
                        .unwrap_or_else(|p| p.into_inner()) = None;
                    return;
                };
                let mime_types = offer
                    .data::<OfferMimeTypes>()
                    .map(|d| d.0.lock().unwrap_or_else(|p| p.into_inner()).clone())
                    .unwrap_or_default();
                match request_offer_read(conn, &offer, &mime_types) {
                    Ok(Some((mime, read_fd))) => {
                        let shared = state.shared.clone();
                        if let Err(e) = thread::Builder::new()
                            .name("wayland-clipboard-read".to_string())
                            .spawn(move || match read_offer_pipe(read_fd) {
                                Ok(bytes) => {
                                    *shared
                                        .latest_selection
                                        .lock()
                                        .unwrap_or_else(|p| p.into_inner()) =
                                        Some(ClipboardContent {
                                            mime_type: canonical_mime(mime),
                                            bytes,
                                        });
                                }
                                Err(e) => {
                                    tracing::warn!(
                                        error = %e,
                                        "failed to read wayland clipboard selection"
                                    );
                                }
                            })
                        {
                            tracing::warn!(error = %e, "failed to spawn clipboard-read thread");
                        }
                    }
                    Ok(None) => {
                        // Offer advertised none of our supported mime
                        // types -- nothing we can display.
                        *state
                            .shared
                            .latest_selection
                            .lock()
                            .unwrap_or_else(|p| p.into_inner()) = None;
                    }
                    Err(e) => {
                        tracing::warn!(error = %e, "failed to request wayland clipboard selection");
                    }
                }
                offer.destroy();
            }
            zwlr_data_control_device_v1::Event::Finished => {
                tracing::warn!(
                    "wayland data-control device finished; clipboard sync degraded until restart"
                );
                *state
                    .shared
                    .finished
                    .lock()
                    .unwrap_or_else(|p| p.into_inner()) = true;
            }
            // `data_offer` needs no action beyond the automatic child
            // object creation (see `event_created_child` below); mime
            // types arrive as separate `offer` events on that object.
            // `primary_selection` (v2, PRIMARY selection) is out of
            // MVP scope -- only CLIPBOARD is synced.
            _ => {}
        }
    }

    event_created_child!(EventLoopState, ZwlrDataControlDeviceV1, [
        zwlr_data_control_device_v1::EVT_DATA_OFFER_OPCODE => (ZwlrDataControlOfferV1, OfferMimeTypes::default()),
    ]);
}

impl Dispatch<ZwlrDataControlOfferV1, OfferMimeTypes> for EventLoopState {
    fn event(
        _: &mut Self,
        _: &ZwlrDataControlOfferV1,
        event: zwlr_data_control_offer_v1::Event,
        data: &OfferMimeTypes,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let zwlr_data_control_offer_v1::Event::Offer { mime_type } = event {
            data.0
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .push(mime_type);
        }
    }
}

impl Dispatch<ZwlrDataControlSourceV1, Arc<Vec<u8>>> for EventLoopState {
    fn event(
        _: &mut Self,
        _: &ZwlrDataControlSourceV1,
        event: zwlr_data_control_source_v1::Event,
        content: &Arc<Vec<u8>>,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match event {
            zwlr_data_control_source_v1::Event::Send { mime_type, fd } => {
                if !SUPPORTED_MIME_TYPES.contains(&mime_type.as_str()) {
                    // Close the fd without writing so the requester
                    // doesn't hang waiting for data we don't have.
                    drop(fd);
                    return;
                }
                let mut file = std::fs::File::from(fd);
                if let Err(e) = file.write_all(content) {
                    tracing::warn!(error = %e, "failed to serve wayland clipboard send request");
                }
            }
            zwlr_data_control_source_v1::Event::Cancelled => {
                // Superseded by another selection owner; nothing to do,
                // the object is destroyed by whoever replaces it in
                // `set_text`.
            }
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn supported_mime_types_prefer_image_png_first() {
        assert_eq!(SUPPORTED_MIME_TYPES[0], "image/png");
        assert!(SUPPORTED_MIME_TYPES.contains(&"text/plain;charset=utf-8"));
        assert!(SUPPORTED_MIME_TYPES.contains(&"UTF8_STRING"));
        assert!(SUPPORTED_MIME_TYPES.contains(&"text/plain"));
    }
}
