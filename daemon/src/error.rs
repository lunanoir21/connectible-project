use crate::proto::connectible::v1::ErrorCode;

/// Project-wide error type for fallible daemon operations. Library code
/// returns `Result<T, DaemonError>` rather than `anyhow::Error`; `anyhow`
/// is reserved for `main.rs` startup-time invariants only (see RULES.md).
#[derive(Debug, thiserror::Error)]
pub enum DaemonError {
    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("database migration error: {0}")]
    Migration(#[from] sqlx::migrate::MigrateError),

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),

    #[error("tls/cert error: {0}")]
    Tls(String),

    #[error("clipboard error: {0}")]
    Clipboard(String),

    #[error("input error: {0}")]
    Input(String),

    #[error("mdns error: {0}")]
    Mdns(#[from] mdns_sd::Error),

    #[error("device not found: {0}")]
    DeviceNotFound(String),

    #[error("pairing rejected: {0}")]
    PairingRejected(String),

    #[error("pairing timed out")]
    PairingTimeout,

    #[error("invalid pin")]
    InvalidPin,

    #[error("rate limited: {0}")]
    RateLimited(String),
}

impl DaemonError {
    /// Maps this error onto the wire-level `ErrorCode` enum so RPC
    /// handlers can build a consistent `Error` proto message instead of
    /// leaking internal error text to callers.
    pub fn code(&self) -> ErrorCode {
        match self {
            DaemonError::DeviceNotFound(_) => ErrorCode::DeviceNotFound,
            DaemonError::PairingRejected(_) => ErrorCode::PairingRejected,
            DaemonError::PairingTimeout => ErrorCode::PairingTimeout,
            DaemonError::InvalidPin => ErrorCode::PairingRejected,
            DaemonError::RateLimited(_) => ErrorCode::RateLimited,
            _ => ErrorCode::Internal,
        }
    }
}

pub type Result<T> = std::result::Result<T, DaemonError>;
