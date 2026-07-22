//! Process-level shutdown test (T-502): spawns the actual compiled
//! `connectibled` binary (not an in-process runtime the way
//! grpc_smoke.rs's tests do) and sends it a real SIGTERM, asserting
//! the *whole process* exits within a bounded time.
//!
//! This is the only test in the suite that would have caught a real
//! bug found while measuring startup/idle resource usage: the
//! `discovery::spawn_browser` background task blocked forever reading
//! mDNS events because `mdns_sd::ServiceDaemon`'s worker thread is not
//! tied to any handle's lifetime and nothing ever called
//! `.shutdown()` on it. `run()` itself returned fine and the
//! `shutdown_signal()` future resolved correctly (both already
//! covered by daemon/src/lib.rs's `shutdown_signal_resolves_on_sigterm`
//! unit test), but the *process* never exited: Tokio's `Runtime::drop`
//! (invoked implicitly at the end of `#[tokio::main]`) blocks
//! indefinitely waiting for every `spawn_blocking` task to finish,
//! including one that will never return on its own. Only a real
//! subprocess test observes that outcome; an in-process test harness
//! sharing a runtime with the test itself does not.

use std::io::Read;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

#[test]
fn daemon_process_exits_promptly_after_sigterm() {
    let bin = env!("CARGO_BIN_EXE_connectibled");
    let data_dir = tempfile::tempdir().expect("tempdir");
    let port = {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
        listener.local_addr().expect("local addr").port()
    };

    let mut child = Command::new(bin)
        .env("CONNECTIBLE_DATA_DIR", data_dir.path())
        .env("CONNECTIBLE_PORT", port.to_string())
        .env("RUST_LOG", "warn")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn connectibled");

    // Give it a moment to finish starting (mDNS advertise, TLS cert
    // load/generation, gRPC listener bind) before signaling.
    std::thread::sleep(Duration::from_millis(800));

    let pid = child.id() as i32;
    let sigterm_sent_at = Instant::now();
    let status = Command::new("kill")
        .args(["-TERM", &pid.to_string()])
        .status()
        .expect("invoke kill(1)");
    assert!(status.success(), "kill -TERM did not succeed");

    // Poll rather than a single blocking `child.wait()` so the test
    // itself has a hard bound instead of hanging forever if this
    // regresses -- 5s is generous relative to the ~0.1s this takes
    // once mDNS shutdown is wired correctly.
    let deadline = Duration::from_secs(5);
    loop {
        if let Some(exit_status) = child.try_wait().expect("try_wait") {
            let elapsed = sigterm_sent_at.elapsed();
            assert!(
                exit_status.success() || exit_status.code() == Some(0),
                "daemon should exit 0 on graceful SIGTERM shutdown, got {exit_status:?}"
            );
            assert!(
                elapsed < Duration::from_secs(2),
                "daemon took {elapsed:?} to exit after SIGTERM, expected well under 2s"
            );
            return;
        }
        if sigterm_sent_at.elapsed() > deadline {
            let _ = child.kill();
            let mut stderr = String::new();
            if let Some(mut s) = child.stderr.take() {
                let _ = s.read_to_string(&mut stderr);
            }
            panic!(
                "daemon did not exit within {deadline:?} of SIGTERM (stderr tail: {})",
                &stderr[stderr.len().saturating_sub(2000)..]
            );
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}
