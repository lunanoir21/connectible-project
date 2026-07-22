use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::sync::Arc;

use rustls::pki_types::{CertificateDer, PrivateKeyDer, UnixTime};
use rustls::server::danger::{ClientCertVerified, ClientCertVerifier};
use rustls::{DigitallySignedStruct, DistinguishedName, ServerConfig, SignatureScheme};
use sha2::{Digest, Sha256};
use tokio::net::{TcpListener, TcpStream};
use tokio_rustls::server::TlsStream;
use tokio_rustls::TlsAcceptor;
use tracing::warn;

use crate::config::Config;
use crate::error::{DaemonError, Result};
use crate::ratelimit::RateLimiter;

const CERT_FILE: &str = "cert.pem";

/// Lowercase-hex SHA-256 of a certificate's DER encoding -- must match
/// `desktop/core/src/tls.rs::cert_fingerprint_hex` exactly, since a
/// device's fingerprint is computed independently on whichever side
/// observes its certificate (the daemon here for an inbound client
/// cert, the desktop/mobile client for an outbound server cert) and
/// the two need to agree for pairing's TOFU pin to ever match (T-G4).
pub fn cert_fingerprint_hex(der: &[u8]) -> String {
    let digest = Sha256::digest(der);
    hex::encode(digest)
}

/// Accepts *any* client certificate at the TLS layer (Phase G, T-G1) --
/// this is intentionally not an authorization decision. Every device's
/// certificate is self-signed with no shared CA, so there is nothing to
/// "validate" about a client cert beyond "the client actually holds the
/// matching private key," which rustls itself already proves via the
/// handshake signature before `verify_client_cert` is even called.
///
/// The actual security check -- does this connection's certificate
/// match what was pinned for the `device_id` it claims to be -- happens
/// one layer up, per-RPC, against the fingerprint this verifier lets
/// through unexamined (see `grpc/service.rs`'s pairing-gate checks and
/// T-G5). Rejecting an unrecognized cert *here* would make first-contact
/// pairing impossible, since a never-before-seen device has nothing
/// pinned yet by definition.
///
/// Client auth is offered but not mandatory: a peer that presents no
/// certificate at all (e.g. an older build, or mid-migration before
/// every stack sends one) still completes the handshake; it simply has
/// no fingerprint to check against downstream, and is treated as
/// unauthenticated the same way a pre-Phase-G connection always was.
#[derive(Debug)]
struct AcceptAnyClientCert {
    provider: Arc<rustls::crypto::CryptoProvider>,
}

impl AcceptAnyClientCert {
    fn new() -> Self {
        Self {
            provider: Arc::new(rustls::crypto::ring::default_provider()),
        }
    }
}

impl ClientCertVerifier for AcceptAnyClientCert {
    fn offer_client_auth(&self) -> bool {
        true
    }

    fn client_auth_mandatory(&self) -> bool {
        false
    }

    fn root_hint_subjects(&self) -> &[DistinguishedName] {
        &[]
    }

    fn verify_client_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _now: UnixTime,
    ) -> std::result::Result<ClientCertVerified, rustls::Error> {
        Ok(ClientCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.provider
            .signature_verification_algorithms
            .supported_schemes()
    }
}

/// T-C8: per-source-IP connection accept limits. A single IP opening more
/// than [`ACCEPTS_PER_IP`] TLS connections within [`ACCEPT_WINDOW`] is a
/// connection flood; further sockets from it are dropped before the
/// (relatively expensive) TLS handshake, so a flood can't exhaust the
/// handshake worker pool or file descriptors. The values are generous
/// relative to legitimate use (reconnect storms, multiple app windows) so
/// only a genuine flood is throttled. `ACCEPT_MAX_IPS` bounds memory
/// against a spoofed-source flood.
const ACCEPTS_PER_IP: u32 = 30;
const ACCEPT_WINDOW: std::time::Duration = std::time::Duration::from_secs(10);
const ACCEPT_MAX_IPS: usize = 4096;
const KEY_FILE: &str = "key.pem";

/// Loads (generating on first run, T-008) this daemon's TLS identity and
/// builds a `rustls::ServerConfig` restricted to TLS 1.3 only.
///
/// tonic's built-in `Server::tls_config()` always negotiates whichever
/// protocol versions the compiled-in rustls supports, which includes
/// TLS 1.2 as soon as any dependency in the build enables that cargo
/// feature (unavoidable given Cargo's additive feature unification).
/// To honor the "TLS 1.3 mandatory, no fallback" requirement, the
/// daemon does not use `tls_config()` at all: it terminates TLS itself
/// with a `ServerConfig` built via `builder_with_protocol_versions(&[
/// &rustls::version::TLS13])`, then hands the already-decrypted stream
/// to tonic through `Server::serve_with_incoming` (see main.rs).
/// Loads (generating on first run) this device's one long-lived
/// self-signed cert/key pair as raw PEM strings, without building a
/// `rustls::ServerConfig` around them. Split out of
/// `load_or_create_server_config` (Phase G, T-G3) so the *same*
/// identity can also be presented as this device's TLS *client*
/// certificate when it connects out to a peer -- there is only ever
/// one identity per device, used in both roles.
pub fn load_or_create_identity_pem(tls_dir: &Path) -> Result<(String, String)> {
    let cert_path = tls_dir.join(CERT_FILE);
    let key_path = tls_dir.join(KEY_FILE);

    if cert_path.exists() && key_path.exists() {
        Ok((
            std::fs::read_to_string(&cert_path)?,
            std::fs::read_to_string(&key_path)?,
        ))
    } else {
        generate_self_signed(&cert_path, &key_path)
    }
}

pub fn load_or_create_server_config(config: &Config) -> Result<Arc<ServerConfig>> {
    let (cert_pem, key_pem) = load_or_create_identity_pem(&config.tls_dir)?;

    let cert_chain = parse_cert_chain(&cert_pem)?;
    let key = parse_private_key(&key_pem)?;

    let mut server_config =
        ServerConfig::builder_with_protocol_versions(&[&rustls::version::TLS13])
            .with_client_cert_verifier(Arc::new(AcceptAnyClientCert::new()))
            .with_single_cert(cert_chain, key)
            .map_err(|e| DaemonError::Tls(format!("invalid cert/key: {e}")))?;

    // HTTP/2 is required for gRPC; without this ALPN entry some clients
    // will refuse to negotiate h2 over the TLS session.
    server_config.alpn_protocols = vec![b"h2".to_vec()];

    Ok(Arc::new(server_config))
}

fn parse_cert_chain(pem: &str) -> Result<Vec<CertificateDer<'static>>> {
    let mut reader = std::io::Cursor::new(pem.as_bytes());
    rustls_pemfile::certs(&mut reader)
        .collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|e| DaemonError::Tls(format!("failed to parse certificate PEM: {e}")))
}

fn parse_private_key(pem: &str) -> Result<PrivateKeyDer<'static>> {
    let mut reader = std::io::Cursor::new(pem.as_bytes());
    rustls_pemfile::private_key(&mut reader)
        .map_err(|e| DaemonError::Tls(format!("failed to parse private key PEM: {e}")))?
        .ok_or_else(|| DaemonError::Tls("no private key found in PEM file".into()))
}

fn generate_self_signed(cert_path: &Path, key_path: &Path) -> Result<(String, String)> {
    let subject_alt_names = vec!["localhost".to_string()];
    let cert_key = rcgen::generate_simple_self_signed(subject_alt_names)
        .map_err(|e| DaemonError::Tls(format!("cert generation failed: {e}")))?;

    let cert_pem = cert_key.cert.pem();
    let key_pem = cert_key.key_pair.serialize_pem();

    write_private(cert_path, &cert_pem)?;
    write_private(key_path, &key_pem)?;

    Ok((cert_pem, key_pem))
}

/// Writes a file already restricted to owner read/write (0600), per the
/// security checklist requirement that private key material is never
/// world- or group-readable.
///
/// The file is created with mode 0600 from the very first `open(2)`
/// call (via `OpenOptions::mode`), rather than being written with
/// default (umask-derived) permissions and then `chmod`'d afterward --
/// that write-then-chmod sequence leaves a TOCTOU window where the key
/// material is on disk with looser permissions than intended (T-113).
/// `create_new(true)` additionally ensures we never write through a
/// pre-existing symlink or file left by another process.
fn write_private(path: &Path, contents: &str) -> Result<()> {
    use std::io::Write;

    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    file.write_all(contents.as_bytes())?;
    Ok(())
}

/// Binds `addr` and returns a channel of TLS-1.3-terminated streams
/// ready to be passed to `tonic::transport::Server::serve_with_incoming`.
/// A single misbehaving/failed client handshake never brings down the
/// accept loop -- it is logged and the loop continues.
pub async fn accept_loop(
    addr: std::net::SocketAddr,
    tls_config: Arc<ServerConfig>,
) -> Result<tokio::sync::mpsc::Receiver<std::io::Result<TlsStream<TcpStream>>>> {
    let listener = TcpListener::bind(addr).await?;
    let acceptor = TlsAcceptor::from(tls_config);
    let (tx, rx) = tokio::sync::mpsc::channel(16);
    // T-C8: per-IP accept rate limiting. Keyed by source IP (not ip:port,
    // since a flooder rolls source ports) so all of one host's sockets
    // share a budget.
    let ip_limiter: Arc<RateLimiter<std::net::IpAddr>> = Arc::new(RateLimiter::new(
        ACCEPTS_PER_IP,
        ACCEPT_WINDOW,
        ACCEPT_MAX_IPS,
    ));

    tokio::spawn(async move {
        loop {
            let (socket, peer_addr) = match listener.accept().await {
                Ok(pair) => pair,
                Err(e) => {
                    warn!(error = %e, "tcp accept failed");
                    continue;
                }
            };
            if !ip_limiter.check(peer_addr.ip()) {
                warn!(%peer_addr, "connection rate limit exceeded; dropping socket");
                // Drop `socket` without handshaking. `continue` returns to
                // accepting; the flooder's excess sockets are shed cheaply.
                continue;
            }
            let acceptor = acceptor.clone();
            let tx = tx.clone();
            tokio::spawn(async move {
                match acceptor.accept(socket).await {
                    Ok(tls_stream) => {
                        let _ = tx.send(Ok(tls_stream)).await;
                    }
                    Err(e) => {
                        warn!(%peer_addr, error = %e, "tls handshake failed");
                    }
                }
            });
        }
    });

    Ok(rx)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt as _;

    /// T-113: the private-key/cert file must be created with 0600 from
    /// the first `open(2)` call. This does not, by itself, prove there
    /// was never a wider-permission window (that would require racing
    /// another process against the `open` syscall), but it does verify
    /// the code path no longer performs a separate `set_permissions`
    /// step after a default-mode `write` -- the file lands at 0600
    /// immediately and stays there.
    #[test]
    fn write_private_creates_file_with_owner_only_permissions() {
        let dir = std::env::temp_dir().join(format!(
            "connectibled-tls-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("system clock before unix epoch")
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).expect("failed to create temp test dir");
        let path = dir.join("key.pem");

        write_private(&path, "dummy private key contents").expect("write_private failed");

        let mode = std::fs::metadata(&path)
            .expect("failed to stat written file")
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600, "expected mode 0600, got {mode:o}");

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// `write_private` must not silently overwrite an existing file
    /// (e.g. left behind by another process) -- `create_new` should
    /// make that an error rather than a TOCTOU-prone overwrite.
    #[test]
    fn write_private_refuses_to_overwrite_existing_file() {
        let dir = std::env::temp_dir().join(format!(
            "connectibled-tls-test-existing-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("system clock before unix epoch")
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).expect("failed to create temp test dir");
        let path = dir.join("key.pem");

        write_private(&path, "first").expect("first write_private failed");
        let result = write_private(&path, "second");
        assert!(result.is_err(), "expected an error on a pre-existing file");

        let _ = std::fs::remove_dir_all(&dir);
    }
}
