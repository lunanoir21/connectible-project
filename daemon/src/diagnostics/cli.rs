//! Terminal interface for the System Doctor (Phase F / T-F6):
//! `connectibled doctor [--json] [--check <id>]`.
//!
//! Runs the same [`default_registry`](super::default_registry) the app UIs
//! consume (via the F7 RPC), prints a colored table + worst-severity
//! summary, and exits nonzero if any check errored so it is scriptable.

use std::io::IsTerminal;

use crate::config::Config;

use super::{default_registry, DiagnosticsContext, Report, Status};

/// Parsed `doctor` invocation.
pub struct DoctorArgs {
    pub json: bool,
    pub check: Option<String>,
}

impl DoctorArgs {
    /// Parses the args *after* the `doctor` subcommand. Unknown flags are
    /// ignored rather than fatal, keeping the CLI forgiving.
    pub fn parse(args: &[String]) -> Self {
        let mut json = false;
        let mut check = None;
        let mut i = 0;
        while i < args.len() {
            match args[i].as_str() {
                "--json" => json = true,
                "--check" => {
                    check = args.get(i + 1).cloned();
                    i += 1;
                }
                other if other.starts_with("--check=") => {
                    check = Some(other["--check=".len()..].to_string());
                }
                _ => {}
            }
            i += 1;
        }
        Self { json, check }
    }
}

/// Runs the doctor and returns the process exit code (0 ok/warn, 1 if any
/// check errored, 2 for a usage error such as an unknown `--check` id).
pub async fn run(config: Config, args: DoctorArgs) -> i32 {
    let registry = default_registry();
    let ctx = DiagnosticsContext::standalone(config);

    if let Some(id) = &args.check {
        match registry.run_one(id, &ctx).await {
            Some(result) => {
                let report = Report {
                    worst: result.status,
                    results: vec![result],
                };
                emit(&report, args.json);
                exit_code(&report)
            }
            None => {
                eprintln!("unknown check id: {id}");
                eprint!("available checks:");
                for (cid, _, _) in registry.list() {
                    eprint!(" {cid}");
                }
                eprintln!();
                2
            }
        }
    } else {
        let report = registry.run_all(&ctx).await;
        emit(&report, args.json);
        exit_code(&report)
    }
}

fn exit_code(report: &Report) -> i32 {
    if report.has_error() {
        1
    } else {
        0
    }
}

fn emit(report: &Report, json: bool) {
    if json {
        // Hand-rolled compact JSON avoids pulling serde_json just for the
        // CLI; the RPC path (F7) carries the structured form to the UIs.
        match serde_json_string(report) {
            Ok(s) => println!("{s}"),
            Err(_) => println!("{{\"error\":\"serialization failed\"}}"),
        }
        return;
    }
    print_table(report);
}

/// Serializes via serde if serde_json is available; falls back to a minimal
/// manual encoder otherwise. We keep it dependency-light by encoding by
/// hand from the already-`Serialize` types' public fields.
fn serde_json_string(report: &Report) -> Result<String, ()> {
    let mut out = String::from("{\"worst\":\"");
    out.push_str(report.worst.as_str());
    out.push_str("\",\"results\":[");
    for (i, r) in report.results.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push('{');
        push_kv(&mut out, "id", &r.id);
        out.push(',');
        push_kv(&mut out, "category", r.category.as_str());
        out.push(',');
        push_kv(&mut out, "status", r.status.as_str());
        out.push(',');
        push_kv(&mut out, "title", &r.title);
        out.push(',');
        push_kv(&mut out, "summary", &r.summary);
        if let Some(d) = &r.detail {
            out.push(',');
            push_kv(&mut out, "detail", d);
        }
        if let Some(rem) = &r.remediation {
            out.push(',');
            push_kv(&mut out, "remediation", rem);
        }
        out.push('}');
    }
    out.push_str("]}");
    Ok(out)
}

fn push_kv(out: &mut String, key: &str, value: &str) {
    out.push('"');
    out.push_str(key);
    out.push_str("\":\"");
    out.push_str(&json_escape(value));
    out.push('"');
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn print_table(report: &Report) {
    let color = std::io::stdout().is_terminal();
    for r in &report.results {
        println!(
            "{}  {:<32}  {}",
            badge(r.status, color),
            r.title,
            r.summary
        );
        if let Some(rem) = &r.remediation {
            if r.status != Status::Ok {
                println!("      -> {rem}");
            }
        }
    }
    println!();
    println!(
        "Overall: {} ({} checks)",
        badge(report.worst, color),
        report.results.len()
    );
}

fn badge(status: Status, color: bool) -> String {
    let (label, code) = match status {
        Status::Ok => ("[ OK ]", "32"),
        Status::Warn => ("[WARN]", "33"),
        Status::Error => ("[FAIL]", "31"),
    };
    if color {
        format!("\x1b[{code}m{label}\x1b[0m")
    } else {
        label.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_json_and_check_flags() {
        let a = DoctorArgs::parse(&["--json".into()]);
        assert!(a.json && a.check.is_none());

        let b = DoctorArgs::parse(&["--check".into(), "disk-space".into()]);
        assert_eq!(b.check.as_deref(), Some("disk-space"));
        assert!(!b.json);

        let c = DoctorArgs::parse(&["--check=tls-cert".into(), "--json".into()]);
        assert_eq!(c.check.as_deref(), Some("tls-cert"));
        assert!(c.json);

        // Unknown flags are ignored, not fatal.
        let d = DoctorArgs::parse(&["--bogus".into()]);
        assert!(!d.json && d.check.is_none());
    }
}
