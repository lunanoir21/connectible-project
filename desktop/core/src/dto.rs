//! Serde DTOs crossing the Tauri IPC boundary. Field names are
//! camelCase to match the TypeScript side's conventions (RULES.md);
//! every type mirrors a proto message but stays independent of prost
//! types so the frontend contract can't accidentally leak
//! wire-encoding details.

use connectibled::proto::connectible::v1 as pb;
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceDto {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub online: bool,
    pub paired_at_ms: i64,
    pub last_seen_ms: i64,
}

impl From<pb::DeviceInfo> for DeviceDto {
    fn from(info: pb::DeviceInfo) -> Self {
        let identity = info.identity.unwrap_or_default();
        // Same enum -> TXT-record-style string used for NearbyDevice, so
        // the frontend's platformIcon()/platformLabel() work for paired
        // devices too instead of only ones still being discovered.
        let platform = pb::Platform::try_from(identity.platform)
            .unwrap_or(pb::Platform::Unspecified)
            .as_str_name()
            .to_string();
        Self {
            device_id: identity.device_id,
            device_name: identity.device_name,
            platform,
            online: info.online,
            paired_at_ms: info.paired_at_ms,
            last_seen_ms: info.last_seen_ms,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NearbyDeviceDto {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub addr: String,
    pub port: u32,
}

impl From<pb::NearbyDevice> for NearbyDeviceDto {
    fn from(device: pb::NearbyDevice) -> Self {
        Self {
            device_id: device.device_id,
            device_name: device.device_name,
            platform: device.platform,
            addr: device.addr,
            port: device.port,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipboardEntryDto {
    /// Base64-encoded raw bytes (Phase L: content can be an image, not
    /// just text) -- empty when `oversized` is true. The frontend
    /// decodes text mime types back to a string, or builds a `data:`
    /// URI directly from this field for image mime types.
    pub content: String,
    pub mime_type: String,
    pub captured_at_ms: i64,
    pub source: String,
    /// True when the original content exceeded the daemon's cap and
    /// was recorded for visibility only -- `content` is empty in that
    /// case; the frontend should show `byteSize` instead of a preview.
    pub oversized: bool,
    pub byte_size: i64,
}

impl From<pb::ClipboardHistoryEntry> for ClipboardEntryDto {
    fn from(entry: pb::ClipboardHistoryEntry) -> Self {
        use base64::Engine;
        Self {
            content: base64::engine::general_purpose::STANDARD.encode(&entry.content),
            mime_type: entry.mime_type,
            captured_at_ms: entry.captured_at_ms,
            source: entry.source,
            oversized: entry.oversized,
            byte_size: entry.byte_size,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatteryDto {
    pub percentage: u32,
    pub is_charging: bool,
    pub minutes_remaining: i32,
    pub reported_at_ms: i64,
}

impl From<pb::BatteryStatus> for BatteryDto {
    fn from(battery: pb::BatteryStatus) -> Self {
        Self {
            percentage: battery.percentage,
            is_charging: battery.is_charging,
            minutes_remaining: battery.minutes_remaining,
            reported_at_ms: battery.reported_at_ms,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NotificationDto {
    pub notification_id: String,
    pub app_name: String,
    pub title: String,
    pub body: String,
    pub posted_at_ms: i64,
    pub is_dismissal: bool,
}

impl From<pb::NotificationData> for NotificationDto {
    fn from(notification: pb::NotificationData) -> Self {
        Self {
            notification_id: notification.notification_id,
            app_name: notification.app_name,
            title: notification.title,
            body: notification.body,
            posted_at_ms: notification.posted_at_ms,
            is_dismissal: notification.is_dismissal,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferProgressDto {
    pub transfer_id: String,
    pub file_name: String,
    pub bytes_transferred: i64,
    pub total_bytes: i64,
    pub completed: bool,
    pub failed: bool,
    /// True when the user aborted an outgoing transfer (a distinct,
    /// non-error terminal state so the UI can say "Canceled" not "Failed").
    pub canceled: bool,
    /// "incoming" (received by the daemon) or "outgoing" (sent by this
    /// desktop app). The proto TransferProgress only describes incoming
    /// transfers; outgoing progress is synthesized by remote.rs.
    pub direction: String,
    /// Sender-declared content type, forwarded from the daemon's
    /// TransferProgress (dedicated upload path only -- see the proto
    /// field's own comment). Empty when unknown.
    pub mime_type: String,
}

impl TransferProgressDto {
    pub fn incoming(progress: pb::TransferProgress) -> Self {
        Self {
            transfer_id: progress.transfer_id,
            file_name: progress.file_name,
            bytes_transferred: progress.bytes_transferred,
            total_bytes: progress.total_bytes,
            completed: progress.completed,
            failed: progress.failed,
            canceled: false,
            direction: "incoming".to_string(),
            mime_type: progress.mime_type,
        }
    }
}

/// Phase J: one persisted `transfer_history` row (both directions --
/// see `daemon/src/grpc/service.rs`'s `TransferHistoryEntry` doc for
/// why incoming and outgoing are written through different paths but
/// land in the same table).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferHistoryEntryDto {
    pub transfer_id: String,
    pub peer_device_id: String,
    pub file_name: String,
    pub total_bytes: i64,
    pub direction: String,
    pub status: String,
    pub started_at_ms: i64,
    pub finished_at_ms: i64,
}

impl From<pb::TransferHistoryEntry> for TransferHistoryEntryDto {
    fn from(entry: pb::TransferHistoryEntry) -> Self {
        Self {
            transfer_id: entry.transfer_id,
            peer_device_id: entry.peer_device_id,
            file_name: entry.file_name,
            total_bytes: entry.total_bytes,
            direction: entry.direction,
            status: entry.status,
            started_at_ms: entry.started_at_ms,
            finished_at_ms: entry.finished_at_ms,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingPromptDto {
    pub requester_device_id: String,
    pub requester_device_name: String,
    pub pin_code: String,
    pub pin_expires_at_ms: i64,
}

impl From<pb::PairingRequestedLocalEvent> for PairingPromptDto {
    fn from(event: pb::PairingRequestedLocalEvent) -> Self {
        Self {
            requester_device_id: event.requester_device_id,
            requester_device_name: event.requester_device_name,
            pin_code: event.pin_code,
            pin_expires_at_ms: event.pin_expires_at_ms,
        }
    }
}

/// A pre-generated pairing code for a QR (scan-to-pair). `pinCode` is
/// exactly the PIN a subsequent `Pair`/`ConfirmPin` exchange will
/// check -- there's no separate confirmation step once it's scanned.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingCodeDto {
    pub pin_code: String,
    pub pin_expires_at_ms: i64,
}

impl From<pb::PreArmPairingCodeResponse> for PairingCodeDto {
    fn from(response: pb::PreArmPairingCodeResponse) -> Self {
        Self {
            pin_code: response.pin_code,
            pin_expires_at_ms: response.pin_expires_at_ms,
        }
    }
}

/// Fired once the requester successfully confirms the PIN this device
/// was showing/sharing (responder side) -- lets that PIN dialog show a
/// success beat and close instead of sitting on the code until the
/// countdown expires.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingCompletedDto {
    pub requester_device_id: String,
    pub requester_device_name: String,
}

impl From<pb::PairingCompletedLocalEvent> for PairingCompletedDto {
    fn from(event: pb::PairingCompletedLocalEvent) -> Self {
        Self {
            requester_device_id: event.requester_device_id,
            requester_device_name: event.requester_device_name,
        }
    }
}

/// Tagged union emitted to the frontend as the "local-event" Tauri
/// event payload; mirrors proto LocalEvent's oneof.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum LocalEventDto {
    #[serde(rename_all = "camelCase")]
    PairingRequested { prompt: PairingPromptDto },
    #[serde(rename_all = "camelCase")]
    Battery { battery: BatteryDto },
    #[serde(rename_all = "camelCase")]
    Notification { notification: NotificationDto },
    #[serde(rename_all = "camelCase")]
    Clipboard { entry: ClipboardEntryDto },
    #[serde(rename_all = "camelCase")]
    TransferProgress { progress: TransferProgressDto },
    #[serde(rename_all = "camelCase")]
    PairingCompleted { completion: PairingCompletedDto },
}

impl LocalEventDto {
    /// Maps a wire-level LocalEvent to the frontend DTO; returns None
    /// for an empty/unknown oneof case (forward compatibility: a newer
    /// daemon may emit event kinds this UI build does not know).
    pub fn from_proto(event: pb::LocalEvent) -> Option<Self> {
        use pb::local_event::Event;
        Some(match event.event? {
            Event::PairingRequested(prompt) => Self::PairingRequested {
                prompt: prompt.into(),
            },
            Event::Battery(battery) => Self::Battery {
                battery: battery.into(),
            },
            Event::Notification(notification) => Self::Notification {
                notification: notification.into(),
            },
            Event::Clipboard(entry) => Self::Clipboard {
                entry: entry.into(),
            },
            Event::TransferProgress(progress) => Self::TransferProgress {
                progress: TransferProgressDto::incoming(progress),
            },
            Event::PairingCompleted(event) => Self::PairingCompleted {
                completion: event.into(),
            },
        })
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalStateDto {
    pub device_id: String,
    pub device_name: String,
    pub capabilities: Vec<String>,
    pub clipboard_history: Vec<ClipboardEntryDto>,
    pub latest_battery: Option<BatteryDto>,
    pub notifications: Vec<NotificationDto>,
    pub nearby_devices: Vec<NearbyDeviceDto>,
    /// Whether incoming RemoteInputEvent frames are currently applied
    /// (T-309); always false when "remote_input" is absent from
    /// `capabilities`.
    pub remote_input_enabled: bool,
    /// Whether local clipboard changes are polled/broadcast and
    /// incoming ones applied (T-310); always false when "clipboard" is
    /// absent from `capabilities`.
    pub clipboard_sync_enabled: bool,
}

impl From<pb::GetLocalStateResponse> for LocalStateDto {
    fn from(state: pb::GetLocalStateResponse) -> Self {
        let identity = state.local_identity.unwrap_or_default();
        Self {
            device_id: identity.device_id,
            device_name: identity.device_name,
            capabilities: state.capabilities,
            clipboard_history: state
                .clipboard_history
                .into_iter()
                .map(Into::into)
                .collect(),
            latest_battery: state.latest_battery.map(Into::into),
            notifications: state.notifications.into_iter().map(Into::into).collect(),
            nearby_devices: state.nearby_devices.into_iter().map(Into::into).collect(),
            remote_input_enabled: state.remote_input_enabled,
            clipboard_sync_enabled: state.clipboard_sync_enabled,
        }
    }
}

/// One System Doctor check result (T-F7/F8), mirrored to the frontend.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiagnosticCheckDto {
    pub id: String,
    pub title: String,
    /// "environment" | "network" | "pairing" | "features".
    pub category: String,
    /// "ok" | "warn" | "error".
    pub status: String,
    pub summary: String,
    /// Empty when absent.
    pub detail: String,
    /// Empty when absent.
    pub remediation: String,
    pub data: std::collections::HashMap<String, String>,
    /// Stable message id for `summary` (T-X43); empty = no stable
    /// template, client falls back to `summary` verbatim.
    pub summary_key: String,
    /// Same fallback contract as `summary_key`, for `remediation`.
    pub remediation_key: String,
}

impl From<pb::DiagnosticCheck> for DiagnosticCheckDto {
    fn from(c: pb::DiagnosticCheck) -> Self {
        Self {
            id: c.id,
            title: c.title,
            category: c.category,
            status: c.status,
            summary: c.summary,
            detail: c.detail,
            remediation: c.remediation,
            data: c.data,
            summary_key: c.summary_key,
            remediation_key: c.remediation_key,
        }
    }
}

/// A full System Doctor run: every check plus the worst-severity roll-up.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiagnosticsReportDto {
    pub checks: Vec<DiagnosticCheckDto>,
    /// "ok" | "warn" | "error".
    pub worst: String,
}

impl From<pb::RunDiagnosticsResponse> for DiagnosticsReportDto {
    fn from(r: pb::RunDiagnosticsResponse) -> Self {
        Self {
            checks: r.checks.into_iter().map(Into::into).collect(),
            worst: r.worst,
        }
    }
}
