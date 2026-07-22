//! Daemon-client core for the Connectible desktop app.
//!
//! Everything the Tauri shell needs to talk to (a) the local daemon
//! over loopback TLS and (b) remote Connectible daemons for pairing,
//! file transfer, and remote input lives here. The crate deliberately
//! has no Tauri/webview dependency, so it compiles and its tests run
//! in any environment the daemon itself builds in -- the Tauri shell
//! (`../src-tauri`) is a thin command-wiring layer over this crate.
//!
//! Architecture note (ADR-001, see ../docs/): the desktop UI talks to
//! the daemon over plain gRPC/TLS from the Tauri Rust core, not via
//! gRPC-Web from the webview. See the ADR for the reasoning.

pub mod dto;
pub mod local;
pub mod remote;
pub mod tls;

pub use local::LocalDaemonClient;
pub use remote::RemoteDeviceClient;

use connectibled::proto::connectible::v1::ErrorCode;

/// Errors surfaced to the Tauri command layer. Stringly-typed at the
/// boundary (Tauri serializes command errors as strings for the
/// frontend), but structured here so core logic and tests can match.
#[derive(Debug, thiserror::Error)]
pub enum DesktopError {
    #[error("daemon is not reachable: {0}")]
    DaemonUnreachable(String),

    #[error("transport error: {0}")]
    Transport(#[from] tonic::transport::Error),

    #[error("rpc failed: {0}")]
    Rpc(#[from] tonic::Status),

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),

    #[error("invalid address: {0}")]
    InvalidAddress(String),

    /// A peer sent back an explicit `Error` envelope (T-602) -- e.g. the
    /// responder side of `Pair`/`ConfirmPin` rejecting with a real
    /// `ErrorCode` such as `RATE_LIMITED`. Distinct from `Rpc`/`Other`
    /// because the code is exact here, not inferred from a gRPC status.
    #[error("{message}")]
    Remote { code: ErrorCode, message: String },

    #[error("{0}")]
    Other(String),
}

impl DesktopError {
    /// Maps this error onto the wire-level `ErrorCode` enum (T-602),
    /// mirroring `DaemonError::code()` on the daemon side
    /// (`daemon/src/error.rs`) so the Tauri command boundary can hand
    /// the frontend a structured code instead of only `Display` text
    /// (see design-docs/error-code-mapping.md). Variants that did not
    /// originate from an explicit proto `Error` envelope fall back to a
    /// best-effort inference from the gRPC status code -- the daemon's
    /// own `to_status` (grpc/service.rs) already collapses several
    /// `ErrorCode`s onto the same `tonic::Code`, so mapping back here is
    /// necessarily lossy for those; `Remote` (built from the peer's own
    /// `Error.code`) is the precise path.
    pub fn code(&self) -> ErrorCode {
        match self {
            DesktopError::DaemonUnreachable(_) => ErrorCode::Unspecified,
            DesktopError::Transport(_) => ErrorCode::Unspecified,
            DesktopError::Rpc(status) => match status.code() {
                tonic::Code::NotFound => ErrorCode::DeviceNotFound,
                tonic::Code::PermissionDenied => ErrorCode::Unauthenticated,
                tonic::Code::DeadlineExceeded => ErrorCode::PairingTimeout,
                tonic::Code::ResourceExhausted => ErrorCode::RateLimited,
                tonic::Code::FailedPrecondition => ErrorCode::UnsupportedPlatform,
                tonic::Code::Aborted => ErrorCode::FileTransferFailed,
                _ => ErrorCode::Internal,
            },
            DesktopError::Io(_) => ErrorCode::Unspecified,
            DesktopError::InvalidAddress(_) => ErrorCode::Unspecified,
            DesktopError::Remote { code, .. } => *code,
            DesktopError::Other(_) => ErrorCode::Unspecified,
        }
    }

    /// The wire `ErrorCode`'s name without the `ERROR_CODE_` prefix
    /// (e.g. `"DEVICE_NOT_FOUND"`) -- the exact key
    /// `desktop/src/lib/errors.ts`'s `errorCodeMessage` table is indexed
    /// by, so the Tauri command layer can hand it to the frontend as
    /// plain data (T-602).
    pub fn code_name(&self) -> &'static str {
        self.code().as_str_name().trim_start_matches("ERROR_CODE_")
    }
}

pub type Result<T> = std::result::Result<T, DesktopError>;
