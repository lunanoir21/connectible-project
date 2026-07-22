# ADR-001: Desktop talks to the daemon from the Tauri Rust core, not gRPC-Web from the webview

Status: Accepted
Date: 2026-07-09
Supersedes: the "communicating with daemon via gRPC-Web client" line in the
original brief for the desktop component.

## Context

The original plan called for the Tauri desktop UI to talk to the local
daemon "via a gRPC-Web client" from the React frontend. In practice that
approach has significant friction for this project:

1. gRPC-Web needs a proxy (e.g. Envoy or an in-process translation
   layer) because browsers/webviews cannot speak raw HTTP/2 gRPC
   framing. The daemon speaks standard gRPC over HTTP/2 + TLS; bolting a
   gRPC-Web translation onto it is extra moving parts for a loopback
   connection.
2. The daemon's TLS listener is TLS 1.3 with a self-signed cert. Getting
   a webview `fetch`/gRPC-Web stack to trust exactly that one cert (and
   nothing else) is awkward and platform-dependent; doing it from Rust
   with tonic's `ClientTlsConfig::ca_certificate` is one line and
   precisely scoped.
3. The most security-sensitive RPCs (`SubscribeLocalEvents`,
   `GetLocalState`) are loopback-gated and carry the pairing PIN in
   plaintext. Terminating them in the trusted Rust process, then handing
   already-shaped DTOs to the webview, keeps the PIN out of any
   webview-reachable network surface.

## Decision

The desktop app talks to the daemon **from the Tauri Rust core** using
the same `tonic` client the daemon's own tests use. The React frontend
never opens a network connection; it calls Tauri **commands**
(request/response) and receives Tauri **events** (daemon push -> UI),
both defined in `desktop/src-tauri/src`.

All of that client logic lives in a separate crate,
`connectible-desktop-core` (`desktop/core`), which has **no Tauri or
webview dependency**. That crate:

- pins the local daemon's self-signed cert read from its data dir
  (`local.rs`),
- accepts remote daemons' self-signed certs under the documented MVP
  trust model (`tls.rs`, `remote.rs`),
- converts proto messages to camelCase serde DTOs for the frontend
  (`dto.rs`).

The Tauri shell (`desktop/src-tauri`) is a thin layer that wires those
core functions to Tauri commands, events, and the system tray.

## Consequences

- **Testability**: `connectible-desktop-core` builds and its integration
  tests run against a real in-process daemon in any environment the
  daemon builds in -- no webview toolchain required. This is why the
  desktop's real logic has end-to-end test coverage
  (`desktop/core/tests/desktop_core_e2e.rs`) even though the Tauri shell
  itself needs system webkit libraries to compile.
- **No proxy**: no Envoy/gRPC-Web bridge to deploy or configure.
- **Single source of protocol truth**: the core crate depends on the
  daemon crate for generated proto types and even reuses the daemon's
  chunked file-`send_file` implementation, so the desktop can never
  drift from the daemon's wire format.
- **Trade-off**: the frontend contract is now the Tauri command/event
  surface (see `desktop/src/lib/ipc.ts`) rather than the proto service
  directly. That surface is small and typed on both sides, which we
  consider a net simplification.

## Note on the original brief

The brief's "gRPC-Web" wording is treated as describing intent ("the UI
talks to the daemon over gRPC") rather than a hard mechanism. The wire
protocol between *daemons* and between *mobile and daemon* is unchanged
standard gRPC over TLS 1.3 exactly as specified; only the desktop UI's
*internal* path to its own local daemon differs, and only for the
reasons above.
