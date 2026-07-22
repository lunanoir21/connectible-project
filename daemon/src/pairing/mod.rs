use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rand::RngCore;
use subtle::ConstantTimeEq;
use tokio::sync::broadcast;

use crate::error::{DaemonError, Result};

pub const PIN_TTL: Duration = Duration::from_secs(30);
const MAX_ATTEMPTS: u32 = 3;

/// T-403: minimum interval between two *fresh* PINs generated for the
/// same requester, so a peer that keeps calling `Pair` (e.g. after
/// each lockout, or just repeatedly) can't keep re-popping the local
/// PIN dialog. Deliberately short relative to human-scale PIN entry
/// (which takes several seconds regardless) so it only blunts a rapid
/// automated burst, not a genuine "let me try that again" retry.
const PAIR_COOLDOWN: Duration = Duration::from_secs(5);

/// Draws one uniformly-random ASCII digit '0'..'9' via rejection
/// sampling (T-404). 256 is not a multiple of 10, so a plain `byte %
/// 10` is slightly biased toward digits 0-5 (26/256 vs 25/256 for
/// 6-9); rejecting bytes >= 250 (the largest multiple of 10 that fits
/// in a byte) and redrawing removes that bias entirely. The reject
/// probability per draw is 6/256 (~2.3%), so this terminates in O(1)
/// expected draws.
fn digit_from_rng(rng: &mut impl RngCore, out: &mut u8) {
    loop {
        let mut b = [0u8; 1];
        rng.fill_bytes(&mut b);
        if b[0] < 250 {
            *out = b'0' + (b[0] % 10);
            return;
        }
    }
}

struct PendingPin {
    code: [u8; 6], // ASCII digits '0'..'9'
    requester_device_name: String,
    expires_at_ms: i64,
    attempts: u32,
}

/// Event emitted to local UI subscribers (desktop/mobile) the moment a
/// `PairRequest` arrives, so the PIN dialog can be shown immediately
/// (T-014).
///
/// Carries the plaintext PIN because the whole point of the dialog is
/// for the local user to read the code aloud. This event only ever
/// travels in-process or over the loopback-gated SubscribeLocalEvents
/// RPC (see grpc/service.rs) -- it must never be forwarded to a remote
/// peer.
#[derive(Debug, Clone)]
pub struct PairingRequestedEvent {
    pub requester_device_id: String,
    pub requester_device_name: String,
    pub pin_code: String,
    pub pin_expires_at_ms: i64,
}

/// Tracks in-flight pairing PINs (T-011, T-012). PINs are never
/// persisted to disk -- they exist only for the 30-second window and
/// are purged from memory on success, expiry, or lockout.
pub struct PairingManager {
    pending: Mutex<HashMap<String, PendingPin>>,
    /// T-403: last time a *fresh* PIN was generated for a given
    /// requester device_id, keyed independently of `pending` so the
    /// cooldown still applies after a pending entry is cleared
    /// (lockout/expiry/success).
    last_created_ms: Mutex<HashMap<String, i64>>,
    events: broadcast::Sender<PairingRequestedEvent>,
}

impl Default for PairingManager {
    fn default() -> Self {
        let (events, _rx) = broadcast::channel(16);
        Self {
            pending: Mutex::new(HashMap::new()),
            last_created_ms: Mutex::new(HashMap::new()),
            events,
        }
    }
}

impl PairingManager {
    pub fn subscribe(&self) -> broadcast::Receiver<PairingRequestedEvent> {
        self.events.subscribe()
    }

    /// Generates a cryptographically random 6-digit PIN for the given
    /// requester and stores it with a 30-second expiry (T-011). Uses
    /// `rand::rngs::OsRng` (via `RngCore`), never a time-seeded PRNG.
    ///
    /// T-403: if a PIN is already pending (and not yet expired) for
    /// this requester, this is idempotent -- it returns the existing
    /// expiry without generating a new PIN or re-firing the local
    /// "pairing requested" event, so a repeated `Pair` call while a
    /// dialog is already showing doesn't pop a second one. Once a
    /// pending entry is cleared (success/lockout/expiry), a *fresh*
    /// PIN is subject to `PAIR_COOLDOWN`: calling again too soon
    /// returns `DaemonError::RateLimited` instead of silently looping.
    pub fn create_pending(
        &self,
        requester_device_id: &str,
        requester_device_name: &str,
    ) -> Result<i64> {
        let now = now_ms();

        {
            let pending = self
                .pending
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            if let Some(existing) = pending.get(requester_device_id) {
                if now <= existing.expires_at_ms {
                    return Ok(existing.expires_at_ms);
                }
            }
        }

        {
            let mut last_created = self
                .last_created_ms
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            if let Some(&last_ms) = last_created.get(requester_device_id) {
                if now - last_ms < PAIR_COOLDOWN.as_millis() as i64 {
                    return Err(DaemonError::RateLimited(format!(
                        "pairing requests from {requester_device_id} are throttled"
                    )));
                }
            }
            last_created.insert(requester_device_id.to_string(), now);
        }

        let mut rng = rand::rngs::OsRng;
        let mut digits = [0u8; 6];
        for digit in &mut digits {
            digit_from_rng(&mut rng, digit);
        }

        let expires_at_ms = now + PIN_TTL.as_millis() as i64;

        let mut pending = self
            .pending
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        pending.insert(
            requester_device_id.to_string(),
            PendingPin {
                code: digits,
                requester_device_name: requester_device_name.to_string(),
                expires_at_ms,
                attempts: 0,
            },
        );
        drop(pending);

        let _ = self.events.send(PairingRequestedEvent {
            requester_device_id: requester_device_id.to_string(),
            requester_device_name: requester_device_name.to_string(),
            pin_code: String::from_utf8_lossy(&digits).into_owned(),
            pin_expires_at_ms: expires_at_ms,
        });

        Ok(expires_at_ms)
    }

    /// Test/debug-only accessor for the generated PIN, so integration
    /// tests can drive a full pairing flow without a human reading a
    /// dialog. Never exposed over the wire.
    #[cfg(test)]
    pub fn peek_pin(&self, requester_device_id: &str) -> Option<String> {
        let pending = self.pending.lock().expect("pairing lock poisoned");
        pending
            .get(requester_device_id)
            .map(|p| String::from_utf8_lossy(&p.code).to_string())
    }

    /// Verifies a submitted PIN in constant time (T-012). On expiry,
    /// wrong-PIN lockout (3 attempts), or success, the pending entry is
    /// removed so a fresh `Pair` call is required to retry.
    pub fn confirm(&self, device_id: &str, submitted: &str) -> Result<()> {
        let mut pending = self
            .pending
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let entry = pending
            .get_mut(device_id)
            .ok_or(DaemonError::PairingRejected("no pending pairing".into()))?;

        if now_ms() > entry.expires_at_ms {
            pending.remove(device_id);
            return Err(DaemonError::PairingTimeout);
        }

        let submitted_bytes = submitted.as_bytes();
        let matches = submitted_bytes.len() == entry.code.len()
            && bool::from(submitted_bytes.ct_eq(&entry.code));

        if matches {
            pending.remove(device_id);
            // A successful pairing means the PAIR_COOLDOWN concern (a
            // peer spamming Pair without ever completing) is moot for
            // this device_id -- clear it so a legitimate later re-pair
            // (e.g. after being forgotten, T-307) isn't throttled by a
            // cooldown left over from this successful attempt.
            self.last_created_ms
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .remove(device_id);
            return Ok(());
        }

        entry.attempts += 1;
        if entry.attempts >= MAX_ATTEMPTS {
            pending.remove(device_id);
            return Err(DaemonError::PairingTimeout);
        }

        Err(DaemonError::InvalidPin)
    }

    pub fn requester_name(&self, device_id: &str) -> Option<String> {
        self.pending
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .get(device_id)
            .map(|p| p.requester_device_name.clone())
    }
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn correct_pin_within_window_verifies() {
        let manager = PairingManager::default();
        manager.create_pending("dev-a", "Anil's Phone").unwrap();
        let pin = manager.peek_pin("dev-a").expect("pin exists");
        assert!(manager.confirm("dev-a", &pin).is_ok());
    }

    #[test]
    fn wrong_pin_three_times_locks_out() {
        let manager = PairingManager::default();
        manager.create_pending("dev-b", "Some Device").unwrap();
        assert!(matches!(
            manager.confirm("dev-b", "000000").unwrap_err(),
            DaemonError::InvalidPin
        ));
        assert!(matches!(
            manager.confirm("dev-b", "000000").unwrap_err(),
            DaemonError::InvalidPin
        ));
        // third wrong attempt triggers early lockout (timeout-equivalent)
        assert!(matches!(
            manager.confirm("dev-b", "000000").unwrap_err(),
            DaemonError::PairingTimeout
        ));
        // pending entry is gone, correct pin no longer helps
        assert!(manager.confirm("dev-b", "123456").is_err());
    }

    #[test]
    fn digit_from_rng_is_uniformly_distributed() {
        // Statistical spot-check (T-404): with rejection sampling every
        // digit 0-9 should appear with roughly equal frequency across a
        // large sample. A plain `byte % 10` would skew digits 0-5 high
        // and 6-9 low; loose bounds here (a real 10% each, tolerating
        // +/-2%) catch that bias without making the test flaky.
        let mut rng = rand::rngs::OsRng;
        let mut counts = [0u32; 10];
        const SAMPLES: u32 = 100_000;
        for _ in 0..SAMPLES {
            let mut digit = 0u8;
            digit_from_rng(&mut rng, &mut digit);
            let value = (digit - b'0') as usize;
            assert!((0..10).contains(&value));
            counts[value] += 1;
        }
        let expected = SAMPLES as f64 / 10.0;
        for (value, &count) in counts.iter().enumerate() {
            let ratio = count as f64 / expected;
            assert!(
                (0.9..1.1).contains(&ratio),
                "digit {value} appeared {count} times, expected ~{expected} (ratio {ratio})"
            );
        }
    }

    #[test]
    fn pin_is_six_ascii_digits() {
        let manager = PairingManager::default();
        manager.create_pending("dev-c", "Some Device").unwrap();
        let pin = manager.peek_pin("dev-c").expect("pin exists");
        assert_eq!(pin.len(), 6);
        assert!(pin.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn confirm_with_no_pending_pairing_is_rejected() {
        let manager = PairingManager::default();
        assert!(manager.confirm("unknown-device", "123456").is_err());
    }

    #[test]
    fn repeated_pair_while_pending_is_idempotent_not_a_fresh_pin() {
        // T-403: calling create_pending again while a PIN is already
        // live for this requester must not generate a new PIN or fire
        // a second local event -- it just reports the same expiry.
        let manager = PairingManager::default();
        let first = manager.create_pending("dev-e", "Some Device").unwrap();
        let pin_before = manager.peek_pin("dev-e").unwrap();
        let second = manager.create_pending("dev-e", "Some Device").unwrap();
        let pin_after = manager.peek_pin("dev-e").unwrap();
        assert_eq!(first, second);
        assert_eq!(pin_before, pin_after);
    }

    #[test]
    fn fresh_pair_after_lockout_is_rate_limited_within_cooldown() {
        // T-403: once a pending PIN is cleared (lockout here), an
        // immediate new Pair call for the same requester is throttled
        // rather than silently popping another dialog.
        let manager = PairingManager::default();
        manager.create_pending("dev-f", "Some Device").unwrap();
        for _ in 0..MAX_ATTEMPTS {
            let _ = manager.confirm("dev-f", "000000");
        }
        // Pending entry is gone (lockout), but the cooldown since the
        // first create_pending is still active.
        assert!(matches!(
            manager.create_pending("dev-f", "Some Device").unwrap_err(),
            DaemonError::RateLimited(_)
        ));
    }

    #[tokio::test]
    async fn pairing_event_carries_the_pin_that_confirm_accepts() {
        let manager = PairingManager::default();
        let mut events = manager.subscribe();

        manager.create_pending("dev-d", "Event Device").unwrap();

        let event = events.recv().await.expect("pairing event");
        assert_eq!(event.requester_device_id, "dev-d");
        assert_eq!(event.requester_device_name, "Event Device");
        assert_eq!(event.pin_code.len(), 6);
        assert!(manager.confirm("dev-d", &event.pin_code).is_ok());
    }
}
