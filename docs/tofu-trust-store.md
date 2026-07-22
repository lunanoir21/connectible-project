# TOFU Trust Store (Phase C / T-C1 design)

**Status:** design (T-C1). Implemented by T-C2..T-C5.
**Goal:** replace the "accept any self-signed cert" MVP posture with
Trust-On-First-Use certificate pinning, so a re-keyed or impersonating
peer is detected instead of silently trusted.

## Current posture (what exists today)

- Each device generates one long-lived **self-signed** cert on first run
  (`daemon/src/tls.rs::generate_self_signed`, mobile equivalent). There is
  no CA.
- TLS 1.3 with **server-only** auth: the daemon server uses
  `with_no_client_auth()` (`daemon/src/tls.rs:48`), so a server never sees
  the connecting client's certificate.
- The **client** side verifies the server cert with
  `AcceptSelfSignedCert` (`desktop/core/src/tls.rs`): the handshake
  signature IS checked (so a MITM can't replay a cert without its private
  key), but chain/identity validation is skipped and **any** self-signed
  cert is accepted. This is the exact seam TOFU replaces.
- The **local** loopback connection already pins the exact cert file the
  daemon wrote (`desktop/core/src/local.rs::pinned_tls_config`) — that is
  not TOFU and is unaffected.
- The daemon's `devices` table **already has a `cert_fingerprint TEXT`
  column** (`daemon/src/db/repository.rs` `DeviceRecord.cert_fingerprint`),
  currently always NULL — `upsert_paired` never sets it. Mobile persists
  paired peers as JSON in `device_list_model.dart` (`_pairedStore`), with
  no fingerprint field yet.

## Trust model: the client pins the server

Because only the client observes a certificate, TOFU is **client-pins-
server**. Pairing is bidirectional (both devices run a gRPC/TLS server and
both dial out as a client), so each device pins the *other's server cert*
in its own client role:

- Desktop ecosystem dialing a peer → `desktop/core` client pins the peer
  server's cert.
- Mobile dialing the daemon → mobile client pins the daemon server's cert.

Net effect: after a successful pair, **both** directions are pinned.

### Fingerprint definition

`fingerprint = lowercase_hex(SHA-256(end_entity_cert_DER))`.

Whole end-entity DER (not just SPKI) — simplest, and our certs only change
on a data-dir reset, which is exactly the "key changed, re-verify" event we
want to catch. The end-entity cert is available directly in the client
verifier's `verify_server_cert(end_entity: &CertificateDer, ...)`.

## Storage

- **Daemon:** reuse `devices.cert_fingerprint`. Add repository methods
  `set_fingerprint(device_id, fp)` and read it via existing `get`. No new
  migration needed for the column (it exists); a migration note only for
  backfill semantics (see T-C5).
- **Mobile:** add an optional `certFingerprint` to the persisted paired
  record (`device_list_model.dart` `_pairedStore` JSON) plus the in-memory
  `DeviceInfo`.

## Capture (T-C2 / T-C4) and verify (T-C3 / T-C4)

The client verifier is constructed with a **`TrustStore` handle** plus the
**target `device_id`** (always known before dialing — you dial a specific
paired peer). In `verify_server_cert`:

1. Compute `fp` of `end_entity`.
2. Look up the pinned fp for `device_id`:
   - **None pinned** (first successful use — pairing, or a pre-TOFU device):
     record `fp` as the pin (**record-on-first-use**) and accept. This is
     the "trust on first use" step and also the T-C5 migration backfill.
   - **Pinned == fp:** accept (seamless reconnect).
   - **Pinned != fp:** **reject** the handshake (return a `rustls::Error`)
     and surface a `FingerprintChanged { device_id, expected, actual }`
     warning to the UI. The user resolves it explicitly by *forgetting +
     re-pairing* the device (which clears the pin so the next connect
     records the new key). We never silently trust a changed key.

### Daemon: observe-in-client vs store-in-daemon-DB

On the desktop side the observer (`desktop/core` client) and the store
(daemon SQLite) are different processes. The `TrustStore` the verifier
holds is therefore an interface with two impls:

- desktop/core: backed by the daemon over a **loopback-only** RPC pair —
  `GetPinnedFingerprint(device_id) -> Option<fp>` and
  `RecordFingerprint(device_id, fp)` (record-on-first-use + backfill).
  These live next to the existing loopback local-events RPCs and must be
  rejected off-loopback, same as those.
- mobile: backed directly by the on-device paired store (same process).

The daemon-as-server continues to use `no_client_auth`; it does **not**
gain client-cert verification. All pinning happens on the dialing side.

## Mismatch decision flow (UI)

- Block the connection; do not fall back to unpinned.
- Emit a distinct, localized error (`FINGERPRINT_CHANGED`) — not a raw TLS
  error — so both UIs can show: "The security key for <device> changed.
  If you didn't reinstall Connectible on it, this could be an imposter.
  To reconnect, forget and re-pair the device."
- Provide the forget→re-pair path (already exists: `forgetDevice` /
  `delete`), which clears the pin so re-pairing records the new key.

## Migration for existing paired devices (T-C5)

No forced re-pair. Devices paired before TOFU have `cert_fingerprint =
NULL` / no `certFingerprint`. The **record-on-first-use** branch above
backfills the pin on their next successful connect. This is a
trust-on-first-*reconnect* window (acceptable: it matches the original
pairing's trust assumption and closes permanently after one connect).

## Test plan

- Daemon repo unit test: set/get fingerprint; NULL→record→match→mismatch.
- Verifier unit test (both cores): none-pinned records+accepts; equal
  accepts; different rejects with the mismatch signal.
- Integration: pair over real TLS, reconnect (seamless), then swap the
  peer cert and confirm the reconnect is blocked with `FINGERPRINT_CHANGED`.
- Migration: a device row with NULL fp connects once, fp is backfilled, and
  the subsequent connect is a seamless match.
