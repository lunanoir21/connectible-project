//! Network & transport checks (Phase F / T-F3): this host's primary LAN
//! address, whether the daemon's gRPC port is reachable, and that the TLS
//! certificate material is present. Deeper transport checks (live TLS 1.3
//! handshake, gRPC Ping/RTT, cert expiry, mDNS advertise/discover) run with
//! full fidelity when the engine is invoked inside the running daemon via
//! the F7 RPC; standalone they degrade to what a separate process can see.

use std::net::{TcpStream, UdpSocket};
use std::time::Duration;

use async_trait::async_trait;

use super::{Category, Check, CheckResult, DiagnosticsContext};

pub fn checks() -> Vec<Box<dyn Check>> {
    vec![
        Box::new(OwnAddress),
        Box::new(PortReachable),
        Box::new(TlsCertPresent),
    ]
}

pub struct OwnAddress;

#[async_trait]
impl Check for OwnAddress {
    fn id(&self) -> &'static str {
        "lan-address"
    }
    fn title(&self) -> &'static str {
        "LAN address"
    }
    fn category(&self) -> Category {
        Category::Network
    }
    async fn run(&self, _ctx: &DiagnosticsContext) -> CheckResult {
        match primary_lan_ip() {
            Some(ip) => CheckResult::ok(self, format!("Reachable at {ip}"))
                .summary_key("doctor.msg.lanAddress.reachable")
                .with_data("address", ip),
            None => CheckResult::ok(self, "No LAN address")
                .warn("Not connected to a network")
                .summary_key("doctor.msg.lanAddress.none")
                .detail("No non-loopback IPv4 address is bound.")
                .remediation("Connect this device to the same Wi-Fi/LAN as its peers.")
                .remediation_key("doctor.msg.lanAddress.none.remediation"),
        }
    }
}

pub struct PortReachable;

#[async_trait]
impl Check for PortReachable {
    fn id(&self) -> &'static str {
        "daemon-port"
    }
    fn title(&self) -> &'static str {
        "Daemon port"
    }
    fn category(&self) -> Category {
        Category::Network
    }
    async fn run(&self, ctx: &DiagnosticsContext) -> CheckResult {
        let port = ctx.config.grpc_port;
        let addr = format!("127.0.0.1:{port}");
        // A short blocking connect on a spawn_blocking thread keeps the
        // async runtime free and bounds the wait.
        let addr2 = addr.clone();
        let reachable = tokio::task::spawn_blocking(move || {
            addr2
                .parse()
                .ok()
                .and_then(|a| TcpStream::connect_timeout(&a, Duration::from_millis(750)).ok())
                .is_some()
        })
        .await
        .unwrap_or(false);

        if reachable {
            CheckResult::ok(self, format!("Listening on port {port}"))
                .summary_key("doctor.msg.daemonPort.reachable")
                .with_data("port", port.to_string())
        } else {
            CheckResult::ok(self, format!("Port {port} not reachable"))
                .error(format!("Nothing is listening on port {port}"))
                .summary_key("doctor.msg.daemonPort.unreachable")
                .detail(format!("TCP connect to {addr} failed."))
                .remediation("Start the daemon (connectibled), or check that no firewall blocks the port.")
                .remediation_key("doctor.msg.daemonPort.unreachable.remediation")
                .with_data("port", port.to_string())
        }
    }
}

pub struct TlsCertPresent;

#[async_trait]
impl Check for TlsCertPresent {
    fn id(&self) -> &'static str {
        "tls-cert"
    }
    fn title(&self) -> &'static str {
        "TLS certificate"
    }
    fn category(&self) -> Category {
        Category::Network
    }
    async fn run(&self, ctx: &DiagnosticsContext) -> CheckResult {
        let cert = ctx.config.tls_dir.join("cert.pem");
        let key = ctx.config.tls_dir.join("key.pem");
        let cert_ok = cert.is_file();
        let key_ok = key.is_file();
        if cert_ok && key_ok {
            CheckResult::ok(self, "Certificate and key present")
                .summary_key("doctor.msg.tlsCert.present")
                .with_data("cert", cert.display().to_string())
        } else {
            let (missing, summary_key) = match (cert_ok, key_ok) {
                (false, false) => ("certificate and key", "doctor.msg.tlsCert.missingBoth"),
                (false, true) => ("certificate", "doctor.msg.tlsCert.missingCert"),
                (true, false) => ("private key", "doctor.msg.tlsCert.missingKey"),
                (true, true) => unreachable!(),
            };
            CheckResult::ok(self, "TLS material missing")
                .error(format!("Missing TLS {missing}"))
                .summary_key(summary_key)
                .detail(format!("Expected under {}", ctx.config.tls_dir.display()))
                .remediation("Start the daemon once -- it generates a self-signed cert/key on first run.")
                .remediation_key("doctor.msg.tlsCert.missing.remediation")
        }
    }
}

/// This host's primary outbound IPv4, found by asking the OS which local
/// address it would route from (a connected UDP socket sends no packets).
/// Dependency-free; returns `None` when offline.
fn primary_lan_ip() -> Option<String> {
    let sock = UdpSocket::bind("0.0.0.0:0").ok()?;
    // 203.0.113.0/24 is TEST-NET-3 (RFC 5737) -- never actually contacted,
    // just used to pick a route/source address.
    sock.connect("203.0.113.1:80").ok()?;
    let ip = sock.local_addr().ok()?.ip();
    if ip.is_loopback() || ip.is_unspecified() {
        None
    } else {
        Some(ip.to_string())
    }
}
