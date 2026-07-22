//! Small, dependency-free fixed-window rate limiter (Phase C / T-C6..C8).
//!
//! One reusable primitive backs every "a flood of X must not exhaust us"
//! defense: per-IP connection accepts (T-C8), per-peer `PrepareUpload`
//! (T-C7), and mDNS advertised-record processing (T-C6). It is deliberately
//! a fixed window (not a token bucket): simpler to reason about, and for
//! DoS *bounding* the small burst-at-a-window-boundary imprecision is
//! irrelevant -- we only care that a key cannot exceed ~`max_events` per
//! `window` indefinitely.
//!
//! Memory is bounded (RULES.md): entries are pruned lazily whenever the map
//! would exceed `max_keys`, evicting windows that have already elapsed
//! first, so a flood of *distinct* keys (spoofed source IPs, random peer
//! ids) cannot grow the map without limit either.

use std::collections::HashMap;
use std::hash::Hash;
use std::sync::Mutex;
use std::time::{Duration, Instant};

struct Window {
    /// Start of the current counting window.
    started_at: Instant,
    /// Events observed since `started_at`.
    count: u32,
}

/// A fixed-window rate limiter keyed by `K`. Cheap to clone-share behind an
/// `Arc`. All methods are non-blocking and lock only briefly.
pub struct RateLimiter<K: Eq + Hash + Clone> {
    inner: Mutex<HashMap<K, Window>>,
    max_events: u32,
    window: Duration,
    max_keys: usize,
}

impl<K: Eq + Hash + Clone> RateLimiter<K> {
    /// Allows up to `max_events` per `window` per key; tracks at most
    /// `max_keys` distinct keys before pruning elapsed ones.
    pub fn new(max_events: u32, window: Duration, max_keys: usize) -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
            max_events,
            window,
            max_keys,
        }
    }

    /// Records an event for `key` and returns `true` if it is within the
    /// limit, `false` if the key has exhausted its window (caller should
    /// drop/reject the event). Uses the real clock.
    pub fn check(&self, key: K) -> bool {
        self.check_at(key, Instant::now())
    }

    /// [`check`](Self::check) with an explicit `now`, for deterministic
    /// tests.
    pub fn check_at(&self, key: K, now: Instant) -> bool {
        let mut map = self.inner.lock().unwrap_or_else(|p| p.into_inner());

        match map.get_mut(&key) {
            Some(w) if now.duration_since(w.started_at) < self.window => {
                if w.count >= self.max_events {
                    return false;
                }
                w.count += 1;
                true
            }
            // Missing, or the previous window has fully elapsed: (re)start.
            Some(w) => {
                w.started_at = now;
                w.count = 1;
                true
            }
            None => {
                if map.len() >= self.max_keys {
                    prune_elapsed(&mut map, now, self.window);
                }
                map.insert(
                    key,
                    Window {
                        started_at: now,
                        count: 1,
                    },
                );
                true
            }
        }
    }
}

/// Drops every entry whose window has fully elapsed. If that frees nothing
/// (every key is actively within its window -- i.e. a genuine distinct-key
/// flood), the map is cleared entirely: dropping live windows only *resets*
/// some counters, which is a safe over-admission, never an unbounded grow.
fn prune_elapsed<K: Eq + Hash + Clone>(
    map: &mut HashMap<K, Window>,
    now: Instant,
    window: Duration,
) {
    let before = map.len();
    map.retain(|_, w| now.duration_since(w.started_at) < window);
    if map.len() == before {
        map.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_up_to_the_limit_then_blocks_within_a_window() {
        let rl = RateLimiter::new(3, Duration::from_secs(10), 100);
        let t0 = Instant::now();
        assert!(rl.check_at("a", t0));
        assert!(rl.check_at("a", t0 + Duration::from_millis(1)));
        assert!(rl.check_at("a", t0 + Duration::from_millis(2)));
        // 4th within the window is rejected.
        assert!(!rl.check_at("a", t0 + Duration::from_millis(3)));
    }

    #[test]
    fn window_rollover_resets_the_count() {
        let rl = RateLimiter::new(2, Duration::from_secs(10), 100);
        let t0 = Instant::now();
        assert!(rl.check_at("a", t0));
        assert!(rl.check_at("a", t0 + Duration::from_secs(1)));
        assert!(!rl.check_at("a", t0 + Duration::from_secs(2)));
        // After the window fully elapses, the key is fresh again.
        assert!(rl.check_at("a", t0 + Duration::from_secs(11)));
        assert!(rl.check_at("a", t0 + Duration::from_secs(12)));
        assert!(!rl.check_at("a", t0 + Duration::from_secs(13)));
    }

    #[test]
    fn keys_are_limited_independently() {
        let rl = RateLimiter::new(1, Duration::from_secs(10), 100);
        let t0 = Instant::now();
        assert!(rl.check_at("a", t0));
        assert!(!rl.check_at("a", t0));
        // A different key has its own budget.
        assert!(rl.check_at("b", t0));
        assert!(!rl.check_at("b", t0));
    }

    #[test]
    fn distinct_key_flood_stays_memory_bounded() {
        let rl = RateLimiter::new(5, Duration::from_secs(10), 8);
        let t0 = Instant::now();
        // 100 distinct keys, all within one window, must never grow the map
        // past max_keys.
        for i in 0..100 {
            assert!(rl.check_at(i, t0));
            let len = rl.inner.lock().unwrap().len();
            assert!(len <= 8, "map grew to {len}, expected <= 8");
        }
    }

    #[test]
    fn elapsed_entries_are_pruned_before_clearing() {
        let rl = RateLimiter::new(5, Duration::from_secs(10), 2);
        let t0 = Instant::now();
        rl.check_at("old", t0);
        // "old"'s window elapses; inserting two fresh keys past capacity
        // should evict "old" rather than clear everything.
        assert!(rl.check_at("new1", t0 + Duration::from_secs(11)));
        assert!(rl.check_at("new2", t0 + Duration::from_secs(11)));
        let map = rl.inner.lock().unwrap();
        assert!(!map.contains_key("old"));
        assert!(map.contains_key("new1") && map.contains_key("new2"));
    }
}
