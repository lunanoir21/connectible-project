use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::{Arc, RwLock};

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use tracing::{debug, info, warn};

use crate::error::Result;
use crate::proto::connectible::v1::{Identity, Platform};
use crate::ratelimit::RateLimiter;

pub const SERVICE_TYPE: &str = "_connectible._tcp.local.";

/// T-C6: bound on distinct discovered devices held in memory. A network
/// full of (possibly spoofed) advertisers cannot grow the table without
/// limit -- new distinct device_ids past this cap are dropped; already-
/// known devices still update. Generous relative to any real LAN.
const MAX_DISCOVERED: usize = 256;

/// T-C6: per-advertiser processing rate. A single device_id re-resolving in
/// a tight loop (a flood aimed at burning CPU parsing/inserting) is bounded
/// to this many `ServiceResolved` events per window; excess is skipped.
const RESOLVES_PER_DEVICE: u32 = 10;
const RESOLVE_WINDOW: std::time::Duration = std::time::Duration::from_secs(10);

/// A device currently visible on the local network via mDNS, distinct
/// from a *paired* device persisted in SQLite (T-005). Entries here are
/// pruned when mDNS reports the peer as removed / TTL-expired.
#[derive(Debug, Clone)]
pub struct DiscoveredDevice {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub protocol_version: String,
    pub addr: IpAddr,
    pub port: u16,
}

#[derive(Clone, Default)]
pub struct DiscoveryTable {
    inner: Arc<RwLock<HashMap<String, DiscoveredDevice>>>,
}

impl DiscoveryTable {
    pub fn list(&self) -> Vec<DiscoveredDevice> {
        self.inner
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .values()
            .cloned()
            .collect()
    }

    fn insert(&self, device: DiscoveredDevice) {
        let mut map = self
            .inner
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        // T-C6: cap distinct advertisers. A new device_id past the cap is
        // dropped; a known one always updates (so a real device's address
        // change is never lost, and the flood only affects newcomers).
        if !map.contains_key(&device.device_id) && map.len() >= MAX_DISCOVERED {
            warn!(
                device_id = %device.device_id,
                "discovery table full ({MAX_DISCOVERED}); dropping new advertiser"
            );
            return;
        }
        map.insert(device.device_id.clone(), device);
    }

    fn remove_by_fullname_prefix(&self, device_id_hint: Option<&str>) {
        if let Some(id) = device_id_hint {
            self.inner
                .write()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .remove(id);
        }
    }
}

/// Advertises this daemon on `_connectible._tcp.local.` with TXT records
/// carrying `device_id`, `device_name`, `platform`, `protocol_version`
/// (T-004), so peers can filter without an extra RPC round-trip.
/// `hostname` is the mDNS host label (distinct from `identity.device_name`,
/// which may contain characters not valid in a DNS label).
///
/// T-503: `.enable_addr_auto()` below is what makes this survive a
/// network interface change without a daemon restart -- `mdns_sd`'s
/// own event loop polls host interfaces every
/// `IP_CHECK_INTERVAL_IN_SECS_DEFAULT` (5s) and automatically adds/
/// removes addresses on any service registered with `addr_auto`
/// (`ServiceDaemon::check_ip_changes`), independent of anything this
/// daemon does. Verified by inspecting the crate's own polling loop
/// (`service_daemon.rs`'s `check_ip_changes`/`apply_intf_selections`),
/// since simulating a real interface up/down cycle isn't practical in
/// an automated test.
pub fn advertise(
    mdns: &ServiceDaemon,
    hostname: &str,
    port: u16,
    identity: &Identity,
) -> Result<()> {
    let platform_name = Platform::try_from(identity.platform)
        .unwrap_or(Platform::Unspecified)
        .as_str_name();
    let protocol_version = identity.protocol_version.to_string();

    let properties = [
        ("device_id", identity.device_id.as_str()),
        ("device_name", identity.device_name.as_str()),
        ("platform", platform_name),
        ("protocol_version", protocol_version.as_str()),
    ];

    let service_info = ServiceInfo::new(
        SERVICE_TYPE,
        &identity.device_id,
        &format!("{hostname}.local."),
        "",
        port,
        &properties[..],
    )?
    .enable_addr_auto();

    mdns.register(service_info)?;
    info!(device_id = %identity.device_id, port, "advertising on mDNS");
    Ok(())
}

/// Spawns a background task browsing for `_connectible._tcp.local.` and
/// maintaining `DiscoveryTable` (T-005). Entries are pruned on
/// `ServiceRemoved`; mdns-sd handles TTL expiry internally and emits the
/// same event, so no separate timeout loop is needed here.
pub fn spawn_browser(mdns: ServiceDaemon, local_device_id: String) -> Result<DiscoveryTable> {
    let table = DiscoveryTable::default();
    let receiver = mdns.browse(SERVICE_TYPE)?;
    let table_clone = table.clone();
    // T-C6: throttle per-advertiser resolve processing so a re-resolution
    // flood can't burn CPU. Keyed by device_id; MAX_DISCOVERED distinct
    // keys bounds this limiter's own memory too.
    let resolve_limiter: RateLimiter<String> =
        RateLimiter::new(RESOLVES_PER_DEVICE, RESOLVE_WINDOW, MAX_DISCOVERED);

    tokio::task::spawn_blocking(move || {
        while let Ok(event) = receiver.recv() {
            match event {
                ServiceEvent::ServiceResolved(info) => {
                    if let Some(device) = parse_discovered(&info) {
                        if device.device_id == local_device_id {
                            continue; // do not discover ourselves
                        }
                        if !resolve_limiter.check(device.device_id.clone()) {
                            debug!(device_id = %device.device_id, "resolve rate limit exceeded; skipping");
                            continue;
                        }
                        debug!(device_id = %device.device_id, addr = %device.addr, "device discovered");
                        table_clone.insert(device);
                    } else {
                        warn!(
                            fullname = info.get_fullname(),
                            "malformed mDNS TXT records, ignoring"
                        );
                    }
                }
                ServiceEvent::ServiceRemoved(_ty_domain, fullname) => {
                    let id = fullname.split('.').next();
                    table_clone.remove_by_fullname_prefix(id);
                }
                _ => {}
            }
        }
    });

    Ok(table)
}

fn parse_discovered(info: &ServiceInfo) -> Option<DiscoveredDevice> {
    let props = info.get_properties();
    let device_id = props.get_property_val_str("device_id")?.to_string();
    let device_name = props
        .get_property_val_str("device_name")
        .unwrap_or("Unknown Device")
        .to_string();
    let platform = props
        .get_property_val_str("platform")
        .unwrap_or("PLATFORM_UNSPECIFIED")
        .to_string();
    let protocol_version = props
        .get_property_val_str("protocol_version")
        .unwrap_or("0")
        .to_string();
    let addr = info.get_addresses().iter().next().copied()?;

    Some(DiscoveredDevice {
        device_id,
        device_name,
        platform,
        protocol_version,
        addr,
        port: info.get_port(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Builds a `ServiceInfo` the same way `advertise()` does (T-004):
    /// `my_name` is the device_id, so the fullname's first label matches
    /// what `spawn_browser`'s `ServiceRemoved` handling extracts and
    /// passes to `remove_by_fullname_prefix` as its hint.
    fn make_service_info(properties: &[(&str, &str)], addr: &str) -> ServiceInfo {
        ServiceInfo::new(
            SERVICE_TYPE,
            "test-device-1",
            "test-host.local.",
            addr,
            7777,
            properties,
        )
        .expect("valid service info")
    }

    #[test]
    fn parse_discovered_returns_device_for_well_formed_service_info() {
        let info = make_service_info(
            &[
                ("device_id", "test-device-1"),
                ("device_name", "Test Phone"),
                ("platform", "PLATFORM_ANDROID"),
                ("protocol_version", "1"),
            ],
            "127.0.0.1",
        );

        let device = parse_discovered(&info).expect("well-formed info must parse");
        assert_eq!(device.device_id, "test-device-1");
        assert_eq!(device.device_name, "Test Phone");
        assert_eq!(device.platform, "PLATFORM_ANDROID");
        assert_eq!(device.protocol_version, "1");
        assert_eq!(device.addr, "127.0.0.1".parse::<IpAddr>().unwrap());
        assert_eq!(device.port, 7777);
    }

    #[test]
    fn parse_discovered_fills_in_defaults_for_missing_optional_properties() {
        // Only device_id is required; device_name/platform/protocol_version
        // fall back to defaults rather than making the whole record
        // malformed.
        let info = make_service_info(&[("device_id", "test-device-1")], "127.0.0.1");

        let device = parse_discovered(&info).expect("device_id alone must be enough to parse");
        assert_eq!(device.device_id, "test-device-1");
        assert_eq!(device.device_name, "Unknown Device");
        assert_eq!(device.platform, "PLATFORM_UNSPECIFIED");
        assert_eq!(device.protocol_version, "0");
    }

    #[test]
    fn parse_discovered_returns_none_when_device_id_is_missing() {
        // Malformed record: no device_id TXT property at all -- this is
        // the path that makes spawn_browser's ServiceResolved handler
        // log "malformed mDNS TXT records" and skip the entry instead of
        // inserting a device with an empty/placeholder id.
        let info = make_service_info(
            &[
                ("device_name", "Test Phone"),
                ("platform", "PLATFORM_ANDROID"),
            ],
            "127.0.0.1",
        );

        assert!(
            parse_discovered(&info).is_none(),
            "missing device_id must be treated as malformed"
        );
    }

    #[test]
    fn parse_discovered_returns_none_when_no_address_is_resolved() {
        // Malformed in a different way: TXT records are fine but mDNS
        // never resolved an address for the instance.
        let info = make_service_info(&[("device_id", "test-device-1")], "");

        assert!(
            parse_discovered(&info).is_none(),
            "an unresolved address must also be treated as malformed"
        );
    }

    #[test]
    fn discovery_table_insert_then_remove_by_fullname_prefix_removes_it() {
        let table = DiscoveryTable::default();
        table.insert(DiscoveredDevice {
            device_id: "test-device-1".to_string(),
            device_name: "Test Phone".to_string(),
            platform: "PLATFORM_ANDROID".to_string(),
            protocol_version: "1".to_string(),
            addr: "127.0.0.1".parse().unwrap(),
            port: 7777,
        });
        assert_eq!(table.list().len(), 1);

        table.remove_by_fullname_prefix(Some("test-device-1"));

        assert!(
            table.list().is_empty(),
            "entry must be gone after removal by its fullname prefix"
        );
    }

    fn dev(id: &str) -> DiscoveredDevice {
        DiscoveredDevice {
            device_id: id.to_string(),
            device_name: "d".to_string(),
            platform: "PLATFORM_UNSPECIFIED".to_string(),
            protocol_version: "1".to_string(),
            addr: "10.0.0.1".parse().unwrap(),
            port: 5000,
        }
    }

    #[test]
    fn discovery_table_caps_distinct_advertisers_but_still_updates_known() {
        let table = DiscoveryTable::default();
        for i in 0..MAX_DISCOVERED {
            table.insert(dev(&format!("dev-{i}")));
        }
        assert_eq!(table.list().len(), MAX_DISCOVERED);

        // A brand-new advertiser past the cap is dropped.
        table.insert(dev("overflow"));
        assert_eq!(table.list().len(), MAX_DISCOVERED);
        assert!(!table.list().iter().any(|d| d.device_id == "overflow"));

        // But a known device still updates (address change survives a full
        // table) without growing it.
        let mut updated = dev("dev-0");
        updated.addr = "10.0.0.2".parse().unwrap();
        table.insert(updated);
        assert_eq!(table.list().len(), MAX_DISCOVERED);
        let d0 = table.list().into_iter().find(|d| d.device_id == "dev-0").unwrap();
        assert_eq!(d0.addr.to_string(), "10.0.0.2");
    }

    #[test]
    fn discovery_table_remove_with_none_hint_is_a_no_op() {
        let table = DiscoveryTable::default();
        table.insert(DiscoveredDevice {
            device_id: "test-device-1".to_string(),
            device_name: "Test Phone".to_string(),
            platform: "PLATFORM_ANDROID".to_string(),
            protocol_version: "1".to_string(),
            addr: "127.0.0.1".parse().unwrap(),
            port: 7777,
        });

        table.remove_by_fullname_prefix(None);

        assert_eq!(
            table.list().len(),
            1,
            "a None hint must not remove anything"
        );
    }
}
