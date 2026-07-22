use std::collections::HashMap;
use std::os::fd::AsFd;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use wayland_client::protocol::{wl_output, wl_pointer, wl_registry, wl_seat};
use wayland_client::{Connection, Dispatch, QueueHandle, WEnum};
use wayland_protocols_misc::zwp_virtual_keyboard_v1::client::zwp_virtual_keyboard_manager_v1::ZwpVirtualKeyboardManagerV1;
use wayland_protocols_misc::zwp_virtual_keyboard_v1::client::zwp_virtual_keyboard_v1::ZwpVirtualKeyboardV1;
use wayland_protocols_wlr::virtual_pointer::v1::client::zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1;
use wayland_protocols_wlr::virtual_pointer::v1::client::zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1;
use xkbcommon::xkb;

use crate::error::{DaemonError, Result};
use crate::input::backend::InputBackend;
use crate::proto::connectible::v1::MouseButton;

/// Linux evdev button codes (see `linux/input-event-codes.h`), used by
/// both `wl_pointer`'s wire format and the virtual-pointer protocol.
const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;
const BTN_MIDDLE: u32 = 0x112;

/// XKB keycodes are offset from Linux evdev keycodes by a fixed amount
/// for X11-protocol-compatibility reasons; `zwp_virtual_keyboard_v1`
/// (like `wl_keyboard`) is wire-compatible with evdev codes directly.
const XKB_EVDEV_OFFSET: u32 = 8;

/// A scroll delta of 1.0 (per connectible.proto's `RemoteInputEvent`)
/// maps to one conventional wheel "click"; `wl_pointer`'s axis value
/// unit is 1/256th of that (matching typical libinput step size).
const SCROLL_STEP: f64 = 15.0;

/// Resolved keysym -> (evdev keycode, needs_shift) lookup, built once
/// from a compiled XKB keymap at construction time (T-302). Keysyms
/// not present in the (US) layout are simply not in the map; `key()`
/// logs and no-ops rather than erroring the whole input session over
/// one untranslatable key.
struct KeyLookup {
    by_keysym: HashMap<u32, (u32, bool)>,
    shift_mod_mask: u32,
}

impl KeyLookup {
    /// Compiles a minimal US-layout XKB keymap via `xkbcommon` and
    /// inverts it into a keysym -> keycode table. Returns the compiled
    /// keymap's serialized text form alongside the lookup table since
    /// the caller also needs to upload it to the compositor via
    /// `zwp_virtual_keyboard_v1::keymap()`.
    fn build() -> Result<(Self, String)> {
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        let keymap = xkb::Keymap::new_from_names(
            &context,
            "",
            "",
            "us",
            "",
            None,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        )
        .ok_or_else(|| {
            DaemonError::Input(
                "failed to compile a minimal US-layout XKB keymap (is libxkbcommon's data \
                 present, e.g. xkeyboard-config?)"
                    .to_string(),
            )
        })?;

        let shift_mod_mask = {
            let idx = keymap.mod_get_index(xkb::MOD_NAME_SHIFT);
            if idx == xkb::MOD_INVALID {
                0
            } else {
                1u32 << idx
            }
        };

        let mut by_keysym = HashMap::new();
        let min = keymap.min_keycode().raw();
        let max = keymap.max_keycode().raw();
        for raw_keycode in min..=max {
            let keycode = xkb::Keycode::new(raw_keycode);
            let num_layouts = keymap.num_layouts_for_key(keycode);
            if num_layouts == 0 {
                continue;
            }
            let num_levels = keymap.num_levels_for_key(keycode, 0);
            for level in 0..num_levels {
                for sym in keymap.key_get_syms_by_level(keycode, 0, level) {
                    // Prefer the lowest (unshifted) level already found
                    // for a given keysym.
                    by_keysym
                        .entry(sym.raw())
                        .or_insert((raw_keycode - XKB_EVDEV_OFFSET, level > 0));
                }
            }
        }

        let keymap_text = keymap.get_as_string(xkb::KEYMAP_FORMAT_TEXT_V1);
        Ok((
            Self {
                by_keysym,
                shift_mod_mask,
            },
            keymap_text,
        ))
    }

    fn lookup(&self, keysym: u32) -> Option<(u32, bool)> {
        self.by_keysym.get(&keysym).copied()
    }
}

/// Registry-driven bootstrap state: only used during the initial
/// roundtrip(s) in `WaylandInputBackend::new`, not afterward -- once
/// construction finishes, all further calls are one-shot requests on
/// already-bound objects (neither the virtual-pointer nor
/// virtual-keyboard protocols have any events to react to).
#[derive(Default)]
struct BootstrapState {
    pointer_manager: Option<ZwlrVirtualPointerManagerV1>,
    keyboard_manager: Option<ZwpVirtualKeyboardManagerV1>,
    seat: Option<wl_seat::WlSeat>,
    output: Option<wl_output::WlOutput>,
    output_size: Option<(u32, u32)>,
}

/// T-302: Wayland-native remote-input backend using
/// `wlr-virtual-pointer-unstable-v1` (mouse) and
/// `virtual-keyboard-unstable-v1` (keyboard), the compositor-side
/// input-injection mechanism `wtype`/`ydotool`'s Wayland mode use, which
/// (unlike X11/XWayland input injection) is visible to native Wayland
/// clients.
pub struct WaylandInputBackend {
    conn: Connection,
    pointer: ZwlrVirtualPointerV1,
    keyboard: ZwpVirtualKeyboardV1,
    /// Output size in pixels, used as the `motion_absolute` extent so
    /// normalized `[0,1]` coordinates map onto the real screen (T-302).
    /// Falls back to a fixed default if `wl_output` geometry could not
    /// be determined, which only degrades absolute-position accuracy,
    /// not basic functionality.
    output_size: (u32, u32),
    keys: KeyLookup,
    /// Serializes request issuance: `InputBackend` methods take `&self`
    /// (see backend.rs), but sending a wayland request and flushing the
    /// connection is not safe to interleave across threads.
    lock: Mutex<()>,
}

/// Used when `wl_output` geometry cannot be determined (T-302's
/// documented degradation path) -- a common enough resolution that
/// normalized coordinates still land somewhere sane on real hardware.
const FALLBACK_OUTPUT_SIZE: (u32, u32) = (1920, 1080);

impl WaylandInputBackend {
    pub fn new() -> Result<Self> {
        let conn = Connection::connect_to_env().map_err(|e| {
            DaemonError::Input(format!("failed to connect to wayland display: {e}"))
        })?;

        let mut event_queue = conn.new_event_queue::<BootstrapState>();
        let qh = event_queue.handle();
        conn.display().get_registry(&qh, ());

        let mut state = BootstrapState::default();
        event_queue
            .roundtrip(&mut state)
            .map_err(|e| DaemonError::Input(format!("initial wayland roundtrip failed: {e}")))?;

        let pointer_manager = state.pointer_manager.clone().ok_or_else(|| {
            DaemonError::Input(
                "compositor does not advertise zwlr_virtual_pointer_manager_v1 (wlr-virtual-pointer unsupported)"
                    .to_string(),
            )
        })?;
        let keyboard_manager = state.keyboard_manager.clone().ok_or_else(|| {
            DaemonError::Input(
                "compositor does not advertise zwp_virtual_keyboard_manager_v1 (virtual-keyboard unsupported)"
                    .to_string(),
            )
        })?;
        let seat = state.seat.clone().ok_or_else(|| {
            DaemonError::Input("no wl_seat available for input injection".to_string())
        })?;

        // wl_output sends its geometry/mode events only after being
        // bound, so a second roundtrip is needed to receive them.
        if state.output.is_some() {
            let _ = event_queue.roundtrip(&mut state);
        }
        let output_size = state.output_size.unwrap_or_else(|| {
            tracing::warn!(
                fallback_width = FALLBACK_OUTPUT_SIZE.0,
                fallback_height = FALLBACK_OUTPUT_SIZE.1,
                "could not determine wl_output resolution; falling back to a default for absolute pointer mapping"
            );
            FALLBACK_OUTPUT_SIZE
        });

        let pointer = match &state.output {
            Some(output) => pointer_manager.create_virtual_pointer_with_output(
                Some(&seat),
                Some(output),
                &qh,
                (),
            ),
            None => pointer_manager.create_virtual_pointer(Some(&seat), &qh, ()),
        };
        let keyboard = keyboard_manager.create_virtual_keyboard(&seat, &qh, ());

        let (keys, keymap_text) = KeyLookup::build()?;
        upload_keymap(&keyboard, &keymap_text)?;

        conn.flush()
            .map_err(|e| DaemonError::Input(format!("failed to flush wayland connection: {e}")))?;

        Ok(Self {
            conn,
            pointer,
            keyboard,
            output_size,
            keys,
            lock: Mutex::new(()),
        })
    }

    fn flush(&self) -> Result<()> {
        self.conn
            .flush()
            .map_err(|e| DaemonError::Input(format!("failed to flush wayland connection: {e}")))
    }
}

impl InputBackend for WaylandInputBackend {
    fn mouse_move(&self, x: f32, y: f32) -> Result<()> {
        let _guard = self.lock.lock().unwrap_or_else(|p| p.into_inner());
        let (width, height) = self.output_size;
        let px = (x.clamp(0.0, 1.0) * width as f32) as u32;
        let py = (y.clamp(0.0, 1.0) * height as f32) as u32;
        self.pointer
            .motion_absolute(now_ms(), px, py, width, height);
        self.pointer.frame();
        self.flush()
    }

    fn mouse_button(&self, button: MouseButton, pressed: bool) -> Result<()> {
        let code = match button {
            MouseButton::Left => BTN_LEFT,
            MouseButton::Right => BTN_RIGHT,
            MouseButton::Middle => BTN_MIDDLE,
            MouseButton::Unspecified => return Ok(()),
        };
        let _guard = self.lock.lock().unwrap_or_else(|p| p.into_inner());
        let state = if pressed {
            wl_pointer::ButtonState::Pressed
        } else {
            wl_pointer::ButtonState::Released
        };
        self.pointer.button(now_ms(), code, state);
        self.pointer.frame();
        self.flush()
    }

    fn scroll(&self, delta_x: f32, delta_y: f32) -> Result<()> {
        let _guard = self.lock.lock().unwrap_or_else(|p| p.into_inner());
        let time = now_ms();
        if delta_y != 0.0 {
            self.pointer.axis(
                time,
                wl_pointer::Axis::VerticalScroll,
                -(delta_y as f64) * SCROLL_STEP,
            );
        }
        if delta_x != 0.0 {
            self.pointer.axis(
                time,
                wl_pointer::Axis::HorizontalScroll,
                -(delta_x as f64) * SCROLL_STEP,
            );
        }
        self.pointer.frame();
        self.flush()
    }

    fn key(&self, key_code: u32, pressed: bool) -> Result<()> {
        let Some((evdev_code, needs_shift)) = self.keys.lookup(key_code) else {
            // Untranslatable keysym for the compiled US layout: skip
            // rather than fail the whole drain loop over one key (see
            // KeyLookup's doc comment).
            tracing::warn!(
                key_code,
                "no keycode mapping for keysym; dropping key event"
            );
            return Ok(());
        };

        let _guard = self.lock.lock().unwrap_or_else(|p| p.into_inner());
        let time = now_ms();
        let state = if pressed { 1 } else { 0 };

        // Best-effort shift handling for the common case of one
        // shifted key at a time (T-302 MVP scope): press Shift just
        // before the key goes down, release it just after the key
        // comes back up. Concurrent multi-key shifted chords from the
        // remote peer are not modeled.
        if needs_shift && pressed {
            self.keyboard.modifiers(self.keys.shift_mod_mask, 0, 0, 0);
        }
        self.keyboard.key(time, evdev_code, state);
        if needs_shift && !pressed {
            self.keyboard.modifiers(0, 0, 0, 0);
        }
        self.flush()
    }
}

fn now_ms() -> u32 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u32)
        .unwrap_or(0)
}

/// Serializes the compiled keymap into an anonymous, sealed-size
/// memory-backed file (`memfd_create`) and uploads it via
/// `zwp_virtual_keyboard_v1::keymap()`, as required before any `key()`
/// request can be sent.
fn upload_keymap(keyboard: &ZwpVirtualKeyboardV1, keymap_text: &str) -> Result<()> {
    // The wire format wants a NUL-terminated keymap string.
    let mut bytes = keymap_text.as_bytes().to_vec();
    bytes.push(0);

    let fd = rustix::fs::memfd_create("connectible-keymap", rustix::fs::MemfdFlags::CLOEXEC)
        .map_err(|e| DaemonError::Input(format!("memfd_create failed: {e}")))?;
    rustix::fs::ftruncate(&fd, bytes.len() as u64)
        .map_err(|e| DaemonError::Input(format!("ftruncate on keymap memfd failed: {e}")))?;

    let mut written = 0usize;
    while written < bytes.len() {
        let n = rustix::io::write(&fd, &bytes[written..])
            .map_err(|e| DaemonError::Input(format!("failed to write keymap memfd: {e}")))?;
        if n == 0 {
            return Err(DaemonError::Input(
                "short write while uploading keymap to memfd".to_string(),
            ));
        }
        written += n;
    }

    // format = 1 (XKB_V1), matching xkb::KEYMAP_FORMAT_TEXT_V1 above.
    keyboard.keymap(1, fd.as_fd(), bytes.len() as u32);
    Ok(())
}

impl Dispatch<wl_registry::WlRegistry, ()> for BootstrapState {
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
            "zwlr_virtual_pointer_manager_v1" if state.pointer_manager.is_none() => {
                state.pointer_manager = Some(registry.bind::<ZwlrVirtualPointerManagerV1, _, _>(
                    name,
                    version.min(2),
                    qh,
                    (),
                ));
            }
            "zwp_virtual_keyboard_manager_v1" if state.keyboard_manager.is_none() => {
                state.keyboard_manager = Some(registry.bind::<ZwpVirtualKeyboardManagerV1, _, _>(
                    name,
                    version.min(1),
                    qh,
                    (),
                ));
            }
            "wl_seat" if state.seat.is_none() => {
                state.seat =
                    Some(registry.bind::<wl_seat::WlSeat, _, _>(name, version.min(1), qh, ()));
            }
            // Only the first output is tracked; multi-monitor-accurate
            // targeting is out of MVP scope (see WaylandInputBackend's
            // `output_size` doc comment).
            "wl_output" if state.output.is_none() => {
                state.output =
                    Some(registry.bind::<wl_output::WlOutput, _, _>(name, version.min(2), qh, ()));
            }
            _ => {}
        }
    }
}

impl Dispatch<ZwlrVirtualPointerManagerV1, ()> for BootstrapState {
    fn event(
        _: &mut Self,
        _: &ZwlrVirtualPointerManagerV1,
        _: wayland_protocols_wlr::virtual_pointer::v1::client::zwlr_virtual_pointer_manager_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        // No events.
    }
}

impl Dispatch<ZwlrVirtualPointerV1, ()> for BootstrapState {
    fn event(
        _: &mut Self,
        _: &ZwlrVirtualPointerV1,
        _: wayland_protocols_wlr::virtual_pointer::v1::client::zwlr_virtual_pointer_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        // No events.
    }
}

impl Dispatch<ZwpVirtualKeyboardManagerV1, ()> for BootstrapState {
    fn event(
        _: &mut Self,
        _: &ZwpVirtualKeyboardManagerV1,
        _: wayland_protocols_misc::zwp_virtual_keyboard_v1::client::zwp_virtual_keyboard_manager_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        // No events.
    }
}

impl Dispatch<ZwpVirtualKeyboardV1, ()> for BootstrapState {
    fn event(
        _: &mut Self,
        _: &ZwpVirtualKeyboardV1,
        _: wayland_protocols_misc::zwp_virtual_keyboard_v1::client::zwp_virtual_keyboard_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        // No events.
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for BootstrapState {
    fn event(
        _: &mut Self,
        _: &wl_seat::WlSeat,
        _: wl_seat::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        // Capability events are irrelevant; we only need the object id.
    }
}

impl Dispatch<wl_output::WlOutput, ()> for BootstrapState {
    fn event(
        state: &mut Self,
        _: &wl_output::WlOutput,
        event: wl_output::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let wl_output::Event::Mode {
            width,
            height,
            flags,
            ..
        } = event
        {
            let is_current =
                matches!(flags, WEnum::Value(f) if f.contains(wl_output::Mode::Current));
            if is_current || state.output_size.is_none() {
                state.output_size = Some((width as u32, height as u32));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// T-302: the reverse keysym -> keycode lookup must resolve basic
    /// printable ASCII (letters, digits) for the compiled US layout, or
    /// remote key events could never actually type anything. This test
    /// requires libxkbcommon's data files (xkeyboard-config) to be
    /// installed, same as any real desktop session running this
    /// backend, so it is skipped (not failed) when compilation fails
    /// in a minimal CI container without them.
    #[test]
    fn keysym_lookup_resolves_common_ascii_keys() {
        let Ok((keys, _keymap_text)) = KeyLookup::build() else {
            eprintln!("skipping: no XKB keymap data available in this environment");
            return;
        };

        // XK_a = 0x0061, XK_1 = 0x0031, XK_space = 0x0020.
        assert!(keys.lookup(0x0061).is_some(), "lowercase 'a' must resolve");
        assert!(keys.lookup(0x0031).is_some(), "digit '1' must resolve");
        assert!(keys.lookup(0x0020).is_some(), "space must resolve");

        // XK_A = 0x0041 (shifted 'a') should resolve to the same
        // physical key as 'a', with needs_shift set.
        let (lower_code, lower_shift) = keys.lookup(0x0061).unwrap();
        let (upper_code, upper_shift) = keys.lookup(0x0041).unwrap();
        assert_eq!(
            lower_code, upper_code,
            "shift level shares the same physical key"
        );
        assert!(!lower_shift, "lowercase must not require shift");
        assert!(upper_shift, "uppercase must require shift");
    }

    #[test]
    fn unmapped_keysym_returns_none() {
        let Ok((keys, _keymap_text)) = KeyLookup::build() else {
            eprintln!("skipping: no XKB keymap data available in this environment");
            return;
        };
        // 0xdead_beef is not a valid keysym in any layout.
        assert!(keys.lookup(0xdead_beef).is_none());
    }
}
