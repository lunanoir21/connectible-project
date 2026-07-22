use std::path::PathBuf;

use connectibled::proto::connectible::v1::connectible_client::ConnectibleClient;
use connectibled::proto::connectible::v1::{
    DisconnectDeviceRequest, ForgetDeviceRequest, GetLocalStateRequest,
    GetPinnedFingerprintRequest, ListDevicesRequest, ListTransferHistoryRequest, LocalEvent,
    LocalEventsRequest, PingRequest, PreArmPairingCodeRequest, RecordFingerprintRequest,
    RecordTransferHistoryRequest, RunDiagnosticsRequest, SetClipboardSyncEnabledRequest,
    SetRemoteInputEnabledRequest, TransferHistoryEntry,
};
use tonic::transport::{Certificate, Channel, ClientTlsConfig};
use tonic::Streaming;

use crate::dto::{DeviceDto, LocalStateDto, TransferHistoryEntryDto};
use crate::{DesktopError, Result};

/// Client for the *local* daemon over loopback TLS (T-033's role,
/// transported via tonic instead of gRPC-Web -- see ADR-001).
///
/// Trust model: pins exactly the certificate the daemon wrote to its
/// data directory on first run (`tls/cert.pem`), the same
/// narrowly-scoped pattern the daemon's own integration tests use.
/// This is NOT the accept-any-self-signed verifier used for remote
/// devices; a process that cannot read the daemon's data dir cannot
/// impersonate it.
#[derive(Clone)]
pub struct LocalDaemonClient {
    client: ConnectibleClient<Channel>,
}

/// Resolves the daemon's data directory exactly the way the daemon
/// itself does (config.rs), so the UI reads the same cert file.
pub fn default_daemon_data_dir() -> Result<PathBuf> {
    directories::ProjectDirs::from("io", "connectible", "connectibled")
        .map(|dirs| dirs.data_dir().to_path_buf())
        .ok_or_else(|| DesktopError::Other("no home directory".to_string()))
}

/// Default daemon gRPC port, honoring the same CONNECTIBLE_PORT
/// override the daemon itself reads (daemon config.rs), so pointing
/// both at a non-default port needs only one env var.
pub fn default_daemon_port() -> u16 {
    std::env::var("CONNECTIBLE_PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(58231)
}

/// Interface name prefixes that identify a virtual/container/VPN
/// adapter rather than a real LAN link. These addresses are technically
/// "private" by IP-range rules and can otherwise sort ahead of the real
/// Wi-Fi/Ethernet address purely by numeric luck (e.g. Docker's default
/// bridge, 172.17.0.1, sorts before a 192.168.x.x Wi-Fi address). Not
/// exhaustive -- the goal is filtering out the handful of interfaces
/// that show up constantly on dev machines, not perfect coverage of
/// every virtual adapter naming scheme in existence.
const VIRTUAL_IFACE_PREFIXES: &[&str] = &[
    "docker", // Docker's default bridge (docker0) and related
    "br-",    // Docker user-defined bridge networks
    "veth",   // Docker/container veth pairs
    "vmnet",  // VMware host-only/NAT adapters
    "utun",   // macOS VPN tunnel interfaces
];

fn is_virtual_iface_name(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    VIRTUAL_IFACE_PREFIXES
        .iter()
        .any(|prefix| lower.starts_with(prefix))
}

/// This machine's usable LAN IPv4 addresses, so the desktop can show
/// its own "connect by address" endpoint the way mobile already does
/// (the webview can't enumerate interfaces itself). Loopback and
/// link-local (169.254.x.x) addresses are dropped -- a peer can't reach
/// this device on either -- as are addresses on well-known virtual/
/// container/VPN interfaces (Docker bridges, veth pairs, vmnet, macOS
/// VPN tunnels), which would otherwise be indistinguishable from a real
/// LAN address by IP range alone. The rest are ordered so a private-LAN
/// address (192.168/10/172.16-31) sorts ahead of anything else, since
/// that's overwhelmingly the one the user wants to hand out.
pub fn local_ipv4_addresses() -> Vec<String> {
    let Ok(ifaces) = if_addrs::get_if_addrs() else {
        return Vec::new();
    };
    let named: Vec<(String, std::net::Ipv4Addr)> = ifaces
        .into_iter()
        .filter_map(|iface| match iface.addr {
            if_addrs::IfAddr::V4(v4) => Some((iface.name, v4.ip)),
            if_addrs::IfAddr::V6(_) => None,
        })
        .collect();
    filter_and_sort_ipv4(named)
}

/// The filtering/ordering logic behind [`local_ipv4_addresses`], pulled
/// out as a pure function of `(interface name, address)` pairs so it can
/// be exercised in tests against synthetic interfaces (e.g. a
/// docker0-shaped one) without depending on the real host's network
/// configuration.
fn filter_and_sort_ipv4(ifaces: Vec<(String, std::net::Ipv4Addr)>) -> Vec<String> {
    let mut addrs: Vec<std::net::Ipv4Addr> = ifaces
        .into_iter()
        .filter(|(name, _)| !is_virtual_iface_name(name))
        .map(|(_, ip)| ip)
        .filter(|ip| !ip.is_loopback() && !ip.is_link_local())
        .collect();
    addrs.sort_by_key(|ip| (!ip.is_private(), ip.octets()));
    addrs.dedup();
    addrs.into_iter().map(|ip| ip.to_string()).collect()
}

/// Identity the desktop app presents on outbound streams (file sends,
/// input sessions, pairing requests). Reuses the daemon's persisted
/// device_id so the remote side sees one device, not two -- the UI
/// acts on behalf of this machine, it is not a separate peer.
pub fn ui_identity(
    data_dir: &std::path::Path,
    device_name: &str,
) -> connectibled::proto::connectible::v1::Identity {
    use connectibled::proto::connectible::v1::{DeviceType, Identity};

    let device_id = std::fs::read_to_string(data_dir.join("device_id"))
        .map(|s| s.trim().to_string())
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

    Identity {
        device_id,
        device_name: device_name.to_string(),
        platform: 0,
        device_type: DeviceType::Desktop as i32,
        protocol_version: 1,
        app_version: env!("CARGO_PKG_VERSION").to_string(),
        capabilities: vec![],
    }
}

/// Builds the pinned-certificate TLS config shared by `LocalDaemonClient::
/// connect` and `tls_handshake_check`, reading the cert the daemon wrote
/// to its data dir on first run.
fn pinned_tls_config(data_dir: &std::path::Path) -> Result<ClientTlsConfig> {
    let cert_path = data_dir.join("tls").join("cert.pem");
    let cert_pem = std::fs::read_to_string(&cert_path).map_err(|e| {
        DesktopError::DaemonUnreachable(format!(
            "cannot read daemon certificate at {} (is connectibled running?): {e}",
            cert_path.display()
        ))
    })?;

    Ok(ClientTlsConfig::new()
        .ca_certificate(Certificate::from_pem(cert_pem))
        // The daemon's self-signed cert carries "localhost" as its
        // subject alt name (see daemon/src/tls.rs).
        .domain_name("localhost"))
}

/// Performs only the TLS 1.3 handshake against the local daemon (channel
/// connect, no RPC), using the same pinned-certificate trust model as
/// `LocalDaemonClient::connect`. Used by the desktop Doctor panel to
/// prove the TLS/certificate layer works independently of whether any
/// particular gRPC call succeeds.
pub async fn tls_handshake_check(data_dir: &std::path::Path, port: u16) -> Result<()> {
    let tls = pinned_tls_config(data_dir)?;
    Channel::from_shared(format!("https://127.0.0.1:{port}"))
        .map_err(|e| DesktopError::InvalidAddress(e.to_string()))?
        .tls_config(tls)?
        .connect()
        .await
        .map_err(|e| DesktopError::DaemonUnreachable(e.to_string()))?;
    Ok(())
}

impl LocalDaemonClient {
    /// Connects to the local daemon at `127.0.0.1:port`, trusting the
    /// certificate found at `<data_dir>/tls/cert.pem`.
    pub async fn connect(data_dir: PathBuf, port: u16) -> Result<Self> {
        let tls = pinned_tls_config(&data_dir)?;

        let channel = Channel::from_shared(format!("https://127.0.0.1:{port}"))
            .map_err(|e| DesktopError::InvalidAddress(e.to_string()))?
            .tls_config(tls)?
            // HTTP/2 keepalive so a silently-dropped local event stream
            // (e.g. daemon killed) surfaces promptly and the bridge
            // reconnects, instead of hanging on a half-open connection.
            .http2_keep_alive_interval(std::time::Duration::from_secs(20))
            .keep_alive_timeout(std::time::Duration::from_secs(10))
            .keep_alive_while_idle(true)
            .connect()
            .await
            .map_err(|e| DesktopError::DaemonUnreachable(e.to_string()))?;

        Ok(Self {
            client: ConnectibleClient::new(channel),
        })
    }

    /// Round-trip latency to the daemon in milliseconds.
    pub async fn ping_rtt_ms(&self) -> Result<i64> {
        let started = std::time::Instant::now();
        let mut client = self.client.clone();
        client
            .ping(PingRequest {
                sent_at_ms: now_ms(),
            })
            .await?;
        Ok(started.elapsed().as_millis() as i64)
    }

    pub async fn local_state(&self) -> Result<LocalStateDto> {
        let mut client = self.client.clone();
        let state = client
            .get_local_state(GetLocalStateRequest {})
            .await?
            .into_inner();
        Ok(state.into())
    }

    pub async fn list_devices(&self) -> Result<Vec<DeviceDto>> {
        let mut client = self.client.clone();
        let response = client
            .list_devices(ListDevicesRequest { online_only: false })
            .await?
            .into_inner();
        Ok(response.devices.into_iter().map(Into::into).collect())
    }

    /// Drops the daemon's live-connection attribution for a paired
    /// device (T-102's "Disconnect" action in the HomePanel device
    /// list). Returns whether a live connection was actually found --
    /// false is not an error, it just means the device was already
    /// offline (or only mDNS-visible).
    pub async fn disconnect_device(&self, device_id: &str) -> Result<bool> {
        let mut client = self.client.clone();
        let response = client
            .disconnect_device(DisconnectDeviceRequest {
                device_id: device_id.to_string(),
            })
            .await?
            .into_inner();
        Ok(response.was_connected)
    }

    /// Permanently removes a paired device from the daemon's store
    /// (T-307's "Forget device" action). Returns whether a device with
    /// this device_id was actually found and removed -- false is not
    /// an error, it just means it was already unpaired. Afterward the
    /// device requires a fresh Pair/ConfirmPin PIN exchange to
    /// reconnect (the T-015 short-circuit no longer applies).
    pub async fn forget_device(&self, device_id: &str) -> Result<bool> {
        let mut client = self.client.clone();
        let response = client
            .forget_device(ForgetDeviceRequest {
                device_id: device_id.to_string(),
            })
            .await?
            .into_inner();
        Ok(response.removed)
    }

    /// System Doctor (T-F7): runs the daemon's diagnostics engine and
    /// returns the structured report. `check_id` runs a single check, or
    /// `None` runs them all. The desktop panel consumes exactly this, so it
    /// stays in lockstep with `connectibled doctor`.
    pub async fn run_diagnostics(
        &self,
        check_id: Option<&str>,
    ) -> Result<crate::dto::DiagnosticsReportDto> {
        let mut client = self.client.clone();
        let response = client
            .run_diagnostics(RunDiagnosticsRequest {
                check_id: check_id.unwrap_or_default().to_string(),
            })
            .await?
            .into_inner();
        Ok(response.into())
    }

    /// TOFU (T-C2): the pinned cert fingerprint the daemon holds for a
    /// paired device, or `None` if it has no pin yet (unknown, or a
    /// pre-TOFU device awaiting first-use backfill). Read before dialing so
    /// the remote connection's verifier can enforce the pin.
    pub async fn pinned_fingerprint(&self, device_id: &str) -> Result<Option<String>> {
        let mut client = self.client.clone();
        let response = client
            .get_pinned_fingerprint(GetPinnedFingerprintRequest {
                device_id: device_id.to_string(),
            })
            .await?
            .into_inner();
        Ok(if response.fingerprint.is_empty() {
            None
        } else {
            Some(response.fingerprint)
        })
    }

    /// TOFU (T-C2/C5): pins a device's observed cert fingerprint
    /// (record-on-first-use / pre-TOFU backfill). Returns whether the
    /// daemon recorded it (false = unknown device).
    pub async fn record_fingerprint(&self, device_id: &str, fingerprint: &str) -> Result<bool> {
        let mut client = self.client.clone();
        let response = client
            .record_fingerprint(RecordFingerprintRequest {
                device_id: device_id.to_string(),
                fingerprint: fingerprint.to_string(),
            })
            .await?
            .into_inner();
        Ok(response.recorded)
    }

    /// Gates whether incoming RemoteInputEvent frames are applied to
    /// the daemon's input backend (T-309's RemoteInputPanel toggle).
    /// Returns the value now in effect (echoed from the daemon, which
    /// is the source of truth).
    pub async fn set_remote_input_enabled(&self, enabled: bool) -> Result<bool> {
        let mut client = self.client.clone();
        let response = client
            .set_remote_input_enabled(SetRemoteInputEnabledRequest { enabled })
            .await?
            .into_inner();
        Ok(response.enabled)
    }

    /// Gates whether the daemon polls/broadcasts local clipboard
    /// changes and applies incoming ones (T-310's tray/settings
    /// toggle). Returns the value now in effect.
    pub async fn set_clipboard_sync_enabled(&self, enabled: bool) -> Result<bool> {
        let mut client = self.client.clone();
        let response = client
            .set_clipboard_sync_enabled(SetClipboardSyncEnabledRequest { enabled })
            .await?
            .into_inner();
        Ok(response.enabled)
    }

    /// Pre-generates a PIN for a pairing QR code (scan-to-pair, T-2.QR):
    /// the returned code is exactly what a subsequent `Pair` call from
    /// anywhere will be checked against (see `PairingManager::pre_arm`
    /// on the daemon side), so the desktop UI can embed it directly in
    /// the QR payload with no extra confirmation step needed.
    pub async fn pre_arm_pairing_code(&self) -> Result<crate::dto::PairingCodeDto> {
        let mut client = self.client.clone();
        let response = client
            .pre_arm_pairing_code(PreArmPairingCodeRequest {})
            .await?
            .into_inner();
        Ok(response.into())
    }

    /// Opens the loopback-only local event stream (pairing prompts,
    /// battery, notifications, clipboard history, transfer progress).
    /// The caller (Tauri shell) forwards each event to the frontend.
    pub async fn subscribe_local_events(&self) -> Result<Streaming<LocalEvent>> {
        let mut client = self.client.clone();
        let stream = client
            .subscribe_local_events(LocalEventsRequest {})
            .await?
            .into_inner();
        Ok(stream)
    }

    /// Phase J: reports the outcome of an outgoing send this process
    /// drove itself directly against a remote peer's daemon (`send_file`
    /// via `RemoteDeviceClient::upload_file`) -- the local daemon has no
    /// other way to learn about it, unlike an incoming transfer.
    /// Best-effort from the caller's point of view: a failure here
    /// should be logged, not surfaced as if the transfer itself failed.
    #[allow(clippy::too_many_arguments)]
    pub async fn record_transfer_history(
        &self,
        transfer_id: &str,
        peer_device_id: &str,
        file_name: &str,
        total_bytes: i64,
        direction: &str,
        status: &str,
        started_at_ms: i64,
        finished_at_ms: i64,
    ) -> Result<()> {
        let mut client = self.client.clone();
        client
            .record_transfer_history(RecordTransferHistoryRequest {
                entry: Some(TransferHistoryEntry {
                    transfer_id: transfer_id.to_string(),
                    peer_device_id: peer_device_id.to_string(),
                    file_name: file_name.to_string(),
                    total_bytes,
                    direction: direction.to_string(),
                    status: status.to_string(),
                    started_at_ms,
                    finished_at_ms,
                }),
            })
            .await?;
        Ok(())
    }

    /// Phase J: persisted transfer history, most recent first (both
    /// directions -- incoming rows the daemon wrote itself, outgoing
    /// rows relayed in via `record_transfer_history` above).
    pub async fn list_transfer_history(&self, limit: i32) -> Result<Vec<TransferHistoryEntryDto>> {
        let mut client = self.client.clone();
        let response = client
            .list_transfer_history(ListTransferHistoryRequest { limit })
            .await?
            .into_inner();
        Ok(response.entries.into_iter().map(Into::into).collect())
    }
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_ipv4_addresses_excludes_loopback_and_link_local() {
        // Interface set is host-dependent, so this asserts the filtering
        // invariants rather than any specific address: never loopback,
        // never link-local, always a parseable IPv4, and private-LAN
        // addresses sort ahead of the rest.
        let addrs = local_ipv4_addresses();
        let mut seen_public = false;
        for a in &addrs {
            let ip: std::net::Ipv4Addr = a.parse().expect("valid IPv4 string");
            assert!(!ip.is_loopback(), "{a} is loopback");
            assert!(!ip.is_link_local(), "{a} is link-local");
            if ip.is_private() {
                assert!(!seen_public, "private address {a} sorted after a public one");
            } else {
                seen_public = true;
            }
        }
    }

    #[test]
    fn docker_bridge_is_excluded_even_though_it_sorts_first_numerically() {
        // 172.17.0.1 (docker0) would otherwise sort ahead of 192.168.1.42
        // (the real Wi-Fi/LAN address) purely because 172 < 192 -- this
        // is the exact scenario the interface-name filter exists for.
        let ifaces = vec![
            ("docker0".to_string(), "172.17.0.1".parse().unwrap()),
            ("wlan0".to_string(), "192.168.1.42".parse().unwrap()),
        ];
        let addrs = filter_and_sort_ipv4(ifaces);
        assert_eq!(addrs, vec!["192.168.1.42".to_string()]);
    }

    #[test]
    fn other_virtual_interface_names_are_excluded() {
        let ifaces = vec![
            ("br-abc123".to_string(), "172.20.0.1".parse().unwrap()),
            ("veth1234".to_string(), "172.21.0.5".parse().unwrap()),
            ("vmnet8".to_string(), "172.16.99.1".parse().unwrap()),
            ("utun3".to_string(), "10.8.0.2".parse().unwrap()),
            ("eth0".to_string(), "10.0.0.5".parse().unwrap()),
        ];
        let addrs = filter_and_sort_ipv4(ifaces);
        assert_eq!(addrs, vec!["10.0.0.5".to_string()]);
    }
}
