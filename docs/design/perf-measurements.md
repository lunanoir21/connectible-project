# Performance measurements (Phase 5)

Measured on this dev machine (CachyOS/Hyprland, release build,
`cargo build --release -p connectibled`) on 2026-07-14.

## T-502: idle RSS

RULES.md target: daemon idle RSS under 30MB with no active
transfers/streams.

Measured via `ps -o rss` on the release binary, 3s after startup
(mDNS advertise + TLS cert load + Wayland clipboard/input backend
init all complete) and again at 10s (settled idle):

```
RSS at 3s:  11492 KB (~11.2 MB)
RSS at 10s: 11492 KB (~11.2 MB)
```

**Result: PASS**, well under the 30MB target with meaningful headroom
(~63% below target). No follow-up optimization needed. RSS was
identical at 3s and 10s, confirming no slow leak during idle (a real
leak would need a longer soak to rule out definitively, but this is
consistent with the poison-safe, bounded-queue design from Phases 2-3
having no obvious unbounded accumulation path).

## T-111/T-502 (found during this measurement, not planned): graceful
shutdown never actually exited the process

While measuring idle RSS, sending SIGTERM to the daemon logged
"received SIGTERM, starting graceful shutdown" (confirming
`shutdown_signal()` fires) but the **process never exited** -- it
stayed alive indefinitely. Root cause: `discovery::spawn_browser`
(daemon/src/discovery/mod.rs) runs a `tokio::task::spawn_blocking`
loop reading `mdns_sd::ServiceDaemon::browse()`'s channel with a plain
blocking `receiver.recv()`. `ServiceDaemon` is a cheap `Clone` handle
onto a background thread that is *not* tied to any particular handle's
lifetime -- dropping it does not stop the thread or close the browse
channel, only an explicit `.shutdown()` call does. Since nothing
called `.shutdown()`, that `recv()` blocked forever, and Tokio's
`Runtime::drop()` (invoked implicitly at the end of `#[tokio::main]`,
after `run()` returns) blocks the whole process indefinitely waiting
for every outstanding `spawn_blocking` task to finish -- including one
that can never return on its own.

Fixed in daemon/src/lib.rs: `run()` now keeps a clone of the
`ServiceDaemon` handle and calls `.shutdown()` on it (with a 2s bound)
after `serve_with_incoming_shutdown` completes, closing the browse
channel so the blocking task's `recv()` returns `Err` and the task
exits, letting the process actually terminate.

Before fix: process never exited (observed hanging for 2+ minutes
before being force-killed by the test harness).
After fix: process exits ~0.1s after SIGTERM.

Regression test: `daemon/tests/process_shutdown.rs`
(`daemon_process_exits_promptly_after_sigterm`) spawns the actual
compiled binary (not an in-process runtime the way grpc_smoke.rs's
tests do) and asserts real-process exit within 2s of SIGTERM -- the
only test shape that would have caught this, since the pre-existing
`shutdown_signal_resolves_on_sigterm` unit test only checked that the
*future* resolves, not that the whole process actually terminates
afterward.

## T-501: bounded input queue under sustained load

See `daemon/src/input/mod.rs`'s
`sustained_mixed_load_stays_bounded_and_preserves_key_order` test:
2000 events (200/sec x 10s equivalent, 4:1 move:key mix) enqueued with
interleaved draining at irregular intervals. Queue length never
exceeded the `MAX_QUEUED_NON_MOVE_EVENTS` (256) bound at any point,
every key event was applied in order with none evicted, and the queue
fully drained (zero backlog) once enqueueing stopped -- confirming no
added dispatch lag under sustained mixed load.

## T-503: mDNS re-advertisement on network interface change

No code change needed -- `discovery::advertise()` already calls
`.enable_addr_auto()` on the `ServiceInfo` it registers. Verified by
reading the `mdns-sd` crate's own event loop
(`service_daemon.rs`'s main loop calls `check_ip_changes()` every
`IP_CHECK_INTERVAL_IN_SECS_DEFAULT` = 5 seconds, which adds/removes
addresses on any `addr_auto`-enabled service as host interfaces come
and go), independent of anything this daemon does. A real interface
up/down cycle isn't practical to simulate in an automated test, so
this is a code-inspection verification, documented inline at the
`advertise()` call site in daemon/src/discovery/mod.rs.

## T-504: file transfer throughput

RULES.md target: sustain >=20MB/s over loopback/local LAN.

Measured via `daemon/tests/grpc_smoke.rs`'s
`file_transfer_throughput_meets_target` (a real 64MB file sent over an
actual TLS 1.3 SyncStream, chunked/CRC32'd/hashed exactly like
production traffic):

```
cargo test (debug):    20.3 - 23.2 MB/s across repeated runs
cargo test --release:  291.9 MB/s
```

**Result: PASS.** The release-mode figure (which is what an actual
shipped build does) clears the target by ~15x, confirming chunking/
buffering is not the bottleneck -- exactly RULES.md's framing
("network/disk may be [the bottleneck]", not the chunking logic
itself). The debug-build number sits close to the 20MB/s line purely
from unoptimized CRC32/SHA-256 costs, which is why the automated
test's asserted floor is set much lower (5MB/s) to avoid CI flakiness
on slower runners while still catching a genuine regression (e.g. an
accidental O(n^2) chunking path).
