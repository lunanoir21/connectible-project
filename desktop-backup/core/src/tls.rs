use std::sync::{Arc, Mutex};

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::CryptoProvider;
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};
use sha2::{Digest, Sha256};

/// Lowercase-hex SHA-256 of a certificate's DER encoding -- the TOFU
/// fingerprint format shared with the daemon store (Phase C / T-C2).
pub fn cert_fingerprint_hex(der: &[u8]) -> String {
    let digest = Sha256::digest(der);
    hex::encode(digest)
}

/// Trust-On-First-Use verifier for connections to *remote* Connectible
/// peers (T-C2/C3). The TLS handshake -- including handshake signature
/// verification against the presented certificate -- runs normally; there
/// is no CA (every peer is self-signed), so chain/identity validation is
/// replaced by **certificate pinning**:
///
///  - the presented end-entity cert's fingerprint is always recorded into
///    [`observed`](Self::observed) so the caller can pin it after the
///    connection succeeds (record-on-first-use / the T-C5 backfill);
///  - if a `pinned` fingerprint was supplied (a device we've connected to
///    before) and the presented cert does **not** match it, the handshake
///    is REJECTED -- a changed key means a re-keyed peer or an imposter,
///    never silently trusted.
///
/// Handshake signatures are still verified against the presented cert, so a
/// MITM cannot replay someone else's certificate without its private key.
/// The *local* daemon connection does NOT use this -- it pins the exact
/// cert file from the daemon's data dir (see local.rs).
#[derive(Debug)]
pub struct TofuVerifier {
    provider: Arc<CryptoProvider>,
    /// Expected fingerprint for this peer, if we have pinned it before.
    /// `None` = first use (accept + record).
    pinned: Option<String>,
    /// The fingerprint actually presented during the handshake, filled in
    /// by [`verify_server_cert`]. The caller reads this after a successful
    /// connect to record-on-first-use.
    observed: Arc<Mutex<Option<String>>>,
}

impl TofuVerifier {
    /// Builds a verifier for a peer whose pinned fingerprint is `pinned`
    /// (`None` for a never-before-seen peer). Returns the verifier and a
    /// shared handle to the observed fingerprint the caller pins afterward.
    pub fn new(pinned: Option<String>) -> (Arc<Self>, Arc<Mutex<Option<String>>>) {
        let observed = Arc::new(Mutex::new(None));
        let verifier = Arc::new(Self {
            provider: Arc::new(rustls::crypto::ring::default_provider()),
            pinned,
            observed: observed.clone(),
        });
        (verifier, observed)
    }
}

impl ServerCertVerifier for TofuVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> std::result::Result<ServerCertVerified, rustls::Error> {
        let fingerprint = cert_fingerprint_hex(end_entity.as_ref());
        // Always record what we saw so the caller can pin on first use.
        if let Ok(mut slot) = self.observed.lock() {
            *slot = Some(fingerprint.clone());
        }
        match &self.pinned {
            // A pin exists and the presented cert does not match it: block.
            // The message carries FINGERPRINT_CHANGED so the caller can map
            // it to a distinct, actionable error code.
            Some(pin) if pin != &fingerprint => Err(rustls::Error::General(
                "FINGERPRINT_CHANGED: peer certificate does not match the pinned fingerprint".into(),
            )),
            // Matches, or first use (no pin): accept.
            _ => Ok(ServerCertVerified::assertion()),
        }
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
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
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use rustls::pki_types::{CertificateDer, ServerName, UnixTime};

    fn verify(v: &TofuVerifier, der: &[u8]) -> Result<(), rustls::Error> {
        let cert = CertificateDer::from(der.to_vec());
        let name = ServerName::try_from("example.com").unwrap();
        v.verify_server_cert(
            &cert,
            &[],
            &name,
            &[],
            UnixTime::since_unix_epoch(std::time::Duration::from_secs(0)),
        )
        .map(|_| ())
    }

    #[test]
    fn fingerprint_is_deterministic_lowercase_hex_sha256() {
        let fp = cert_fingerprint_hex(b"hello");
        assert_eq!(fp, cert_fingerprint_hex(b"hello"));
        assert_eq!(fp.len(), 64);
        assert!(fp
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
    }

    #[test]
    fn first_use_accepts_and_records_the_observed_fingerprint() {
        let (v, observed) = TofuVerifier::new(None);
        assert!(verify(&v, b"cert-bytes").is_ok());
        assert_eq!(
            observed.lock().unwrap().as_deref(),
            Some(cert_fingerprint_hex(b"cert-bytes").as_str())
        );
    }

    #[test]
    fn a_matching_pin_is_accepted() {
        let pin = cert_fingerprint_hex(b"cert-bytes");
        let (v, _observed) = TofuVerifier::new(Some(pin));
        assert!(verify(&v, b"cert-bytes").is_ok());
    }

    #[test]
    fn a_changed_pin_is_rejected_with_fingerprint_changed() {
        let (v, _observed) = TofuVerifier::new(Some(cert_fingerprint_hex(b"old-cert")));
        let err = verify(&v, b"new-cert").unwrap_err();
        assert!(format!("{err}").contains("FINGERPRINT_CHANGED"));
    }
}
