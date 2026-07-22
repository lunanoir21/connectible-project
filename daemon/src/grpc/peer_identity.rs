//! Phase G (T-G2): reads the fingerprint of the TLS client certificate a
//! connection presented, if any, out of tonic's request extensions.
//!
//! Tonic's built-in `impl<T: Connected> Connected for TlsStream<T>`
//! (gated behind the `tls-connect-info` feature, already enabled
//! transitively via the `tls-ring` feature in `daemon/Cargo.toml`)
//! populates a `TlsConnectInfo<TcpConnectInfo>` extension on every
//! request automatically, once the incoming stream handed to
//! `Server::serve_with_incoming_shutdown` is a `TlsStream<TcpStream>`
//! (see `tls::accept_loop`) -- no manual `Connected` impl needed here.

use tonic::transport::server::{TcpConnectInfo, TlsConnectInfo};
use tonic::Request;

use crate::tls::cert_fingerprint_hex;

/// The fingerprint of the client certificate presented on the
/// connection this request arrived over, if any. `None` when the
/// client presented no certificate (client auth is optional, T-G1) or
/// -- defensively -- when running over a non-TLS incoming stream (never
/// true in production; only a gap here would be a test harness bug).
pub fn peer_client_cert_fingerprint<T>(request: &Request<T>) -> Option<String> {
    let tls_info = request
        .extensions()
        .get::<TlsConnectInfo<TcpConnectInfo>>()?;
    let certs = tls_info.peer_certs()?;
    let end_entity = certs.first()?;
    Some(cert_fingerprint_hex(end_entity.as_ref()))
}
