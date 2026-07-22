//! Recent-error capture for the System Doctor (Phase F / T-F11).
//!
//! A process-global bounded ring buffer of the daemon's most recent
//! warn/error log lines, fed by a `tracing` [`Layer`] installed in the
//! daemon's subscriber. The [`RecentErrors`] diagnostics check reads it, so
//! a failing system surfaces the underlying log context in both
//! `connectibled doctor` and the app -- no log-file spelunking. Standalone
//! (the doctor CLI, no daemon) the buffer is simply empty.

use std::collections::VecDeque;
use std::sync::{Mutex, OnceLock};

use async_trait::async_trait;
use tracing::field::{Field, Visit};
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::layer::Context;
use tracing_subscriber::Layer;

use super::{Category, Check, CheckResult, DiagnosticsContext};

/// How many recent warn/error lines to retain.
const CAPACITY: usize = 50;

/// One captured log line.
#[derive(Debug, Clone)]
pub struct LogLine {
    pub level: &'static str,
    pub target: String,
    pub message: String,
}

fn buffer() -> &'static Mutex<VecDeque<LogLine>> {
    static BUF: OnceLock<Mutex<VecDeque<LogLine>>> = OnceLock::new();
    BUF.get_or_init(|| Mutex::new(VecDeque::with_capacity(CAPACITY)))
}

fn push(line: LogLine) {
    let mut buf = buffer().lock().unwrap_or_else(|p| p.into_inner());
    if buf.len() == CAPACITY {
        buf.pop_front();
    }
    buf.push_back(line);
}

/// A snapshot of the retained lines, oldest first.
pub fn recent() -> Vec<LogLine> {
    buffer()
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .iter()
        .cloned()
        .collect()
}

/// A `tracing` layer that captures warn/error events into the ring buffer.
/// Add it to the daemon subscriber; it never captures below WARN, so normal
/// info/debug logging is untouched.
pub struct CaptureLayer;

impl<S: Subscriber> Layer<S> for CaptureLayer {
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        let level = *event.metadata().level();
        if level > Level::WARN {
            return; // only WARN and ERROR (Level ordering: ERROR < WARN < INFO)
        }
        let mut visitor = MessageVisitor::default();
        event.record(&mut visitor);
        push(LogLine {
            level: if level == Level::ERROR { "error" } else { "warn" },
            target: event.metadata().target().to_string(),
            message: visitor.message,
        });
    }
}

#[derive(Default)]
struct MessageVisitor {
    message: String,
}

impl Visit for MessageVisitor {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.message = format!("{value:?}");
            // Debug of a &str wraps it in quotes; strip them for readability.
            if self.message.starts_with('"') && self.message.ends_with('"') {
                self.message = self.message[1..self.message.len() - 1].to_string();
            }
        }
    }
}

/// Diagnostics check that reports the most recent warn/error log lines.
pub struct RecentErrors;

#[async_trait]
impl Check for RecentErrors {
    fn id(&self) -> &'static str {
        "recent-errors"
    }
    fn title(&self) -> &'static str {
        "Recent errors & warnings"
    }
    fn category(&self) -> Category {
        Category::Features
    }
    async fn run(&self, _ctx: &DiagnosticsContext) -> CheckResult {
        let lines = recent();
        let errors = lines.iter().filter(|l| l.level == "error").count();
        let warns = lines.len() - errors;

        if lines.is_empty() {
            return CheckResult::ok(self, "No recent errors or warnings")
                .with_data("errors", "0")
                .with_data("warnings", "0");
        }

        // Show the last few lines as context.
        let tail: Vec<String> = lines
            .iter()
            .rev()
            .take(5)
            .map(|l| format!("[{}] {}: {}", l.level, l.target, l.message))
            .collect();
        let detail = tail.into_iter().rev().collect::<Vec<_>>().join("\n");

        let base = CheckResult::ok(self, format!("{errors} error(s), {warns} warning(s) logged"))
            .detail(detail)
            .with_data("errors", errors.to_string())
            .with_data("warnings", warns.to_string());

        if errors > 0 {
            base.warn(format!("{errors} recent error(s)"))
                .remediation("Review the lines above; a failing check nearby usually explains them.")
        } else {
            base
        }
    }
}
