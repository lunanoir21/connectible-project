use std::sync::Mutex;

use tokio::sync::broadcast;

use crate::proto::connectible::v1::{BatteryStatus, NotificationData};

/// Event pushed to local UI subscribers (desktop tray/panel) when the
/// daemon receives a `BatteryStatus` or `NotificationData` frame from a
/// paired mobile peer (T-031). Mirrors the `PairingRequestedEvent`
/// pattern in `pairing::PairingManager`.
#[derive(Debug, Clone)]
pub enum StatusEvent {
    Battery(BatteryStatus),
    Notification(NotificationData),
}

/// Tracks the most recently forwarded battery reading and the set of
/// currently-live (not yet dismissed) notifications forwarded from a
/// paired mobile device. The daemon does not originate this data
/// itself in MVP -- only mobile-to-desktop forwarding is in scope (see
/// PLAN.md non-goals).
#[derive(Default)]
pub struct StatusHub {
    battery: Mutex<Option<BatteryStatus>>,
    notifications: Mutex<Vec<NotificationData>>,
    events: Mutex<Option<broadcast::Sender<StatusEvent>>>,
}

impl StatusHub {
    pub fn subscribe(&self) -> broadcast::Receiver<StatusEvent> {
        let mut guard = self
            .events
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let sender = guard.get_or_insert_with(|| broadcast::channel(32).0);
        sender.subscribe()
    }

    fn emit(&self, event: StatusEvent) {
        if let Some(sender) = self
            .events
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .as_ref()
        {
            let _ = sender.send(event);
        }
    }

    pub fn update_battery(&self, status: BatteryStatus) {
        *self
            .battery
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(status);
        self.emit(StatusEvent::Battery(status));
    }

    pub fn latest_battery(&self) -> Option<BatteryStatus> {
        *self
            .battery
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Applies an incoming `NotificationData` frame: either records a
    /// new/updated notification, or -- when `is_dismissal` is set --
    /// removes the matching prior notification by `notification_id`
    /// without treating a missing match as an error (the dismissal may
    /// race a notification this daemon never saw).
    pub fn apply_notification(&self, notification: NotificationData) {
        let mut notifications = self
            .notifications
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        notifications.retain(|n| n.notification_id != notification.notification_id);
        if !notification.is_dismissal {
            notifications.push(notification.clone());
        }
        drop(notifications);
        self.emit(StatusEvent::Notification(notification));
    }

    pub fn list_notifications(&self) -> Vec<NotificationData> {
        self.notifications
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn battery(percentage: u32) -> BatteryStatus {
        BatteryStatus {
            percentage,
            is_charging: false,
            minutes_remaining: -1,
            reported_at_ms: 1000,
        }
    }

    fn notification(id: &str, is_dismissal: bool) -> NotificationData {
        NotificationData {
            notification_id: id.to_string(),
            app_name: "Messages".to_string(),
            title: "Hi".to_string(),
            body: "there".to_string(),
            icon: vec![],
            posted_at_ms: 1000,
            is_dismissal,
        }
    }

    #[test]
    fn battery_update_is_retrievable() {
        let hub = StatusHub::default();
        assert!(hub.latest_battery().is_none());
        hub.update_battery(battery(80));
        assert_eq!(hub.latest_battery().unwrap().percentage, 80);
    }

    #[test]
    fn notification_is_added_then_removed_on_dismissal() {
        let hub = StatusHub::default();
        hub.apply_notification(notification("n1", false));
        assert_eq!(hub.list_notifications().len(), 1);

        hub.apply_notification(notification("n1", true));
        assert!(hub.list_notifications().is_empty());
    }

    #[test]
    fn dismissal_of_unknown_notification_is_not_an_error() {
        let hub = StatusHub::default();
        hub.apply_notification(notification("never-seen", true));
        assert!(hub.list_notifications().is_empty());
    }

    #[tokio::test]
    async fn subscribers_receive_battery_and_notification_events() {
        let hub = StatusHub::default();
        let mut rx = hub.subscribe();

        hub.update_battery(battery(42));
        match rx.recv().await.expect("event") {
            StatusEvent::Battery(b) => assert_eq!(b.percentage, 42),
            _ => panic!("expected Battery event"),
        }

        hub.apply_notification(notification("n2", false));
        match rx.recv().await.expect("event") {
            StatusEvent::Notification(n) => assert_eq!(n.notification_id, "n2"),
            _ => panic!("expected Notification event"),
        }
    }
}
