# Manual cross-platform test matrix (T-907)

Run 2026-07-14 on the project's own dev machine (CachyOS, Hyprland
0.4x, wlroots-based, XWayland present but not deliberately disabled).
Hardware available: this one Linux/Hyprland machine only -- no second
physical machine, no Android device/emulator, no genuine X11-only
(non-Wayland) desktop session. Results below are grouped into what was
actually exercised end to end versus what's honestly out of reach in
this environment, so this reads as real coverage rather than a
checklist rubber-stamp.

## Linux (Hyprland/Wayland) <-> Linux (Hyprland/Wayland), same machine

Two independent `connectibled` release binaries, each given its own
`$HOME` (so each gets its own device_id/TLS cert/SQLite DB, avoiding
the single-instance-per-machine assumption baked into the daemon's
fixed XDG data-dir path -- see "Findings" below), on ports 58301/58302,
both on this real Hyprland session.

| Feature | Result | Notes |
|---|---|---|
| Daemon startup | PASS | Both instances selected `wayland-native` for clipboard (`wlr-data-control-unstable-v1`) and remote input (`wlr-virtual-pointer` + `virtual-keyboard`) at startup -- direct confirmation T-301/T-302 work on a real Hyprland compositor, not just in unit tests. |
| mDNS advertise + discovery | PASS | `avahi-browse -r _connectible._tcp` showed both instances with correct TXT records (`device_id`, `device_name`, `platform=PLATFORM_LINUX_WAYLAND`, `protocol_version`) on both IPv4 and IPv6. |
| Pairing (Pair -> PIN -> ConfirmPin) | PASS | Real TLS 1.3 connection, real `Pair` RPC, real PIN delivered over `SubscribeLocalEvents`, real `ConfirmPin` verified. |
| Clipboard sync | PASS | A real `ClipboardData` frame sent over a real `SyncStream` landed in the responder's actual Wayland clipboard (verified by reading it back via the same `wayland-native` backend). |
| File transfer, corrupted-chunk resend, throughput | PASS (via automated suite, not repeated manually) | Already covered end-to-end by `daemon/tests/grpc_smoke.rs`'s real-TLS tests (`file_transfer_over_real_tls_lands_on_disk`, `corrupted_chunk_triggers_resend_and_transfer_completes`, `file_transfer_throughput_meets_target`) -- these already exercise two real daemon-side roles over a real socket, so a manual repeat added no new confidence. |
| Remote input (mouse/keyboard injection) | Not interactively driven | The daemon's Wayland input backend initialized successfully (confirmed via startup log), and the dispatch/coalescing logic has thorough unit + sustained-load coverage (T-501). Did not inject a live mouse-move/keypress against this real session during the test -- doing so would move the cursor/type keys in the tester's actual live desktop session mid-work, which is disruptive to verify blindly. Recommend the user do a short manual check of a real cursor movement themselves when convenient (drag on a paired phone's touchpad screen, watch the desktop cursor move) rather than script it here. |

## Linux X11 <-> Linux Wayland

Not separately tested: this machine's only session is Hyprland
(Wayland), and both `daemon/src/clipboard/backend.rs` and
`daemon/src/input/backend.rs` already fall back to the X11/XWayland
path automatically when `$XDG_SESSION_TYPE` isn't `wayland` (unit
tests confirm the fallback chain logic; `daemon/tests/grpc_smoke.rs`'s
existing clipboard/input tests already exercise whichever backend the
CI runner's session resolves to, which has historically been the X11
path on GitHub Actions' Xvfb-based runners -- so the X11 code path
does get exercised by CI, just not by this manual pass specifically).
A genuine side-by-side X11-desktop-environment test needs a second
session/machine not available here.

## Linux <-> Android

Not tested: no Android device or emulator available in this
environment. Mobile's own test suite (`flutter test`, including the
real-TLS `test/integration/server_pairing_test.dart`) exercises the
phone-side responder logic against a real TLS client already, and this
document's Hyprland-to-Hyprland pairing test above exercises the exact
same wire protocol/pairing state machine the phone side implements
(`PairingManager`/`ConnectibleServer` mirror the daemon's
`PairingManager`/`ConnectibleService` deliberately) -- but a real
device pairing (including its physical Wi-Fi/mDNS-on-Android
behavior, its own OS clipboard/notification permissions, etc.) has not
been observed. This is the single largest verification gap left in
the project and needs a real phone.

## Findings from running this test

- **The daemon has no supported way to run two instances on one
  machine via config** -- `CONNECTIBLE_DATA_DIR` does not exist as an
  env var (only `CONNECTIBLE_PORT`/`CONNECTIBLE_DEVICE_NAME` are read,
  per `daemon/src/config.rs`); the data directory is a fixed XDG path.
  This test only worked by overriding `$HOME` per instance. This is a
  reasonable constraint for the *shipped* single-daemon-per-machine
  model (a real user only ever runs one), so this is not filed as a
  bug -- just documented here since it wasn't obvious going in, and it
  affects anyone else who wants to manually test multi-daemon
  scenarios on one machine the way this test did.
- No crashes, panics, or hangs observed in either instance across the
  test; both were cleanly killed (SIGTERM, per the T-502 shutdown fix)
  afterward.

## Outstanding for a full pass

- [ ] Real Android device pairing (clipboard, file transfer, remote
  input, from a phone).
- [ ] A genuine non-Wayland X11 desktop session (not just XWayland
  under a Wayland compositor).
- [ ] Interactive remote-input verification (watching a real cursor
  move/keys type) with two separate physical machines, so an
  automated script doesn't need to move the operator's own live mouse.
