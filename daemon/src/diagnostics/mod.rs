//! System Doctor diagnostics engine (Phase F).
//!
//! A single source of truth for "is the whole system healthy" checks,
//! runnable both from the terminal (`connectibled doctor`, F6) and from the
//! apps via a loopback RPC (F7) -- CLI and UI call the exact same [`Check`]s,
//! so results can never drift.
//!
//! Each check reports a [`Status`] (ok / warn / error), a plain-language
//! [`summary`](CheckResult::summary), an optional detail + remediation, and
//! optional structured [`data`](CheckResult::data). The [`Registry`] runs
//! all or one and rolls up the worst severity.

pub mod cli;
pub mod environment;
pub mod features;
pub mod logbuf;
pub mod network;
pub mod pairing;

use std::collections::BTreeMap;

use async_trait::async_trait;
use serde::Serialize;

use crate::config::Config;

/// Severity of a single check. Ordered so `Ord::max` yields the worst
/// status across a set (Ok < Warn < Error), which the roll-up relies on.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Ok,
    Warn,
    Error,
}

impl Status {
    pub fn as_str(self) -> &'static str {
        match self {
            Status::Ok => "ok",
            Status::Warn => "warn",
            Status::Error => "error",
        }
    }
}

/// Groups checks in reports/UI. Kept small and stable.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Category {
    Environment,
    Network,
    Pairing,
    Features,
}

impl Category {
    pub fn as_str(self) -> &'static str {
        match self {
            Category::Environment => "environment",
            Category::Network => "network",
            Category::Pairing => "pairing",
            Category::Features => "features",
        }
    }
}

/// The outcome of one check.
#[derive(Debug, Clone, Serialize)]
pub struct CheckResult {
    pub id: String,
    pub title: String,
    pub category: Category,
    pub status: Status,
    /// One-line, plain-language result ("Download directory is writable").
    pub summary: String,
    /// Optional longer context (paths, measured values, the underlying
    /// error text).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    /// Optional concrete fix for a warn/error ("Create the directory or
    /// point the override file elsewhere").
    #[serde(skip_serializing_if = "Option::is_none")]
    pub remediation: Option<String>,
    /// Optional structured extras for machine consumers / the UI.
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub data: BTreeMap<String, String>,
    /// Stable machine id for the exact wording of `summary` (T-X43), so a
    /// client can render a localized template instead of the daemon's raw
    /// English -- interpolated against `data` for any dynamic values.
    /// `None` when this exact result has no stable template (should not
    /// normally happen for a known check, but a client always falls back
    /// to `summary` verbatim so a missing key never blanks the UI).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub summary_key: Option<&'static str>,
    /// Same fallback contract as `summary_key`, for `remediation`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub remediation_key: Option<&'static str>,
}

impl CheckResult {
    /// Starts an `ok` result for `check`; chain `.warn()`/`.error()` /
    /// `.detail()` / `.remediation()` / `.with_data()` to refine it.
    pub fn ok(check: &dyn Check, summary: impl Into<String>) -> Self {
        Self {
            id: check.id().to_string(),
            title: check.title().to_string(),
            category: check.category(),
            status: Status::Ok,
            summary: summary.into(),
            detail: None,
            remediation: None,
            data: BTreeMap::new(),
            summary_key: None,
            remediation_key: None,
        }
    }

    pub fn status(mut self, status: Status, summary: impl Into<String>) -> Self {
        self.status = status;
        self.summary = summary.into();
        self
    }

    pub fn warn(self, summary: impl Into<String>) -> Self {
        self.status(Status::Warn, summary)
    }

    pub fn error(self, summary: impl Into<String>) -> Self {
        self.status(Status::Error, summary)
    }

    pub fn detail(mut self, detail: impl Into<String>) -> Self {
        self.detail = Some(detail.into());
        self
    }

    pub fn remediation(mut self, remediation: impl Into<String>) -> Self {
        self.remediation = Some(remediation.into());
        self
    }

    pub fn with_data(mut self, key: &str, value: impl Into<String>) -> Self {
        self.data.insert(key.to_string(), value.into());
        self
    }

    /// Attaches T-X43's stable message id for the current `summary`. Call
    /// this last in each branch's chain, since `.warn()`/`.error()` change
    /// `summary` but not this field.
    pub fn summary_key(mut self, key: &'static str) -> Self {
        self.summary_key = Some(key);
        self
    }

    /// Attaches T-X43's stable message id for the current `remediation`.
    pub fn remediation_key(mut self, key: &'static str) -> Self {
        self.remediation_key = Some(key);
        self
    }
}

/// Read-only context handed to every check. Carries the daemon [`Config`]
/// (paths, port) plus optional live-daemon runtime facts populated only
/// when the engine runs *inside* the daemon (via the F7 RPC); standalone
/// CLI runs leave them `None` and the affected checks degrade gracefully.
pub struct DiagnosticsContext {
    pub config: Config,
    pub runtime: Option<DaemonRuntime>,
}

/// Live facts only the running daemon knows (uptime, resident memory).
pub struct DaemonRuntime {
    pub started_at: std::time::Instant,
}

impl DiagnosticsContext {
    pub fn standalone(config: Config) -> Self {
        Self {
            config,
            runtime: None,
        }
    }
}

/// One diagnostic check. Implemented by a zero-sized type per check so the
/// registry can address them by id.
#[async_trait]
pub trait Check: Send + Sync {
    fn id(&self) -> &'static str;
    fn title(&self) -> &'static str;
    fn category(&self) -> Category;
    async fn run(&self, ctx: &DiagnosticsContext) -> CheckResult;
}

/// A full run's results plus the worst-severity roll-up.
#[derive(Debug, Clone, Serialize)]
pub struct Report {
    pub results: Vec<CheckResult>,
    pub worst: Status,
}

impl Report {
    /// True if any check reported `error` -- the CLI exits nonzero on this.
    pub fn has_error(&self) -> bool {
        self.worst == Status::Error
    }
}

/// The set of registered checks. Built with [`default_registry`].
pub struct Registry {
    checks: Vec<Box<dyn Check>>,
}

impl Registry {
    pub fn new(checks: Vec<Box<dyn Check>>) -> Self {
        Self { checks }
    }

    /// Runs every check in registration order and rolls up the worst
    /// severity. Checks run sequentially -- diagnostics are not a hot path
    /// and sequential output is easier to read/stream.
    pub async fn run_all(&self, ctx: &DiagnosticsContext) -> Report {
        let mut results = Vec::with_capacity(self.checks.len());
        let mut worst = Status::Ok;
        for check in &self.checks {
            let result = check.run(ctx).await;
            worst = worst.max(result.status);
            results.push(result);
        }
        Report { results, worst }
    }

    /// Runs a single check by id, or `None` if no check has that id.
    pub async fn run_one(&self, id: &str, ctx: &DiagnosticsContext) -> Option<CheckResult> {
        for check in &self.checks {
            if check.id() == id {
                return Some(check.run(ctx).await);
            }
        }
        None
    }

    /// The ids/titles/categories of every registered check (for `--help`
    /// style listing and UI grouping) without running them.
    pub fn list(&self) -> Vec<(&'static str, &'static str, Category)> {
        self.checks
            .iter()
            .map(|c| (c.id(), c.title(), c.category()))
            .collect()
    }
}

/// The canonical registry: every check the CLI and UIs share, grouped by
/// category in report order (environment -> network -> pairing -> features).
pub fn default_registry() -> Registry {
    let mut checks = environment::checks();
    checks.extend(network::checks());
    checks.extend(pairing::checks());
    checks.extend(features::checks());
    checks.push(Box::new(logbuf::RecentErrors));
    Registry::new(checks)
}

#[cfg(test)]
pub(crate) fn test_context() -> DiagnosticsContext {
    let dir = std::env::temp_dir();
    DiagnosticsContext::standalone(Config {
        data_dir: dir.clone(),
        tls_dir: dir.clone(),
        transfers_dir: dir.clone(),
        db_path: dir.join("connectible-doctor-test.db"),
        grpc_port: 0,
        device_name: "test".into(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fixed(&'static str, Status);

    #[async_trait]
    impl Check for Fixed {
        fn id(&self) -> &'static str {
            self.0
        }
        fn title(&self) -> &'static str {
            self.0
        }
        fn category(&self) -> Category {
            Category::Environment
        }
        async fn run(&self, _ctx: &DiagnosticsContext) -> CheckResult {
            CheckResult::ok(self, "x").status(self.1, "x")
        }
    }

    #[tokio::test]
    async fn run_all_rolls_up_worst_severity() {
        let reg = Registry::new(vec![
            Box::new(Fixed("a", Status::Ok)),
            Box::new(Fixed("b", Status::Warn)),
            Box::new(Fixed("c", Status::Error)),
        ]);
        let report = reg.run_all(&test_context()).await;
        assert_eq!(report.results.len(), 3);
        assert_eq!(report.worst, Status::Error);
        assert!(report.has_error());
    }

    #[tokio::test]
    async fn run_one_by_id() {
        let reg = Registry::new(vec![Box::new(Fixed("a", Status::Warn))]);
        assert_eq!(
            reg.run_one("a", &test_context()).await.map(|r| r.status),
            Some(Status::Warn)
        );
        assert!(reg.run_one("missing", &test_context()).await.is_none());
    }

    #[tokio::test]
    async fn default_registry_runs_every_check() {
        let reg = default_registry();
        let report = reg.run_all(&test_context()).await;
        // All categories are represented and every check produced a result.
        assert_eq!(report.results.len(), reg.list().len());
        assert!(report
            .results
            .iter()
            .any(|r| r.category == Category::Environment));
        assert!(report.results.iter().any(|r| r.id == "recent-errors"));
    }
}
