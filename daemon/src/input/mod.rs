mod backend;
mod wayland_backend;

pub use backend::{detect_backend, InputBackend, YdotoolBackend};
pub use wayland_backend::WaylandInputBackend;

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use crate::error::Result;
use crate::proto::connectible::v1::{InputEventType, MouseButton, RemoteInputEvent};

/// One coalesced/queued input action, applied in order by
/// `InputDispatcher::drain_and_apply` (T-030).
#[derive(Debug, Clone, PartialEq)]
enum QueuedEvent {
    Move { x: f32, y: f32 },
    Button { button: MouseButton, pressed: bool },
    Scroll { delta_x: f32, delta_y: f32 },
    Key { key_code: u32, pressed: bool },
}

/// Upper bound on the number of non-coalesced (Key/Button/Scroll)
/// events held in `InputDispatcher`'s queue at once (T-112). Move
/// events never count against this limit since they are coalesced
/// down to at most one entry regardless of burst size; Key/Button/
/// Scroll events arrive directly off the network and are not
/// coalesced, so without a bound a flooding peer could grow the queue
/// without limit. When the bound is hit the oldest queued non-move
/// event is dropped to make room for the new one: for input replay,
/// staleness is worse than a gap (an operator holding a key through a
/// flood cares far more about the *current* key state than about a
/// button transition that is now over a queue-length behind), and
/// drop-oldest keeps the drain loop applying data that is still
/// relevant instead of catching up on backlog that no longer matters.
const MAX_QUEUED_NON_MOVE_EVENTS: usize = 256;

/// Dispatches incoming `RemoteInputEvent` frames to an `InputBackend`
/// (T-030). Rapid mouse-move events are coalesced -- if the most
/// recently queued event is *also* an unapplied move, it is replaced
/// in place rather than appended -- so a burst of movement never grows
/// the queue unbounded and never delays key/button events queued
/// after it. Key and button events are always preserved individually
/// and applied in the order they were enqueued, so press/release
/// ordering is never reordered by coalescing, but their count is
/// bounded by `MAX_QUEUED_NON_MOVE_EVENTS` (T-112) since, unlike
/// moves, they cannot be collapsed into a single entry.
pub struct InputDispatcher {
    backend: Arc<dyn InputBackend>,
    queue: Mutex<VecDeque<QueuedEvent>>,
    /// Gate for T-309's "disable remote input" toggle: when false,
    /// `enqueue` drops incoming events immediately instead of queuing
    /// them, so a re-enable does not suddenly replay a backlog of
    /// input that accumulated while disabled. Defaults to enabled so
    /// existing behavior (and every test below) is unchanged unless a
    /// caller explicitly disables it.
    enabled: AtomicBool,
}

impl InputDispatcher {
    pub fn new(backend: Arc<dyn InputBackend>) -> Self {
        Self {
            backend,
            queue: Mutex::new(VecDeque::new()),
            enabled: AtomicBool::new(true),
        }
    }

    pub fn queue_len(&self) -> usize {
        self.queue
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .len()
    }

    /// Whether incoming `RemoteInputEvent` frames are currently applied
    /// (T-309). Read by `GetLocalState` and defaults to true.
    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    /// Flips the T-309 dispatch gate. Disabling does not clear
    /// already-queued events (the drain loop still applies whatever was
    /// queued before the toggle flipped); it only stops new incoming
    /// events from being queued.
    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Relaxed);
    }

    /// Enqueues one incoming wire event, translating the proto's flat
    /// `RemoteInputEvent` shape into a `QueuedEvent` and coalescing
    /// consecutive moves. A no-op while disabled (T-309): the event is
    /// dropped rather than queued, so incoming `RemoteInputEvent`
    /// frames are ignored end-to-end while remote input is turned off.
    pub fn enqueue(&self, event: &RemoteInputEvent) {
        if !self.is_enabled() {
            return;
        }

        let queued =
            match InputEventType::try_from(event.r#type).unwrap_or(InputEventType::Unspecified) {
                InputEventType::MouseMove => QueuedEvent::Move {
                    x: event.x,
                    y: event.y,
                },
                InputEventType::MouseButton => QueuedEvent::Button {
                    button: MouseButton::try_from(event.button).unwrap_or(MouseButton::Unspecified),
                    pressed: event.pressed,
                },
                InputEventType::MouseScroll => QueuedEvent::Scroll {
                    delta_x: event.scroll_delta_x,
                    delta_y: event.scroll_delta_y,
                },
                InputEventType::Key => QueuedEvent::Key {
                    key_code: event.key_code,
                    pressed: event.key_pressed,
                },
                InputEventType::Unspecified => return,
            };

        let mut queue = self
            .queue
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let should_coalesce = matches!(
            (&queued, queue.back()),
            (QueuedEvent::Move { .. }, Some(QueuedEvent::Move { .. }))
        );
        if should_coalesce {
            *queue.back_mut().expect("checked non-empty above") = queued;
            return;
        }

        // Move events are self-limiting (coalesced above), but Key/
        // Button/Scroll events are not, so a flooding peer sending only
        // those could otherwise grow the queue without bound (T-112).
        // If we are at capacity, drop the oldest queued non-move event
        // to make room: with this many events backlogged the drain loop
        // is already falling behind, and applying the most recent state
        // is more useful than working through stale backlog.
        if !matches!(queued, QueuedEvent::Move { .. }) {
            let non_move_count = queue
                .iter()
                .filter(|e| !matches!(e, QueuedEvent::Move { .. }))
                .count();
            if non_move_count >= MAX_QUEUED_NON_MOVE_EVENTS {
                if let Some(pos) = queue
                    .iter()
                    .position(|e| !matches!(e, QueuedEvent::Move { .. }))
                {
                    queue.remove(pos);
                }
            }
        }
        queue.push_back(queued);
    }

    /// Applies every currently-queued event, in order, to the backend.
    /// Stops and propagates the first backend error (later events stay
    /// queued for the caller to retry or drop as it sees fit).
    pub fn drain_and_apply(&self) -> Result<()> {
        loop {
            let next = self
                .queue
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .pop_front();
            let Some(event) = next else { break };
            self.apply(&event)?;
        }
        Ok(())
    }

    fn apply(&self, event: &QueuedEvent) -> Result<()> {
        match event {
            QueuedEvent::Move { x, y } => self.backend.mouse_move(*x, *y),
            QueuedEvent::Button { button, pressed } => self.backend.mouse_button(*button, *pressed),
            QueuedEvent::Scroll { delta_x, delta_y } => self.backend.scroll(*delta_x, *delta_y),
            QueuedEvent::Key { key_code, pressed } => self.backend.key(*key_code, *pressed),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex as StdMutex;

    #[derive(Debug, PartialEq, Clone)]
    enum Applied {
        Move(f32, f32),
        Button(MouseButton, bool),
        Scroll(f32, f32),
        Key(u32, bool),
    }

    #[derive(Default)]
    struct RecordingBackend {
        applied: StdMutex<Vec<Applied>>,
    }

    impl InputBackend for RecordingBackend {
        fn mouse_move(&self, x: f32, y: f32) -> Result<()> {
            self.applied.lock().unwrap().push(Applied::Move(x, y));
            Ok(())
        }
        fn mouse_button(&self, button: MouseButton, pressed: bool) -> Result<()> {
            self.applied
                .lock()
                .unwrap()
                .push(Applied::Button(button, pressed));
            Ok(())
        }
        fn scroll(&self, delta_x: f32, delta_y: f32) -> Result<()> {
            self.applied
                .lock()
                .unwrap()
                .push(Applied::Scroll(delta_x, delta_y));
            Ok(())
        }
        fn key(&self, key_code: u32, pressed: bool) -> Result<()> {
            self.applied
                .lock()
                .unwrap()
                .push(Applied::Key(key_code, pressed));
            Ok(())
        }
    }

    fn move_event(x: f32, y: f32) -> RemoteInputEvent {
        RemoteInputEvent {
            r#type: InputEventType::MouseMove as i32,
            x,
            y,
            button: 0,
            pressed: false,
            scroll_delta_x: 0.0,
            scroll_delta_y: 0.0,
            key_code: 0,
            key_pressed: false,
            modifiers: 0,
        }
    }

    fn key_event(key_code: u32, pressed: bool) -> RemoteInputEvent {
        RemoteInputEvent {
            r#type: InputEventType::Key as i32,
            x: 0.0,
            y: 0.0,
            button: 0,
            pressed: false,
            scroll_delta_x: 0.0,
            scroll_delta_y: 0.0,
            key_code,
            key_pressed: pressed,
            modifiers: 0,
        }
    }

    #[test]
    fn rapid_moves_coalesce_into_a_single_queued_event() {
        let backend = Arc::new(RecordingBackend::default());
        let dispatcher = InputDispatcher::new(backend.clone());

        for i in 0..200 {
            dispatcher.enqueue(&move_event(i as f32 / 200.0, 0.5));
        }

        assert_eq!(
            dispatcher.queue_len(),
            1,
            "200 consecutive moves must coalesce to 1 queued event"
        );
        dispatcher.drain_and_apply().unwrap();
        assert_eq!(backend.applied.lock().unwrap().len(), 1);
    }

    #[test]
    fn key_events_are_never_coalesced_and_preserve_order() {
        let backend = Arc::new(RecordingBackend::default());
        let dispatcher = InputDispatcher::new(backend.clone());

        dispatcher.enqueue(&move_event(0.1, 0.1));
        dispatcher.enqueue(&key_event(30, true));
        dispatcher.enqueue(&move_event(0.2, 0.2));
        dispatcher.enqueue(&move_event(0.3, 0.3));
        dispatcher.enqueue(&key_event(30, false));

        // move, move+move coalesced, key, key = 4 queued (not 5)
        assert_eq!(dispatcher.queue_len(), 4);

        dispatcher.drain_and_apply().unwrap();
        let applied = backend.applied.lock().unwrap().clone();
        assert_eq!(
            applied,
            vec![
                Applied::Move(0.1, 0.1),
                Applied::Key(30, true),
                Applied::Move(0.3, 0.3),
                Applied::Key(30, false),
            ]
        );
    }

    #[test]
    fn empty_queue_drains_cleanly() {
        let backend = Arc::new(RecordingBackend::default());
        let dispatcher = InputDispatcher::new(backend);
        assert!(dispatcher.drain_and_apply().is_ok());
    }

    /// T-112: a flooding peer sending far more Key/Button/Scroll events
    /// than the drain loop can keep up with must not grow the queue
    /// without bound.
    #[test]
    fn burst_of_non_move_events_stays_bounded() {
        let backend = Arc::new(RecordingBackend::default());
        let dispatcher = InputDispatcher::new(backend);

        for i in 0..(MAX_QUEUED_NON_MOVE_EVENTS * 10) {
            dispatcher.enqueue(&key_event(30, i % 2 == 0));
        }

        assert!(
            dispatcher.queue_len() <= MAX_QUEUED_NON_MOVE_EVENTS,
            "queue grew to {} despite a bound of {}",
            dispatcher.queue_len(),
            MAX_QUEUED_NON_MOVE_EVENTS
        );
    }

    /// A burst that also interleaves distinct button/scroll events (not
    /// just repeats of one key) must be bounded the same way.
    #[test]
    fn burst_of_mixed_non_move_events_stays_bounded() {
        let backend = Arc::new(RecordingBackend::default());
        let dispatcher = InputDispatcher::new(backend);

        for i in 0..(MAX_QUEUED_NON_MOVE_EVENTS * 10) {
            if i % 2 == 0 {
                dispatcher.enqueue(&key_event(i as u32, true));
            } else {
                dispatcher.enqueue(&RemoteInputEvent {
                    r#type: InputEventType::MouseScroll as i32,
                    x: 0.0,
                    y: 0.0,
                    button: 0,
                    pressed: false,
                    scroll_delta_x: 0.0,
                    scroll_delta_y: 1.0,
                    key_code: 0,
                    key_pressed: false,
                    modifiers: 0,
                });
            }
        }

        assert!(
            dispatcher.queue_len() <= MAX_QUEUED_NON_MOVE_EVENTS,
            "mixed non-move burst grew queue to {} despite a bound of {}",
            dispatcher.queue_len(),
            MAX_QUEUED_NON_MOVE_EVENTS
        );
    }

    /// T-309: a new dispatcher starts enabled, matching every test
    /// above that never touches `set_enabled`.
    #[test]
    fn dispatcher_is_enabled_by_default() {
        let backend = Arc::new(RecordingBackend::default());
        let dispatcher = InputDispatcher::new(backend);
        assert!(dispatcher.is_enabled());
    }

    /// T-309's core acceptance criterion: once disabled, incoming
    /// RemoteInputEvent frames are ignored entirely (never queued, so
    /// they can never reach the backend), and re-enabling resumes
    /// normal dispatch for events that arrive afterward.
    #[test]
    fn disabled_dispatcher_drops_incoming_events_without_queuing_them() {
        let backend = Arc::new(RecordingBackend::default());
        let dispatcher = InputDispatcher::new(backend.clone());

        dispatcher.set_enabled(false);
        assert!(!dispatcher.is_enabled());

        dispatcher.enqueue(&move_event(0.5, 0.5));
        dispatcher.enqueue(&key_event(30, true));
        assert_eq!(
            dispatcher.queue_len(),
            0,
            "events must be dropped, not queued, while disabled"
        );

        dispatcher.drain_and_apply().unwrap();
        assert!(
            backend.applied.lock().unwrap().is_empty(),
            "no event must reach the backend while disabled"
        );

        dispatcher.set_enabled(true);
        dispatcher.enqueue(&key_event(31, true));
        assert_eq!(dispatcher.queue_len(), 1);
        dispatcher.drain_and_apply().unwrap();
        assert_eq!(
            backend.applied.lock().unwrap().clone(),
            vec![Applied::Key(31, true)],
            "re-enabling must resume normal dispatch for new events"
        );
    }

    /// T-501: sustained-load check for the T-112 bound, interleaving
    /// enqueue and drain the way a real daemon would (frames arriving
    /// off the network concurrently with a drain loop applying them),
    /// at a rate well above RULES.md's "200 events/sec" scenario.
    /// Deterministic and fast (no real 10s sleep) rather than literally
    /// timed: correctness of the bound and of coalescing/ordering under
    /// sustained mixed traffic is what's being verified, not wall-clock
    /// throughput, which is dominated by the (out of scope here) input
    /// backend's own syscalls in production.
    #[test]
    fn sustained_mixed_load_stays_bounded_and_preserves_key_order() {
        let backend = Arc::new(RecordingBackend::default());
        let dispatcher = InputDispatcher::new(backend.clone());

        // 10s at 200 events/sec, mixed 4 moves : 1 key so moves (which
        // coalesce for free) don't dominate the non-move bound.
        const TOTAL_EVENTS: usize = 200 * 10;
        const DRAIN_EVERY: usize = 37; // prime, so drains land at irregular points
        let mut expected_keys = Vec::new();

        for i in 0..TOTAL_EVENTS {
            if i % 5 == 0 {
                let key_code = i as u32;
                dispatcher.enqueue(&key_event(key_code, true));
                expected_keys.push(key_code);
            } else {
                dispatcher.enqueue(&move_event(i as f32, i as f32));
            }

            assert!(
                dispatcher.queue_len() <= MAX_QUEUED_NON_MOVE_EVENTS + 1,
                "queue grew past the T-112 bound at event {i}: len={}",
                dispatcher.queue_len()
            );

            if i % DRAIN_EVERY == 0 {
                dispatcher.drain_and_apply().unwrap();
            }
        }
        dispatcher.drain_and_apply().unwrap();
        assert_eq!(
            dispatcher.queue_len(),
            0,
            "drain must fully catch up once enqueueing stops -- no unbounded lag"
        );

        let applied_keys: Vec<u32> = backend
            .applied
            .lock()
            .unwrap()
            .iter()
            .filter_map(|a| match a {
                Applied::Key(code, true) => Some(*code),
                _ => None,
            })
            .collect();
        // Frequent interleaved draining (well within the bound at every
        // step) means no key should ever have been evicted; if this
        // regresses to draining only at the very end, some of the
        // oldest keys would be dropped instead, which is the scenario
        // the eviction policy exists for -- this test's frequent-drain
        // shape is what proves it not lagging in the first place.
        assert_eq!(
            applied_keys, expected_keys,
            "every key event must survive and stay in order under sustained interleaved load"
        );
    }
}
