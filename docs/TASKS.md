# Connectible - Road to v1.0.0: Completion Criteria (Phased Task Breakdown)

**Created:** 2026-07-19. Supersedes the previous root `TASKS.md`
(mobile pairing/QR + desktop UI simplification work), archived at
[`TASKS-v1.0-pairing-ui.md`](archive/TASKS-v1.0-pairing-ui.md) — that work is
done. Also supersedes the four still-open items from
[`TASKS-v1.0-filetransfer.md`](archive/TASKS-v1.0-filetransfer.md) (T-A20,
T-A21, T-A22, T-B3): T-A20/21/22 are re-tracked below as Phase I;
T-B3 is re-tracked as Phase N. Do not pick those four up from the old
file — this one is current.

## Why this exists

Two reports were produced on 2026-07-19: a code audit (36 findings,
all now fixed and verified — daemon/desktop/mobile test suites all
green) and a follow-on roadmap report scoring every existing feature
against concrete completion criteria. This file is the phased,
task-level breakdown of that roadmap report's "existing features
completion" section (its section 02) — every criterion marked open
there gets a phase here. It does not re-derive the "1.0.0 zorunlu"
release-mechanics items (LICENSE, version bump, release-pipeline tag
test) or the "sonraki faz" platform-expansion items (Windows/macOS/
iOS) from that report's other sections — those are tracked in the
report itself, not duplicated into task form here, since they are
either one-shot mechanical steps or multi-month platform work with no
immediate task breakdown value yet.

Phase lettering continues from the archived file-transfer roadmap
(which ran A-F) starting at G, so cross-references between the two
files stay unambiguous.

## How to work this file

One phase at a time. Every task is small on purpose: it should be
completable and verifiable on its own. Check a task off only when its
**Acceptance** holds (automated tests where possible; real-device where
noted). Keep every stack compiling green after each task.

**Status keys:** `[ ]` todo, `[~]` in progress, `[x]` done, `[-]` cut/skip.
**Field keys:** *Files* = where the work lands; *Depends* = must land first;
*Acceptance* = definition of done.

## Working style (Luna)

- Reply in **Turkish** in chat; keep all code, comments, and docs
  **English/ASCII**.
- Phase-grind: finish a whole phase without asking for per-task
  confirmation; only stop for steps that need a real device, or a
  decision flagged **ASK FIRST**.
- Phase N (battery, real-device) is explicitly deferred — Luna said to
  set device/adb work aside for now. Don't start it unprompted.

---

## Phase G — Close the mTLS identity gap

**Status: complete (2026-07-20).** All 10 tasks done. Full verification
at phase end: `cargo test --workspace` green, `cargo clippy --workspace
--all-targets -- -D warnings` clean, `flutter analyze` clean,
`flutter test` 140/140 green, desktop `tsc --noEmit` clean. One real
regression was caught and fixed during this pass, not before it shipped:
T-G6's first attempt (requesting a client cert on mobile's own inbound
server) hung every real pairing test at a 60s timeout by breaking the
TLS handshake outright -- root-caused to a genuine `dart:io` platform
limitation (no custom client-cert verifier, unlike rustls) via an
isolated reproduction, then reverted to an app-layer-only check. See
T-G6's own entry for the full account.

**Why:** the one open item from the code audit's Yuksek (High) findings.
TOFU pinning already exists (`tofu-trust-store.md`) but only in one
direction: the *client* pins the *server's* certificate fingerprint per
device_id and verifies it on reconnect. Nothing verifies the reverse —
every RPC handler that gates on `is_paired(device_id)` trusts a
client-declared string with no cryptographic binding to the TLS session
it arrived on. `with_no_client_auth()` in `daemon/src/tls.rs` means the
server never even asks for a client certificate today. Anyone on the
LAN who learns a paired device's `device_id` (trivially discoverable —
it's in every mDNS TXT record and gRPC response) can open their own TLS
connection and impersonate that device in `UploadFile`/`PrepareUpload`/
any SyncStream frame.

The fix is symmetric to what already exists for server-side TOFU: each
device already has one long-lived self-signed identity (the same
cert/key pair `tls.rs` generates once and reuses as *its own server's*
identity). Reuse that same identity as the device's *client* identity
too, request client certs on the server side, and pin the presented
client certificate's fingerprint the same way `RecordFingerprint`
already pins the server-side one — bootstrapped once, during a
successful pairing.

### T-G1: Request (not require) client certificates on the daemon's TLS listener `[x]`
**Done.** `AcceptAnyClientCert` (implements `rustls::server::danger::
ClientCertVerifier`) replaces `.with_no_client_auth()`:
`offer_client_auth=true`, `client_auth_mandatory=false`, accepts any
presented cert unexamined (the actual trust decision is per-RPC, T-G5).
Also added `cert_fingerprint_hex` to `daemon/src/tls.rs`, matching
`desktop/core/src/tls.rs`'s algorithm exactly (SHA-256 of DER,
lowercase hex) so fingerprints computed on either side of a connection
agree. `cargo check -p connectibled` clean.
Change `load_or_create_server_config` in `daemon/src/tls.rs` from
`.with_no_client_auth()` to a client-cert-optional verifier: accept any
self-signed certificate presented (mirroring the existing client-side
accept-self-signed verifier used when connecting *out* to a peer), but
do not reject connections that present none — an unpaired first-contact
peer (still doing initial `Pair`) has nothing to pin yet.
*Files:* `daemon/src/tls.rs`.
*Acceptance:* a connection with no client cert still completes the TLS
handshake (existing pairing flow unaffected); a connection presenting
one completes too and the cert is retrievable from the session.

### T-G2: Surface the peer's client-cert fingerprint to gRPC handlers `[x]`
**Done -- simpler than planned.** tonic already ships a blanket
`impl<T: Connected> Connected for TlsStream<T>` behind the
`tls-connect-info` feature (already on transitively via daemon's
existing `tls-ring` feature), which auto-populates a
`TlsConnectInfo<TcpConnectInfo>` request extension carrying the peer's
cert chain -- no manual `Connected` impl needed. New
`daemon/src/grpc/peer_identity.rs::peer_client_cert_fingerprint(&request)`
reads it. `cargo check -p connectibled` clean.

<details><summary>original plan (superseded by the above)</summary>

tonic doesn't expose the raw rustls session by default; thread the
accepted peer certificate (if any) through as a tonic connection
`Extension` at accept time (in `main.rs`'s `serve_with_incoming`, next
to where the TLS stream is terminated) so every handler can read
`request.extensions().get::<PeerCertFingerprint>()`.
*Files:* `daemon/src/main.rs`, new small module e.g. `daemon/src/grpc/peer_identity.rs`.
*Depends:* T-G1.
*Acceptance:* a handler-level unit/integration test proves the
extension carries the correct SHA-256 fingerprint of the cert the test
client presented, and is absent when the client presented none.

</details>

### T-G3: Reuse each device's own server identity as its client identity `[x]`
**Done (desktop half; mobile is T-G6).** `daemon::tls::
load_or_create_server_config` split into a new pub
`load_or_create_identity_pem(tls_dir: &Path)` (loads-or-generates the
raw PEM pair) so `desktop/core/src/remote.rs` can reuse the exact same
identity-loading logic. `RemoteDeviceClient::connect`/`connect_pinned`
now take a `data_dir: &Path` first argument, load
`<data_dir>/tls/{cert,key}.pem`, and set it via
`ClientTlsConfig::identity(...)` alongside the existing TOFU
`tls_config_with_verifier` call (confirmed via tonic's own doc comment
that `identity` "continues to apply" when combined with a custom
verifier). Updated all 3 call sites in `commands.rs` (via the existing
`daemon_endpoint()` helper) and all 4 in `desktop_core_e2e.rs` (new
`own_identity_dir()` test helper, deliberately a separate temp dir from
the test daemon's own, since the client and the daemon it connects to
are different devices). `cargo check --workspace --tests` clean.

<details><summary>original plan</summary>

When a `RemoteDeviceClient` (desktop) or `ConnectibleServer`'s outbound
client (mobile) initiates a connection to a peer, present this
device's own long-lived cert/key (the same one `tls.rs`/mobile's
equivalent generates for being a server) as the TLS client
certificate, instead of connecting with no client identity at all.
*Files:* `desktop/core/src/remote.rs`, `daemon/src/tls.rs` (helper to
load the identity for client use), mobile's `grpc_service.dart` /
`connectible_server.dart` equivalent.
*Depends:* T-G1.
*Acceptance:* an outbound connection's client cert, inspected
server-side via T-G2's extension, matches the connecting device's known
identity.

</details>

### T-G4: Pin the client-cert fingerprint on successful pairing `[x]`
**Done -- landed in `confirm_pin` (grpc/service.rs), not `PairingManager::
confirm` itself.** `confirm_pin` is always called by the *confirming*
device (its own comment already establishes `req.device_id` is the
caller's own id, "not the target device's id"), so the connection this
RPC arrives on is exactly the one whose client cert should be pinned to
that device_id. Captures `peer_client_cert_fingerprint(&request)`
before `into_inner()`, then -- after the existing `upsert_paired` --
calls `self.devices.set_fingerprint(...)`, best-effort (a device with
no client cert yet still pairs; nothing pinned, same as pre-Phase-G).
Symmetric to the existing client-side TOFU pin-on-first-use. Works for
both pairing directions since either side can run this handler as
responder. `cargo check -p connectibled` clean.

<details><summary>original plan</summary>

In `PairingManager::confirm`'s success path (`daemon/src/pairing/mod.rs`),
if the confirming connection presented a client certificate, record its
fingerprint against the newly-paired `device_id` — same table, same
`set_fingerprint` method already used for the server-side TOFU pin,
just called from the responder's side of the handshake instead of only
the requester's. Handles both pairing directions since either side can
be responder.
*Files:* `daemon/src/pairing/mod.rs`, `daemon/src/grpc/service.rs`
(`confirm_pin` handler, to pass the extension through).
*Depends:* T-G2, T-G3.
*Acceptance:* new test: two real daemons pair over real TLS; after
`confirm_pin` succeeds, `devices.cert_fingerprint` for the requester's
row (read from the responder's DB) is non-null and matches the
requester's actual cert.

</details>

### T-G5: Gate every paired-only RPC on fingerprint match, not just device_id `[x]`
**Done -- `upload_file` needed no change (see finding below).** New
`ConnectibleService::verify_peer_identity(device_id, client_fingerprint)
-> PeerIdentityCheck` (`Ok`/`NotPaired`/`FingerprintMismatch`) is the
shared check; wired into `handle_frame` (fingerprint captured once in
`sync_stream` before `into_inner()`, threaded through the per-frame
loop) and `prepare_upload` (captured the same way). A mismatch reuses
the existing `ErrorCode::FingerprintChanged` (`ERROR_CODE_
FINGERPRINT_CHANGED = 11`, already used for the symmetric client-side
TOFU case) rather than adding a new code -- same user-facing meaning
("this identity doesn't match what was pinned; re-pair if expected"),
so **T-G7 (new ErrorCode) is not needed and is folded into this task**.
A device with nothing pinned yet passes on the paired check alone (the
backfill grace window).

**Finding: `upload_file` needed no separate check.** It has no
`is_paired` call at all -- authorization is entirely via the opaque
ticket/token `prepare_upload` mints and `UploadRegistry::resolve`
redeems, which only exists because `prepare_upload`'s check already
passed. The token is intentionally bearer-style, not connection-bound
(it must be redeemable from a *new* connection after a dropped stream,
for resume) -- so binding it to a specific fingerprint would break
resume-after-drop, and would be redundant security theater on top of
an already-narrow, single-use, server-generated token. Left as-is.

The other `is_paired` call site (`record_fingerprint`, `service.rs`) is
`require_loopback`-gated -- callable only by this machine's own local
UI, not a remote peer -- so it is outside this phase's threat model
entirely and was correctly left untouched.

*Files:* `daemon/src/grpc/service.rs`.
*Acceptance:* `cargo check -p connectibled` and
`cargo clippy --workspace --all-targets -- -D warnings` both clean.
Also fixed one pre-existing, unrelated clippy `doc_lazy_continuation`
failure in `daemon/src/config.rs` (a stricter lint from a newer clippy
than this code was last checked against) so the workspace-wide clippy
gate stays green going forward. Real end-to-end proof (a third,
never-paired daemon spoofing a known device_id gets rejected) is
T-G8's `desktop_core_e2e.rs` test, run at the end of this phase per
Luna's "run tests last" instruction this session.

### T-G6: Apply the same model to mobile's own gRPC server `[x]`
**Done, but the TLS-layer half is not achievable on mobile -- see the
platform-limitation finding below. Landed instead: (a) a genuinely
bigger pre-existing gap than the task assumed, fixed; (b) mobile's
outbound identity presentation, which *does* work.**

**Platform limitation found and reverted.** First attempt requested a
client certificate on the inbound server
(`Server.serve(..., requestClientCertificate: true)`, `grpc: ^3.2.4`'s
equivalent of the daemon's optional-client-cert verifier) and read it
back via `ServiceCall.clientCertificate`. This broke every real
handshake: unlike rustls (where `ClientCertVerifier::verify_client_cert`
is fully custom code we control, T-G1's `AcceptAnyClientCert`),
`dart:io`'s `SecureServerSocket` always chain-verifies whatever
certificate a client presents and aborts the handshake outright on
failure -- there is no "accept any cert, decide later" hook on the
server side. Since every device's certificate is self-signed with no
shared CA (the whole point of this codebase's trust model), the server
rejected every connection with `HandshakeException:
CERTIFICATE_VERIFY_FAILED: self signed certificate`, confirmed with an
isolated `SecureServerSocket`/`SecureSocket` reproduction outside the
app before spending more time on it. This is why every
"requester pairing flow" test against a real responder hung for 60s
and then failed with "used after being disposed" once discovered
through this session's full-suite run -- reverted before landing.

**What actually shipped:**
- `GrpcService.connect` (`grpc_service.dart`) gained a `required
  ServerIdentity identity` param, presented as the outbound client cert
  via a new `_MtlsChannelCredentials` (subclasses `ChannelCredentials`,
  overrides `securityContext` to call `useCertificateChainBytes`/
  `usePrivateKeyBytes` -- the package's `ChannelCredentials.secure()`
  has no built-in client-identity option, unlike tonic's
  `ClientTlsConfig::identity`). This direction *does* work end to end:
  a real daemon (rustls, T-G1) can fully verify and pin the fingerprint
  of a connecting mobile client via its own T-G4/T-G5 machinery,
  already proven by the Rust test suite. `PairingModel` caches one
  `ServerIdentity` (`_loadOwnIdentity`, injectable via a new
  `ownIdentityLoader` constructor param for testability) and passes it
  to `startPair`/`reconnectToPeer`'s connects, alongside the existing
  inbound-server use -- same identity, either role.
- **The real fix, kept after reverting the TLS half:** mobile's
  `onInboundSyncStream` had **no pairing check on inbound frames at
  all** -- any device completing a TLS handshake to this phone's server
  could push clipboard/file frames unconditionally, and inbound
  `Identity` frames were silently dropped, so the app never even
  tracked *who* was connected. Now `_inboundPeerDeviceId` is set from
  the first `Identity` frame, and a new `_onInboundFrameFromRemotePeer`
  wrapper drops every other frame until that claimed device_id is
  confirmed paired -- fail-closed, dropped not replied to (mobile's
  SyncStream has no error-frame convention). This does **not** verify
  the connection's TLS identity against the claim (that would need the
  reverted mechanism) -- it closes the "no check at all" gap, not the
  full spoofing gap the daemon closes for itself.
- **Testability fix, found while wiring this up:** `startPair`/
  `reconnectToPeer` now unconditionally need this device's own identity,
  but `pairing_model_test.dart` deliberately used `pairableEnabled:
  false` to avoid `ServerIdentity.loadOrCreate()`'s `path_provider`
  dependency (unavailable in that unit-test host, per the file's own
  comment) -- that guard didn't cover the new code path. Added the
  `ownIdentityLoader` injection point to `PairingModel`'s constructor
  (defaults to the real loader) rather than adding a path_provider mock,
  matching the file's existing dependency-injection testing style; all
  five other test files constructing `PairingModel` were checked and
  don't exercise `startPair`/`reconnectToPeer`, so they needed no change.

*Files:* `mobile/lib/src/services/connectible_server.dart`,
`mobile/lib/src/services/grpc_service.dart`,
`mobile/lib/src/state/pairing_model.dart`,
`mobile/test/pairing_model_test.dart`,
`mobile/test/screens/remote_input_screen_test.dart`.
*Acceptance:* `flutter analyze` clean; full `flutter test` run
140/140 green (was hanging/timing out on 7 tests before the platform
-limitation revert). New tests in `pairing_model_test.dart`: inbound
frames from an unidentified peer are dropped; inbound frames from an
identified-but-never-paired peer are dropped. Existing "dispatches each
inbound frame kind" test updated to pair the device and send an
`Identity` frame first (previously exercised no attribution at all).

**Follow-up worth tracking separately if this gap matters enough to
revisit:** mobile's responder role has no cryptographic binding between
a claimed device_id and the connection presenting it -- a device that
somehow learned a paired peer's device_id could still claim it inbound.
Closing this fully would need either a Dart FFI/native TLS layer with
real custom verification (large), or an application-layer challenge
(e.g. the responder asks the claimed device_id to sign a nonce with its
known public key before trusting frames) -- both bigger than this
phase's scope. Not re-tracked as a numbered task here since it wasn't
part of the original request; flag to Luna if this asymmetry matters
before 1.0.0.

### T-G7: New ErrorCode for identity mismatch `[x]`
**Folded into T-G5 -- no new code needed.** The mismatch case reuses
`ErrorCode::FingerprintChanged` (already wired end to end: daemon
`to_status` maps it to `PermissionDenied`, desktop already has a
`FINGERPRINT_CHANGED` handling path from the existing client-side TOFU
check). `docs/design/error-code-mapping.md` doc update for the new
call site is folded into T-G10.

<details><summary>original plan</summary>

Add `ErrorCode::IDENTITY_MISMATCH` (or similarly named) to the shared
error-code scheme (`docs/design/error-code-mapping.md`'s table + both
sides' mapping code) with a plain-language message: "this device's
identity doesn't match what was pinned during pairing — if you didn't
re-pair or reinstall, someone else may be impersonating a paired
device. Forget and re-pair if this is expected (e.g. after reinstall)."
*Files:* `daemon/src/error.rs`, `desktop/src/lib/errors.ts`,
mobile's error-mapping equivalent, `docs/design/error-code-mapping.md`.
*Depends:* T-G5.
*Acceptance:* the mismatch case from T-G5's test surfaces this exact
code end to end (not a generic internal error).

</details>

### T-G8: desktop_core_e2e coverage `[x]`
**Written; not yet run (deferred to this session's end-of-work full
test pass, per Luna's instruction).** New
`upload_file_rejects_a_sender_claiming_another_devices_pinned_identity`:
pairs "desktop-ui-test" normally (pins its cert fingerprint), then a
second, distinct identity (different cert, never paired) calls
`upload_file` claiming `device_id: "desktop-ui-test"` in the request
body -- the `sender` field is caller-supplied, independent of the
actual TLS connection identity, which is exactly the spoofing vector
T-G5 closes. Asserts a `PermissionDenied` RPC error and that nothing
lands on disk. `cargo check -p connectible-desktop-core --tests` clean.
*Files:* `desktop/core/tests/desktop_core_e2e.rs`.
*Acceptance:* compiles clean; pass/fail confirmed in this phase's final
test run (see Phase G wrap-up note at the end of this file once all of
G is done).

### T-G9: System Doctor check `[x]`
**Already covered by the existing `PairedStore` check -- no new code.**
Read `daemon/src/diagnostics/pairing.rs`: it already counts paired
devices vs. `cert_fingerprint IS NOT NULL AND != ''`, and already warns
"N device(s) not yet cert-pinned" with a "pin automatically on next
connect" remediation when the two counts differ. T-G4 pins into the
exact same `devices.cert_fingerprint` column the client-side TOFU path
already wrote to (same column, whichever direction pins first) -- so
this check reports the new client-cert pinning state with zero changes,
by construction. Writing a near-duplicate second check would violate
RULES.md's anti-duplication guidance for no added value.

### T-G10: Update TOFU docs for the now-bidirectional model `[x]`
**Done.** `docs/tofu-trust-store.md` gets a new "Phase G: the daemon
also pins the client" section (full design, matching what actually
shipped) plus inline `**(Superseded by Phase G...)**` corrections on
the two sentences that flatly stated the old one-directional reality
("daemon-as-server continues to use no_client_auth... does not gain
client-cert verification") so a reader doesn't take stale text as
current. `docs/api-reference.md`'s "Transport & trust" section rewritten
to describe both pinning directions, the shared `cert_fingerprint`
column, the shared `FINGERPRINT_CHANGED` error, and the deliberate
`UploadFile` exception (bearer token, not connection-bound, for
resume).

---

## Phase H — SQLite at-rest encryption

**Status: complete (2026-07-20).** All 8 tasks done. Full verification:
`cargo test --workspace` 128/128 green (was 98 before this phase's new
tests), `cargo clippy --workspace --all-targets -- -D warnings` clean,
`flutter analyze` clean, desktop `tsc --noEmit` clean. `daemon/Cargo.toml`
gained `aes-gcm = "0.11"` and `keyring = "4.1.4"` (pinned below `4.1.5`
-- see T-H2's note on a registry-mirror resolution issue with that
patch version).

**Why:** `PLAN.md` explicitly flags plaintext device storage as an
"accepted high risk... track it as a v1.0 task," not a permanent
design choice. The roadmap report lists this as one of the two
remaining security-foundation gaps (alongside Phase G).

### T-H1: Decide the encryption approach and document why `[x]`
**Done.** `docs/design/db-encryption.md`: application-level AES-256-GCM
on just `cert_fingerprint`, not SQLCipher (musl+OpenSSL static-link
risk, and would encrypt data that's already broadcast in the clear over
mDNS/pairing anyway) and not the whole row/file (nothing else in
`devices` has a real disclosure consequence). Key sourced from
`CONNECTIBLE_DB_KEY_FILE` override > OS keyring (`keyring` crate,
`zbus-secret-service-keyring-store`, pure Rust) > a `0600` key file
fallback.

<details><summary>original plan</summary>
Evaluate SQLCipher (transparent, but a C dependency — check it can
still satisfy RULES.md's single statically-linked binary requirement)
against application-level column encryption (encrypt only
`cert_fingerprint` and any other sensitive columns with a key from the
OS keyring, leave SQLite's own file format untouched). Write the
decision and reasoning into a new `docs/design/db-encryption.md` before
writing any implementation code.
*Files:* new `docs/design/db-encryption.md`.
*Acceptance:* the doc names the chosen approach, the rejected
alternative, and the concrete reason (static-linking risk, migration
complexity, or similar) — not a preference statement alone.

</details>

### T-H2: Linux keyring integration for the DB encryption key `[x]`
**Done.** New `daemon/src/db/keys.rs::load_or_create_db_key`. Uses the
`keyring` crate v4 (`v1` + `zbus-secret-service-keyring-store` features
-- pure-Rust D-Bus client, no `libdbus` C dependency, so it doesn't
reintroduce the static-linking risk T-H1 rejected SQLCipher over) under
service `connectibled`, username `db-encryption-key`. Generates a fresh
32-byte key on first use (`Error::NoEntry`), stores it hex-encoded, and
reads the same key back on every later start. The blocking `keyring`
calls run via `tokio::task::spawn_blocking` under a 3s
`tokio::time::timeout` so a hung D-Bus connection attempt (headless host)
can't stall daemon startup -- ties directly into T-H3's fallback.
*Files:* `daemon/src/db/keys.rs`.
*Note on `Cargo.toml`:* pinned to `keyring = "4.1.4"` rather than the
newer `4.1.5` -- that patch version's manifest declares an
`apple-native-keyring-store = "^1.0.1"` requirement this environment's
registry mirror can't resolve (unrelated to any feature actually
enabled here, since `default-features = false` and only the Linux
backend is on). `4.1.4` resolves and builds clean; revisit the pin once
mirror sync catches up.

### T-H3: Headless/no-keyring fallback `[x]`
**Done, implemented together with T-H2 (same module, same function's
control flow -- the two are one fallback chain, not separable
changes).** `load_or_create_db_key` falls back to a `0600` key file at
`<data_dir>/tls/db.key` (`load_or_create_key_file`, mirroring
`tls.rs`'s cert/key file creation pattern exactly, including the
`create_new` TOCTOU-avoidance) whenever the keyring attempt returns
`None` for any reason (unreachable bus, timeout, locked store, no
entry-creation permission, ...) -- logged via `tracing::warn` with an
explicit note that this is expected for a headless systemd service.
*Files:* `daemon/src/db/keys.rs`.
*Acceptance:* new tests `load_or_create_key_file_persists_across_calls`
(second call reads back the same key, mode is `0600`) and
`load_or_create_key_file_rejects_a_malformed_existing_file`. Real
headless-host behavior (no session bus at all) will be exercised for
real the first time Luna runs this under her systemd unit -- the
timeout+fallback logic is unit-tested, not live-verified against an
actual missing D-Bus session in this sandbox.

### T-H4: Encrypt-in-place migration for existing plaintext databases `[x]`
**Done, with the mechanism adapted to T-H1's column-level (not
whole-file) encryption choice -- see below for why the "copy-then-
verify-then-replace whole file" original plan doesn't apply.** New
`DeviceRepository::migrate_plaintext_fingerprints()`: selects every row
with a non-null `cert_fingerprint`, skips anything already
`ENCRYPTED_PREFIX`-tagged, and for each legacy plaintext value:
encrypts it, decrypts the result back and asserts it matches the
original *before* writing anything (so a migration bug can never
silently corrupt a working pin), then writes via a single `UPDATE` --
SQLite's own durability already makes that one-row write atomic, so
there is no separate file-level copy/replace step to add on top; that
part of the original plan was written assuming whole-database-file
encryption (SQLCipher), which T-H1 explicitly did not choose. Called
once at every daemon startup (`lib.rs::run`, right after constructing
`DeviceRepository`) -- a no-op once every row is already migrated, so
it's safe to run unconditionally rather than needing a one-shot
version-gate.
*Files:* `daemon/src/db/repository.rs`, `daemon/src/lib.rs`.
*Acceptance:* new test `migrate_plaintext_fingerprints_encrypts_legacy_
rows_only` -- seeds one legacy-plaintext row (written directly via raw
SQL, bypassing `set_fingerprint`, exactly as a pre-Phase-H binary
would've left it) and one already-encrypted row; migration touches only
the legacy row, the raw on-disk value is no longer the plaintext
string afterward, `fingerprint()` still reads back the original value
correctly, and a second migration pass is a confirmed no-op.

### T-H5: `CONNECTIBLE_DB_KEY_FILE` override `[x]`
**Done, folded into T-H2/T-H3's `keys.rs` rather than `config.rs`** --
it's a key-*sourcing* concern, and keeping all three sources
(env > keyring > fallback file) in one function's priority chain in one
file is clearer than splitting the env-var branch out into `config.rs`
while its two siblings live in `keys.rs`. Reads the var, and if the
path doesn't exist yet, generates+writes a key there too (the same
`load_or_create_key_file` helper as the fallback path) rather than
hard-failing on a missing file -- consistent with this codebase's
existing "generate on first use" convention for `tls.rs`'s cert/key.
*Files:* `daemon/src/db/keys.rs`. README.md's env-var table update
folded into T-H8 (documenting the whole feature in one pass rather than
two separate doc edits).
*Acceptance:* covered by the same `load_or_create_key_file` tests as
T-H3 (it's the identical function, just given a caller-supplied path
instead of the default fallback location) -- pointing the var at a path
with an existing key file honors that key rather than regenerating one,
by construction (`path.exists()` check comes first).

### T-H6: System Doctor check for encryption status `[x]`
**Done.** New `DbEncryptionKeySource` check in
`daemon/src/diagnostics/environment.rs`, registered in
`environment::checks()`. Re-derives the source by calling the same
`load_or_create_db_key` the daemon used at startup (idempotent, reads
the same key back) rather than threading extra state through
`DiagnosticsContext`. `ok` for keyring/env-override; `warn` +
remediation for the fallback file (expected on headless systemd,
worth a look on a desktop session). Verified fast (~0.08s for the
whole diagnostics test group) in this sandbox where the keyring
attempt fails immediately rather than hitting its 3s timeout.
*Files:* `daemon/src/diagnostics/environment.rs`.
*Acceptance:* registered in the shared registry, so it's automatically
covered by `connectibled doctor`, the loopback `RunDiagnostics` RPC,
and both UI Doctor panels -- no separate wiring needed anywhere else.

### T-H7: Tests `[x]`
**Done.** Beyond T-H4's migration test (already covers round-trip
open/write/read on a fresh encrypted DB via the existing
`fingerprint_starts_null_then_records_and_reads_back` test, now
exercising the real encrypt/decrypt path): new
`wrong_key_fails_to_decrypt_cleanly_instead_of_panicking` (a second
`DeviceRepository` on the same pool with a different key gets a typed
`Err`, never `Ok(None)` or a panic) and
`concurrent_fingerprint_writes_all_round_trip_correctly` (10 concurrent
tasks against a 5-connection file-backed pool, each setting and
reading back its own device's fingerprint correctly -- had to switch
from `sqlite::memory:` to a temp file-backed DB for this one
specifically, since an in-memory SQLite DB is per-connection and a
multi-connection pool against `:memory:` would give each connection its
own empty database, making a genuine concurrency test meaningless).
*Files:* `daemon/src/db/repository.rs`, `daemon/src/db/keys.rs`.
*Acceptance:* 15/15 new+existing `db::` tests pass
(`cargo test -p connectibled db::`); full-workspace confirmation
deferred to this phase's end-of-work run per Luna's instruction.

### T-H8: Update docs removing the "plaintext" MVP-limitation language `[x]`
**Done.** `README.md`'s Security section: replaced the "certificate
identity isn't verified beyond the PIN" and "SQLite device storage is
plaintext" bullets with an accurate description of the now-bidirectional
TOFU pinning (linking `docs/tofu-trust-store.md`, including its mobile
asymmetry note) and the AES-256-GCM column encryption (linking
`docs/design/db-encryption.md`). `PLAN.md`: both non-goals bullets and
the risk-table row annotated `**Delivered, Phase G/H, 2026-07-20**`
rather than rewritten -- these are a historical MVP-planning record
(week-numbered risks, a point-in-time non-goals list), so the pattern
already used elsewhere in this codebase for superseded content
(inline "Superseded by..." / "Delivered..." annotations, not silent
rewrites) applies here too. Left the "Definition of done (MVP /
v0.1.0)" checklist's own limitations line untouched -- it's a
historical v0.1.0-specific acceptance record, not a live current-state
claim, and editing it retroactively would misrepresent what v0.1.0
actually shipped with.

---

## Phase I — Retire the legacy chunk-transfer path

**Why:** re-tracks `TASKS-v1.0-filetransfer.md`'s T-A20/T-A21/T-A22,
previously gated on "T-A25" (full regression validation), which this
session's 36-finding audit-fix pass and full green test suite
effectively satisfies. Two parallel file-transfer implementations
(the original `SyncStream`-multiplexed `FileChunk` frames, and the
dedicated `PrepareUpload`/`UploadFile` streaming path) is real ongoing
maintenance and consistency risk — the SyncStream-pairing-gate fix
earlier this session had to be applied to *both* paths independently,
which is exactly the kind of duplicated-fix-surface this phase removes.

### T-I1: Confirm feature parity before deleting anything `[x]`
**Done -- found one real, deliberately accepted gap; everything else
is at parity.**

| Capability | Legacy (`FileChunk`) | Dedicated (`UploadFile`) | Verdict |
|---|---|---|---|
| Resume after drop | ✓ (`FileTransferStart.resume_offset_bytes`) | ✓ (`resume_offset()`/`UploadFileOffer.resume_offset_bytes`, proven by `upload_file_resumes_after_a_dropped_stream`) | Parity |
| Cancel | ✓ (proven by `cancel_aborts_transfer_and_finalizes_nothing`, currently against `send_file`) | ✓ in code -- `RemoteDeviceClient::upload_file`'s feeder loop checks `cancel_flag` every read, breaks, ends the stream; daemon lands it in `UploadOutcome::Incomplete` (nothing finalized), identical outcome to the legacy path's cancel. **Not yet proven by an existing test against `upload_file` specifically** -- T-I3 ports the test. | Parity (code), test coverage closes in T-I3 |
| Progress reporting | ✓ | ✓ (`upload_file_delivers_intact_file_and_reports_progress`) | Parity |
| Whole-file hash verification | ✓ | ✓ (`upload_file_with_wrong_hash_is_not_finalized`) | Parity |
| **Per-chunk corrupted-chunk resend (T-306)** | ✓ -- CRC32 per `FileChunk`, a mismatch triggers a `FileChunkRequest` for just that one offset (`corrupted_chunk_triggers_resend_and_transfer_completes`) | **✗ absent.** `UploadFilePart` carries no per-chunk checksum; a whole-file SHA-256 mismatch (`UploadWriter::finish`) deletes the entire partial and forces a full restart, not a targeted resend. | **Real gap, accepted, not closed** -- see reasoning below. |

**Why the corrupted-chunk gap is an accepted trade-off, not a
blocker.** Traced `corrupted_chunk_triggers_resend_and_transfer_completes`
(`daemon/tests/grpc_smoke.rs`) to what it actually fault-injects: a test
proxy flips a byte of the **plaintext application-level `FileChunk.data`
before it enters the TLS-encrypted channel** -- simulating corruption
introduced by the sender's own code/memory, not network-transit
corruption. TLS 1.3's AEAD (AES-GCM) already cryptographically
guarantees that whatever the receiver decrypts is byte-identical to
what the sender encrypted, so this specific per-chunk CRC32 was never
protecting against transit corruption -- transit corruption is already
excluded by TLS on both paths. What it protects against (a bug in the
sender's own disk-read/chunking logic, a rare memory fault) is still
*caught* on the dedicated path -- the whole-file hash check never
silently accepts a corrupted upload -- just recovered from less
efficiently (full retry vs. one resent chunk). For a LAN sync tool this
is judged an acceptable cost for removing a second, independently-
maintained corruption-handling code path (the exact kind of
duplicated-fix-surface that caused the SyncStream pairing-gate bug to
need fixing twice, earlier this session). **Flagging this trade-off
explicitly rather than deciding it silently** -- Luna, say so if you'd
rather keep chunk-level resend and this phase should stop at T-I1.
*Files:* investigation only.
*Acceptance:* table above; proceeding with Phase I on this basis.

### T-I2: Remove `FileChunk` handling from the daemon `[x]`
**Done, together with T-I5 (proto reservation) and T-I6 (test sweep) --
the three were too entangled to land separately: removing the
`match`'s `FileChunk`/`FileTransferStart`/`FileChunkRequest` arms
without reserving the proto fields first leaves the `match`
non-exhaustive (compile error), and neither compiles green until the
now-orphaned tests are gone too.**

- `grpc/service.rs`: removed the three `Payload::*` arms from
  `handle_frame` and the now-dead `send_file_chunk_request` helper.
- `transfer/mod.rs`: this file lost roughly two-thirds of its content.
  Removed entirely: `TransferMeta`, `ChunkOutcome`, `TransferManager`'s
  `in_progress`/`transfers_dir` fields and every legacy method
  (`begin`, `note_corrupt_chunk`, `write_chunk`, `record_progress`,
  `emit_terminal`, `finalize`), `ResendRequest`, `send_file`,
  `send_file_with_resend`, `try_reserve_resend_attempt`,
  `resend_one_chunk`, `mime_guess_from_extension`, `hash_file`, and the
  `MAX_CHUNK_RESEND_ATTEMPTS`/`CHUNK_RESEND_GRACE_PERIOD` consts.
  `TransferManager` is now a thin progress-broadcast hub (`new`/
  `subscribe`/`progress_sender` only) -- `upload::UploadWriter` never
  touched its removed state at all, confirmed by grep before deleting.
  Kept, unchanged: `move_into_place`, `sanitize_file_name`,
  `unique_destination` (genuinely shared with `upload.rs`),
  `CHUNK_SIZE_BYTES`/`PROGRESS_EMIT_INTERVAL` consts (also used by
  `upload.rs` via `super::`).
- **T-I5, proto:** `proto/connectible.proto`'s `SyncFrame` oneof now has
  `reserved 3, 4, 9; reserved "file_transfer_start", "file_chunk",
  "file_chunk_request";` instead of those three field declarations; the
  `FileTransferStart`/`FileChunk`/`FileChunkRequest` message
  definitions themselves are deleted outright (protobuf has no
  "reserved message name" mechanism the way it does field numbers --
  only the oneof's wire-format slots needed protecting against reuse).
  Updated two stale doc comments elsewhere in the proto that referenced
  the removed messages (`TransferProgress.mime_type`'s comment, and the
  "Dedicated file upload" section header) rather than leaving them
  describing a plan that already happened.
- **T-I6, test sweep, done inline per file rather than as one pass at
  the end** (kept every file compiling+green as I went, rather than
  batch-breaking the whole suite then batch-fixing):
  - `daemon/tests/grpc_smoke.rs`: deleted `file_transfer_over_real_tls_
    lands_on_disk` (redundant with `upload_transfer.rs`'s
    `upload_file_lands_on_disk_after_prepare`) and
    `corrupted_chunk_triggers_resend_and_transfer_completes` (T-306 --
    per T-I1's finding, this property is a deliberately accepted gap
    on the dedicated path, not something to port). **Ported**
    `file_transfer_throughput_meets_target` to
    `daemon/tests/upload_transfer.rs` as `upload_file_throughput_meets_
    target` (same 64MB payload, same RULES.md >=20MB/s target,
    `async_stream::stream!` instead of the legacy chunker) -- this one
    verifies a real, still-load-bearing performance requirement, not
    legacy-specific behavior.
  - `daemon/tests/fault_injection.rs` deleted entirely (its one test,
    "connection drop mid-transfer then resume via a brand new
    connection," was legacy-path-only). **Not ported**, on the
    reasoning that its distinguishing feature -- resuming via a
    genuinely new client connection, as opposed to `upload_transfer.rs`
    `upload_file_resumes_after_a_dropped_stream`'s same-client
    dropped-stream resume -- tests a distinction the dedicated path's
    own architecture makes moot: each `UploadFile` call is already an
    independent RPC, never multiplexed onto a shared persistent
    stream, which is precisely the design property that made the old
    "does resume survive a connection drop" question worth asking in
    the first place. Flagging this reasoning explicitly in case it's
    judged wrong -- happy to add a genuinely-new-connection variant of
    `upload_file_resumes_after_a_dropped_stream` if so.
  - `daemon/src/transfer/mod.rs`'s own test module: kept the 4
    `sanitize_file_name_*` unit tests (shared logic, untouched);
    deleted `malicious_file_name_cannot_escape_dest_dir` (exercised the
    removed `TransferManager::begin`/`write_chunk`) but **ported its
    exact security property** to `daemon/src/transfer/upload.rs` as
    `finish_sanitizes_a_malicious_file_name_to_stay_inside_dest_dir`,
    proving `UploadWriter::finish` -- not just `sanitize_file_name` in
    isolation -- actually applies the sanitizer on the real finalize
    path. Deleted the other 7 legacy-only unit tests outright (already
    covered by `upload.rs`'s and `upload_transfer.rs`'s own tests for
    every property that has a dedicated-path equivalent: round-trip,
    resume, hash mismatch).

*Files:* `daemon/src/grpc/service.rs`, `daemon/src/transfer/mod.rs`,
`daemon/src/transfer/upload.rs`, `daemon/src/lib.rs` (call-site fix for
`TransferManager::new()`'s now-empty signature),
`proto/connectible.proto`, `daemon/tests/grpc_smoke.rs`,
`daemon/tests/upload_transfer.rs`, `daemon/tests/fault_injection.rs`
(deleted).
*Acceptance:* `cargo check --workspace --tests` and
`cargo clippy --workspace --all-targets -- -D warnings` both clean;
`cargo test --workspace` 120/120 green (was 128 before this phase --
net change reflects the deletions/ports/additions above, not a
coverage loss: every removed test's property is either provably
redundant with a surviving test, explicitly accepted as a gap in
T-I1, or replaced by a new one).

### T-I3: Migrate desktop off `send_file` onto `upload_file` exclusively `[x]`
**Done -- the production wiring turned out to already be migrated;
only the dead method + its tests remained.** `commands.rs`'s `send_file`
Tauri command (the name is user/IPC-facing, kept for continuity) was
already calling `RemoteDeviceClient::upload_file` internally -- grepping
confirmed the *method* `RemoteDeviceClient::send_file` had zero
production callers left anywhere in `desktop/`, only the two tests
below. Deleted the ~190-line `send_file` method from
`desktop/core/src/remote.rs` (and its now-unused `AtomicI64`/
`connectibled::transfer` imports). In `desktop_core_e2e.rs`:
`send_file_delivers_intact_file_and_reports_progress` deleted outright
(superseded by `upload_file_delivers_intact_file_and_reports_progress`);
`cancel_aborts_transfer_and_finalizes_nothing` ported to `upload_file`
-- **had to add an explicit pair-first step this version didn't
originally have**, because `send_file`'s cancel raced ahead of the
SyncStream pairing gate fast enough that the unpaired sender never
mattered in practice, but `upload_file`'s `PrepareUpload` step enforces
pairing synchronously *before* the cancelable feeder loop even starts,
so an unpaired cancel test would now fail on "device is not paired"
instead of testing cancellation at all.
*Files:* `desktop/core/src/remote.rs`, `desktop/core/tests/desktop_core_e2e.rs`.
*Acceptance:* `cargo test -p connectible-desktop-core --test
desktop_core_e2e` → 5/5 green, including the ported cancel test.

### T-I4: Confirm and finish mobile's migration off the legacy path `[x]`
**Done -- outbound was already fully migrated; the legacy *inbound*
receive path (never mentioned in the task description) was the real
remaining work.** Confirmed by reading, not assuming: `sendFile()`
only ever calls `client.prepareUpload`/`client.uploadFile` -- no
`FileChunk` construction anywhere in the send path. But
`handleFileChunkRequest`/`handleFileTransferStart`/`handleFileChunk`
and their private helpers (`_beginIncoming`, `_writeIncoming`,
`_verifyWholeFile`, `_finalizeIncoming`, `_failIncoming`,
`_emitIncoming`) were all still present and wired into
`PairingModel._onInboundFrame`'s dispatch switch -- dead in practice
(nothing in the ecosystem sends legacy frames anymore, confirmed by
T-I3 removing desktop's last sender), but not yet deleted. Removed all
of it, plus the now-pointless `_activeSends`/`_OutgoingSend` write-only
bookkeeping in `sendFile` (its only reader, `handleFileChunkRequest`,
is gone) and the `_IncomingTransfer` class. `PairingModel`'s
`onFileTransferStart`/`onFileChunk`/`onFileChunkRequest` constructor
callbacks and their dispatch cases removed too (folded into this task
rather than deferred to T-I6, since they're mobile's half of the same
wiring). Test coverage: `file_transfer_model_test.dart`'s legacy
"incoming receive (T-905)" and "chunk-corruption fault injection
(T-908)" groups deleted (superseded by "incoming upload receive
(Phase A)"); `pairing_model_test.dart`'s frame-dispatch test narrowed
to clipboard only (the sole frame kind still dispatched); 5 other test
files' now-meaningless empty-stub callback args removed.
*Files:* `mobile/lib/src/state/file_transfer_model.dart`,
`mobile/lib/src/state/pairing_model.dart`,
`mobile/lib/src/state/app_providers.dart`,
`mobile/test/file_transfer_model_test.dart`,
`mobile/test/pairing_model_test.dart`, and 5 screen test files.
*Acceptance:* `flutter analyze` clean; `flutter test
test/file_transfer_model_test.dart test/pairing_model_test.dart` →
20/20 green. Full-suite confirmation deferred to T-I8.

### T-I5: Reserve the retired proto fields `[x]`
**Done -- see T-I2's entry (landed together).** `SyncFrame`'s oneof
reserves numbers 3, 4, 9 and their names; the three message types are
deleted outright (no proto3 mechanism reserves message-type names, and
none was needed -- only the oneof's wire slots).
*Acceptance:* `cargo check --workspace` regenerates the Rust stubs via
`build.rs` cleanly (confirms the daemon/desktop side); mobile's Dart
stubs are regenerated as part of T-I8's full regression pass, since
`gen_proto.sh` needs the Dart protoc plugin and is more naturally
checked alongside the rest of that phase-closing verification.

### T-I6: Remove orphaned tests referencing the legacy path `[x]`
**Done -- see T-I2's entry for the daemon-side sweep (grpc_smoke.rs,
fault_injection.rs, transfer/mod.rs's own tests) and T-I4's entry for
mobile's sweep (file_transfer_model_test.dart, pairing_model_test.dart,
5 screen test files). Desktop's sweep was T-I3's entry
(desktop_core_e2e.rs).** No `#[ignore]`/skipped tests left anywhere;
every deleted test's coverage was either provably redundant with a
surviving test, explicitly accepted as a gap (T-I1's corrupted-chunk
finding), or replaced by a ported equivalent.

### T-I7: Update the archived filetransfer file's checkboxes `[x]`
**Done, and surfaced an important deviation while doing it.**
T-A20/T-A21/T-A22 marked `[x]` in `TASKS-v1.0-filetransfer.md` with a
pointer back to this phase. While updating it, re-read its own gating
condition and found this phase proceeded **without** satisfying it:
those three tasks were explicitly written to wait for **T-A25**
(real-device Linux<->Android transfer + a real Wi-Fi-pull-mid-transfer
resume test) specifically so a working fallback wouldn't be deleted
before the replacement was proven on real hardware. T-A25 was never
run (no phone in this sandbox); Phase I proceeded on automated-test
confidence alone, which is real but weaker than what the original plan
called for. Documented prominently in both files rather than quietly
proceeding -- **recommend Luna runs T-A25 for real soon**, since the
old chunk path is no longer there as a safety net if resume-after-a-
real-drop turns out to behave differently on real Wi-Fi than in the
loopback test suite. Also updated `TASKS-v1.0-pairing-ui.md`'s own
now-stale §3 (it separately referenced these same four items).
*Files:* `TASKS-v1.0-filetransfer.md`, `TASKS-v1.0-pairing-ui.md`.
*Acceptance:* both archived files' checkboxes/status text reflect
reality; the T-A25 gap is flagged, not silently skipped past.

### T-I8: Full regression pass `[x]`
**Done, all four (five, counting clippy) commands green.** Regenerating
mobile's proto stubs (`./tool/gen_proto.sh`, needed since Phase I
deleted the legacy messages proto-side in T-I5) exposed two
previously-hidden `flutter analyze` errors against stale-stub code:
- `ConnectibleServiceBase.preArmPairingCode` was abstract and
  unimplemented in `connectible_server.dart` -- masked until the stubs
  regenerated. Fixed with a `GrpcError.unimplemented` override
  (mobile's `PairingManager` has no pre-arm concept), matching the
  existing convention for other loopback-only/unsupported RPCs.
- `mobile/test/integration/daemon_integration_test.dart` still built
  raw `FileTransferStart`/`FileChunk` SyncFrames via a
  `_fileTransferFrames()` helper, feeding two legacy-path tests ("file
  send lands on daemon byte-for-byte", "resumed transfer... lands
  intact"). Deleted both tests and the helper (plus now-unused
  `dart:math` and `crc32.dart` imports) -- same reasoning as
  `daemon/tests/fault_injection.rs`'s deletion in T-I6: the first test
  didn't even exercise mobile's real `FileTransferModel`/`GrpcService`
  code (raw frames, bypassing the app layer entirely) and duplicated
  coverage already proven in `upload_transfer.rs` and
  `file_transfer_model_test.dart`'s upload tests; the second re-tested
  the same "resume via a brand-new connection" property already judged
  architecturally moot for the dedicated path (each `UploadFile` RPC is
  independent, not multiplexed onto a shared stream).

Final results, all clean:
- `flutter analyze` (mobile) -- 0 issues.
- `flutter test` (mobile) -- 133 passed, 0 failed.
- `npx tsc --noEmit -p .` (desktop) -- 0 errors.
- `npx vitest run` (desktop) -- 112 passed, 0 failed, 16/16 files.
- `cargo test --workspace` -- 95+7+5+6+1+6 = all passed, 0 failed
  across every crate/binary/integration-test target.
- `cargo clippy --workspace --all-targets -- -D warnings` -- clean.

*Files:* `mobile/lib/src/services/connectible_server.dart`,
`mobile/test/integration/daemon_integration_test.dart`.
*Acceptance:* all commands exit clean with no failing/skipped tests
introduced by this phase. Met.

**Phase I status: complete.** All of T-I1 through T-I8 done. One
accepted trade-off (T-I1's corrupted-chunk-resend gap) and one flagged
process deviation (T-I7's T-A25 real-device gate not actually run in
this sandbox -- **recommend running it soon**) are documented above,
not silently absorbed.

---

## Phase J — Persisted transfer history

**Why:** `TransferPanel.tsx`'s completed/failed transfer list is
derived entirely from live, in-memory state — a daemon restart or app
close loses every record of what was sent or received. Roadmap report
flags this under "Dosya transferi" as an open completion criterion.

**Architecture correction (found before writing any code, see below)
— this phase's original task list assumed every transfer passes
through `daemon/src/transfer/upload.rs`, which is only true for
*incoming* transfers. Rewriting T-J1..T-J7 here to match reality
before implementing, rather than silently building against the wrong
model and discovering it mid-way:**

- **Incoming** (a peer pushes a file to *this* machine): genuinely
  handled by this daemon's own `upload_file` RPC handler
  (`daemon/src/grpc/service.rs`) — the daemon can write history
  directly.
- **Outgoing** (this machine sends a file to a peer): `RemoteDeviceClient::upload_file`
  (desktop) and `GrpcService`-driven sends (mobile) connect **straight
  from the app/UI process to the remote peer's daemon**, deliberately
  bypassing this machine's own local daemon entirely (see the doc
  comment at `desktop/src-tauri/src/commands.rs`'s `send_file` and
  `useDaemon.ts`'s comment on why outgoing progress is a separate
  Tauri event, not a `SubscribeLocalEvents` frame). The local daemon
  has **no visibility** into an outgoing send today, at all.
- **Mobile has no separate daemon process** — `FileTransferModel` runs
  in the same app process for both sending and receiving, and mobile's
  only durable local storage today is `shared_preferences` (JSON blob
  per key, the pattern `DeviceListModel` already uses for the paired-
  device roster — no `sqflite`/embedded DB dependency exists). A
  daemon-DB-shaped design doesn't apply to mobile at all.

Revised design: the daemon owns one `transfer_history` table serving
**both** directions for desktop — incoming rows written directly by
`upload_file`; outgoing rows written by a **new loopback RPC**
(`RecordTransferHistory`) that desktop's `send_file` command calls
after `RemoteDeviceClient::upload_file` resolves (mirroring the
existing `record_fingerprint` loopback-call pattern in `commands.rs`).
Mobile gets its own independent `shared_preferences`-backed history,
no RPC involved, mirroring `DeviceListModel`'s existing persistence
pattern exactly.

### T-J1: `transfer_history` table + repository `[x]`
**Done.** Table + `TransferHistoryRepository` built exactly as
planned; 4 unit tests (round trip, ordering, cap-trim, limit fallback)
all green.
New SQLite table (own migration file, `0002_transfer_history.sql`,
alongside `0001_init.sql`): `id` (autoincrement PK, since the same
`transfer_id` can legitimately recur across retried attempts and isn't
itself unique over time), `transfer_id`, `peer_device_id`, `file_name`,
`total_bytes`, `direction` (`incoming`/`outgoing`), `status`
(`completed`/`failed`/`canceled`), `started_at_ms`, `finished_at_ms`.
New `daemon/src/db/history.rs` (`TransferHistoryRepository`), mirroring
`repository.rs`'s style (typed `Result`, no panics on malformed input).
*Files:* `daemon/migrations/0002_transfer_history.sql`,
`daemon/src/db/history.rs`, `daemon/src/db/mod.rs`.
*Acceptance:* migration runs cleanly on both a fresh DB and an
existing Phase-H one; a repository unit test inserts and reads back a
row.

### T-J2a: Daemon writes incoming history directly `[x]`
**Done.** New integration test
`upload_file_completion_and_hash_mismatch_are_recorded_in_history`
(`daemon/tests/upload_transfer.rs`) proves both terminal outcomes land
correctly, over a real TLS connection end to end.
`UploadTicket` gains a `device_id` field (threaded through
`UploadRegistry::accept` from `PrepareUpload`'s already-authenticated
`sender.device_id` — the ticket currently has no notion of who's
sending). `grpc/service.rs`'s `upload_file` handler writes a history
row on `UploadOutcome::Completed` (status=completed) and
`UploadOutcome::HashMismatch` (status=failed); `Incomplete` is
deliberately *not* terminal (resumable partial, matches T-J2's
original "live transfers unaffected" intent) and writes nothing.
*Files:* `daemon/src/transfer/upload.rs`, `daemon/src/grpc/service.rs`.
*Depends:* T-J1.
*Acceptance:* new test: an `upload_file` run to completion, then one
that hash-mismatches; both land correctly in `transfer_history`.

### T-J2b: Proto + loopback RPCs `[x]`
**Done.** `local_rpcs_reject_non_loopback_callers` (`grpc/service.rs`)
extended to cover both new RPCs; new integration test
`record_transfer_history_round_trips_and_rejects_non_loopback`
(`daemon/tests/upload_transfer.rs`) proves the round trip.
`TransferHistoryEntry` message plus `RecordTransferHistoryRequest/Response`
and `ListTransferHistoryRequest/Response`; two new `require_loopback`-
gated RPCs, `RecordTransferHistory` (desktop calls this after an
outgoing send resolves) and `ListTransferHistory` (paginated by a
simple `limit`, matching T-J3's cap — no cursor needed at this volume).
*Files:* `proto/connectible.proto`, `daemon/src/grpc/service.rs`.
*Depends:* T-J1.
*Acceptance:* `RecordTransferHistory` rejects a non-loopback caller
(`PERMISSION_DENIED`, matching every other local-UI RPC); a round-trip
test records one via the RPC and reads it back via `ListTransferHistory`.

### T-J3: Retention cap `[x]`
**Done, folded into T-J1's implementation.**
`seeding_past_the_cap_trims_to_the_most_recent_rows` proves 600 rows
trims to the 500-cap, keeping the most recent.
Unbounded growth here is exactly the pattern this session's audit
flagged elsewhere (`pending`/`last_created_ms` maps, upload ticket
registry) — cap the table (keep the most recent 500 rows) with a
cleanup pass run on every `TransferHistoryRepository::record` call (a
simple `DELETE ... WHERE id NOT IN (SELECT id ... ORDER BY id DESC LIMIT 500)`
tail-trim, no separate background task needed at this volume).
*Files:* `daemon/src/db/history.rs`.
*Depends:* T-J1.
*Acceptance:* a test seeding 600 rows ends up at the cap, keeping the
most recent entries.

### T-J4: Desktop reports + reads history `[x]`
**Done.** `commands.rs::send_file` captures the pump's last-forwarded
progress event (always the terminal one, since `RemoteDeviceClient::
upload_file` sends exactly one before dropping its sender) via a
shared `Arc<Mutex<Option<TransferProgressDto>>>`, then calls
`record_transfer_history` best-effort (a persistence failure logs a
warning, never turns a real send outcome into a different error).
`TransferPanel.tsx` fetches persisted history once on mount and merges
it with the live `transfers`-derived history (live wins on a
transferId collision -- richer data, and it's the just-finished case).
2 new component tests (persisted-only entry renders; live+persisted
same id doesn't duplicate); `tsc`/`vitest` both clean (114/114).
*Files:* as planned, plus `desktop/src/lib/types.ts` (new
`TransferHistoryEntry` type) and `desktop/src-tauri/src/lib.rs`
(command registration).
`desktop/core/src/local.rs` gets `record_transfer_history()` and
`list_transfer_history()`. `send_file` (`commands.rs`) captures the
terminal `TransferProgressDto` (completed/failed/canceled — already
distinguished on that DTO) from its own progress pump, and calls
`record_transfer_history` right after `remote.upload_file` resolves
(covers outgoing; incoming is already covered daemon-side by T-J2a).
New `list_transfer_history` Tauri command + `ipc.ts` binding.
`TransferPanel.tsx`'s `history` derivation changes from filtering the
live `transfers` prop to fetching via the new command on mount,
merged with whatever's still live in `transfers` (so a just-finished
transfer doesn't flicker out before the next fetch).
*Files:* `desktop/core/src/local.rs`, `desktop/src-tauri/src/commands.rs`,
`desktop/src/lib/ipc.ts`, `desktop/src/components/TransferPanel.tsx`,
`desktop/src/hooks/useDaemon.ts`.
*Depends:* T-J2a, T-J2b.
*Acceptance:* a transfer (either direction) completed before an app
restart still shows in history after restart, in a fresh
`npm run tauri dev` session.

### T-J5: Mobile persists its own history (no RPC) `[x]`
**Done.** As planned, plus: new `TransferHistoryEntry` model class
(`models.dart`); history recorded at *every* terminal point of
`sendFile` (unreadable-file fallback, PrepareUpload failure, declined
offer, completed, canceled, failed, RPC exception) and of
`handleUploadFile` (completed, hash-mismatch failed) -- an
`Incomplete`/dropped stream deliberately records nothing, matching the
daemon's own T-J2a convention (resumable, not terminal). Also fixed a
bug this feature exposed in `transfers_screen.dart`: the empty-state
guard was `rows.isEmpty` (live transfers only), which would have
masked persisted history behind "No transfers yet" after a restart --
now `active.isEmpty && history.isEmpty` (desktop's TransferPanel got
the equivalent guard in T-J4). 3 new model tests (restart via model
reconstruction against the same prefs; hash-mismatch recorded as
failed; corrupted stored blob falls back to empty without crashing) +
1 new widget test (persisted-only history renders after "restart").
`flutter analyze` clean; full `flutter test` green (137 passed, 0
failed).
*Files:* as planned, plus `mobile/lib/src/models/models.dart`,
`mobile/lib/src/state/app_providers.dart` (constructor wiring),
`mobile/test/file_transfer_model_test.dart`,
`mobile/test/screens/transfers_screen_test.dart`.
`FileTransferModel` gains a small `TransferHistoryEntry`-shaped record
type and JSON-blob persistence under a single `shared_preferences` key
(`connectible.transfer_history`), mirroring `DeviceListModel`'s
`_savePairedStore`/`_loadPairedStore` pattern exactly (load-on-
construct with a defensive try/catch, save-on-every-terminal-mutation),
capped at 200 entries (mirrors T-J3's cap, chosen smaller since a
phone's storage/UI surface is more constrained than desktop's). Saved
on both the send path (`_emitOutgoing`'s terminal event) and the
receive path (`_emitUpload`'s terminal event). `transfers_screen.dart`
renders persisted history merged with live `transfers`.
*Files:* `mobile/lib/src/state/file_transfer_model.dart`,
`mobile/lib/src/screens/transfers_screen.dart`.
*Acceptance:* a transfer completed before an app restart (simulated by
reconstructing `FileTransferModel` against the same `SharedPreferences`
instance in a test) still shows in history afterward.

### T-J6: Tests `[x]`
**Done -- all four legs landed.** Daemon repository + RPC tests are in
the T-J1/T-J2a/T-J2b/T-J3 entries above. The last missing piece, the
`desktop_core_e2e.rs` round-trip test, is
`transfer_history_round_trips_through_the_local_daemon_client`: spawns
a real daemon via the file's existing `spawn_test_daemon()` harness,
connects a real `LocalDaemonClient` (pinned cert from the daemon's own
data dir), records an outgoing/completed entry through
`record_transfer_history`, lists it back through
`list_transfer_history`, and asserts all 8 fields round-trip. Passed
on its first run. The `TransferPanel.test.tsx` merge cases are in
T-J4's entry; the mobile model + widget tests are in T-J5's.
*Acceptance:* met -- see T-J7 for the full-suite numbers.

### T-J7: Full regression pass `[x]`
**Done, all commands green:**
- `cargo test --workspace` -- connectibled lib 99, grpc_smoke 6,
  process_shutdown 1, upload_transfer 8, desktop-core lib 7,
  desktop_core_e2e 6; 0 failed anywhere.
- `cargo clippy --workspace --all-targets -- -D warnings` -- clean.
- `npx tsc --noEmit -p .` -- clean.
- `npx vitest run` -- 16 files, 114 tests, 0 failed.
- `flutter analyze` -- 0 issues; `flutter test` -- 137 passed, 0 failed.

Worth recording: the tsc leg initially caught **3 real type errors**
in the new `TransferPanel.test.tsx` mock (`vi.fn(() => ...value: [])`
inferred `never[]`, plus an `unknown[]` spread into a 0-arg mock) that
vitest could not see -- esbuild transpiles without typechecking, so
all 114 tests were green while `tsc` was red. Fixed with an explicit
return-type annotation and a no-arg forwarder. Exactly the failure
class this task runs `tsc` separately to catch.

**Phase J status: complete.** T-J1 through T-J7 all done. Transfer
history now survives restarts on all three surfaces: the daemon owns
one `transfer_history` table serving both directions for desktop
(incoming written directly by `upload_file`, outgoing reported back by
the UI via the loopback `RecordTransferHistory` RPC, since outgoing
sends bypass the local daemon entirely), and mobile self-persists via
`shared_preferences`. The architecture correction that reshaped this
phase's original task list is documented at the top of the phase.

---

## Phase K — Notification dismiss-sync

**Why:** notification mirroring is currently one-way display only —
dismissing a mirrored notification on one device does nothing to the
original on the other. Roadmap report calls this the most visible
remaining KDE-Connect-parity gap.

### T-K1: Proto message for dismiss events `[ ]`
New `NotificationDismissed { notification_id }` message plus a
SyncStream frame case (or fold into the existing notification
local-event oneof if that's a cleaner fit — decide during the task,
matching the existing `Notification`/`local_event` message shapes).
*Files:* `proto/connectible.proto`.
*Acceptance:* `make proto` regenerates cleanly on all three targets.

### T-K2: Daemon relays dismiss frames between paired peers `[ ]`
Same relay pattern the daemon already uses for mirroring the
notification itself — forward a received dismiss frame to the other
paired connection, gated by the same pairing check as every other
SyncStream frame (Phase G's fingerprint gate applies here too, once
that phase has landed; until then, the existing `is_paired` gate).
*Files:* `daemon/src/grpc/service.rs`.
*Depends:* T-K1.
*Acceptance:* integration test: peer A sends a dismiss frame, peer B's
local-event stream receives it.

### T-K3: Mobile detects a real dismissal and emits the frame `[ ]`
`ConnectibleNotificationListener.kt`'s `onNotificationRemoved` callback
(Android's own dismissal hook) triggers sending a dismiss frame for
that notification's id, if it originated from a synced source.
*Files:* `mobile/android/app/src/main/kotlin/io/connectible/mobile/notifications/ConnectibleNotificationListener.kt`,
`mobile/lib/src/state/notification_model.dart`.
*Depends:* T-K1.
*Acceptance:* dismissing a real Android notification (that was itself
mirrored from desktop) sends the frame — verify via a daemon-side log/
test double, not just code inspection.

### T-K4: Investigate mobile's ability to dismiss on receipt `[ ]`
Unlike sending a dismissal, *receiving* one and canceling a live
Android notification requires `NotificationListenerService.
cancelNotification`, which only works for notifications the listener
has visibility into (documented Android behavior, not guaranteed for
every OEM/notification source). Spike this first: confirm it works for
Connectible's own use case before building the full path. If it
doesn't work reliably, document the one-directional limitation (mobile
dismiss to desktop: yes; desktop dismiss to mobile: not reliably
possible) instead of shipping a flaky feature.
*Files:* investigation only; write the finding into
`mobile/android/app/src/main/kotlin/io/connectible/mobile/notifications/ConnectibleNotificationListener.kt`'s
own doc comment either way.
*Depends:* T-K1.
*Acceptance:* a written finding (works / doesn't work / works with
caveats), with the remaining tasks in this phase adjusted accordingly
before implementation continues.

### T-K5: Desktop dismiss action sends the frame `[ ]`
`NotificationsPanel.tsx` gets a dismiss/close affordance per
notification card that sends the T-K1 frame to the paired peer.
*Files:* `desktop/src/components/NotificationsPanel.tsx`,
`desktop/core/src/remote.rs` or wherever outbound frames are sent from.
*Depends:* T-K1.
*Acceptance:* clicking dismiss sends the frame (integration-tested via
`desktop_core_e2e.rs`, not just unit-tested in isolation).

### T-K6: Desktop applies an incoming dismiss `[ ]`
Receiving a dismiss frame from the peer removes/marks that entry in
`NotificationsPanel`'s state.
*Files:* `desktop/src/components/NotificationsPanel.tsx`,
`desktop/src/hooks/useDaemon.ts`.
*Depends:* T-K2.
*Acceptance:* widget test: emitting a dismiss local-event removes the
matching notification from the rendered list.

### T-K7: Echo suppression `[ ]`
Mirror the clipboard model's echo-guard pattern
(`ClipboardEchoGuard`/`daemon`'s clipboard echo suppression) so a
device that dismissed its own notification doesn't receive and
re-process an echo of that same dismissal bouncing back.
*Files:* wherever T-K2/T-K3/T-K6 land.
*Depends:* T-K2, T-K3, T-K6.
*Acceptance:* test proves a self-originated dismissal doesn't loop.

### T-K8: i18n strings `[ ]`
New keys for the dismiss affordance and any related copy, both
languages, both platforms.
*Files:* `desktop/src/i18n/locales/{en,tr}.json`,
`mobile/lib/src/i18n/strings.dart`.
*Depends:* T-K5, T-K6.
*Acceptance:* no hardcoded English string introduced in either UI.

### T-K9: Tests `[ ]`
Full-stack coverage beyond the per-task acceptance above: a daemon
integration test proving the whole round trip (mobile-side dismissal
simulated via the RPC, desktop-side receipt verified).
*Depends:* T-K2 through T-K8.
*Acceptance:* new test passes; full suites stay green.

---

## Phase L — Clipboard rich content (images)

**Why:** clipboard sync is text-only today. Roadmap report lists this
as the one open "Pano senkronu" criterion. Scoped to images for this
phase — arbitrary file-clipboard sync is a materially bigger feature
(effectively file transfer with different UX) and isn't included here.

### T-L1: Scope decision, written down before coding `[ ]`
Confirm images-only for v1 of this feature (matches the common
KDE-Connect-parity case: copy a screenshot on one device, paste on the
other) and a hard size cap (recommend starting at 10MB, revisit if it
proves wrong in testing) so clipboard sync can't be used as a
backdoor bulk file-transfer channel. Write the decision into this
phase's own commit/PR description — no separate doc needed for a
decision this small.
*Acceptance:* the cap and scope are referenced consistently by every
task below (T-L2's proto field, T-L7's enforcement).

### T-L2: Proto extension for MIME-typed clipboard payloads `[ ]`
Extend `ClipboardData` (or add a new message, whichever is the smaller
diff against the existing oneof/frame structure) with `mime_type` and
binary `payload` fields alongside the existing text field.
*Files:* `proto/connectible.proto`.
*Depends:* T-L1.
*Acceptance:* `make proto` regenerates cleanly on all three targets;
existing text-only clipboard tests still pass unmodified (new fields
default empty).

### T-L3: Daemon captures image clipboard content (Wayland) `[ ]`
`wlr-data-control-unstable-v1` already supports arbitrary MIME offers
per its own protocol spec — extend the daemon's Wayland clipboard
backend beyond `text/plain` to also capture `image/png` (and
`image/jpeg` if trivial) offers, subject to T-L1's size cap.
*Files:* daemon's Wayland clipboard backend module.
*Depends:* T-L2.
*Acceptance:* copying a screenshot on a Wayland session and inspecting
the daemon's captured clipboard state (via a test hook or log) shows
the image MIME type and byte size.

### T-L4: Daemon captures image clipboard content (X11) `[ ]`
Same for the `x11-clipboard`-backed path — check the crate's support
for non-text MIME targets; if it's insufficient, document the gap
rather than silently shipping X11 as text-only-forever.
*Files:* daemon's X11 clipboard backend module.
*Depends:* T-L2.
*Acceptance:* equivalent to T-L3's acceptance, on an X11 session (or a
documented, explicit limitation if the crate can't support it).

### T-L5: Daemon applies a received image to the local clipboard `[ ]`
Reverse direction of T-L3/T-L4: an inbound `ClipboardData` frame with a
non-empty `mime_type` writes the image to the OS clipboard instead of
the text path.
*Files:* same backend modules as T-L3/T-L4.
*Depends:* T-L3, T-L4.
*Acceptance:* round-trip test (where the platform allows automated
clipboard assertions): send an image frame, read back the OS
clipboard, confirm the bytes match.

### T-L6: Desktop clipboard panel renders images `[ ]`
`ClipboardPanel.tsx`'s history entries render an image thumbnail
(with a reasonable max display size) instead of / alongside the text
preview when `mimeType` starts with `image/`; a "copy image" action per
entry.
*Files:* `desktop/src/components/ClipboardPanel.tsx`.
*Depends:* T-L2.
*Acceptance:* widget test with a sample `image/png` entry renders an
`<img>` (or canvas) element, not raw base64 text.

### T-L7: Mobile clipboard image support `[ ]`
Flutter's built-in `Clipboard` API (`flutter/services.dart`) is
text-only — reading/writing image clipboard content needs a platform-
channel-capable package (e.g. `super_clipboard`) or custom platform
code. Flag this as the highest-uncertainty task in the phase; spike it
first and confirm feasibility before committing to the full mobile
side of this feature.
*Files:* `mobile/lib/src/state/clipboard_model.dart`,
`mobile/pubspec.yaml` (new dependency if one is chosen).
*Depends:* T-L2.
*Acceptance:* a spike confirming a working approach, then the same
round-trip proof as T-L6 but on mobile.

### T-L8: Size-cap enforcement and user-facing error `[ ]`
A copied image exceeding T-L1's cap is not sent; the user sees a clear
message explaining why (not a silent no-op).
*Files:* wherever T-L3/T-L4/T-L7 capture the content.
*Depends:* T-L1, T-L3, T-L4, T-L7.
*Acceptance:* test: an oversized image triggers the exact user-facing
message, and confirmed nothing partial gets sent.

### T-L9: Tests `[ ]`
Beyond each task's own acceptance: a daemon-level MIME round-trip
test, desktop panel rendering test, mobile test scoped by whatever
T-L7's spike found feasible.
*Depends:* T-L3 through T-L8.
*Acceptance:* all new tests pass; full suites stay green.

---

## Phase M — End-user documentation

**Why:** `docs/developer-guide.md` and `docs/api-reference.md` exist
and are thorough; nothing exists for the person who just wants to pair
their phone and send a file without reading source code. Roadmap
report's only open "Dokümantasyon" criterion.

### T-M1: `docs/user-guide.md` skeleton `[ ]`
Match `docs/developer-guide.md`'s structure and tone (plain, direct,
no marketing language) rather than inventing a new format.
*Files:* new `docs/user-guide.md`.
*Acceptance:* skeleton with section headers for T-M2 through T-M6
below, committed even before every section has full content, so the
structure itself can be reviewed early.

### T-M2: First-pairing walkthrough `[ ]`
Both roles (desktop-initiates via QR or manual address; phone-
initiates the same) and both mechanisms (QR scan, manual "connect by
address"). No screenshots required — see T-M8 for that decision.
*Files:* `docs/user-guide.md`.
*Depends:* T-M1.
*Acceptance:* a person who has never used the app could follow this
section alone and successfully pair, verified by having someone
unfamiliar with the app actually try it against the written steps.

### T-M3: Clipboard sync section `[ ]`
Usage plus current limitations — update this section once Phase L
ships to stop saying "text only."
*Files:* `docs/user-guide.md`.
*Depends:* T-M1.
*Acceptance:* accurately reflects whatever clipboard capability is
shipped at time of writing (text-only now, image-capable after Phase
L — don't let this drift out of sync).

### T-M4: File send/receive walkthrough `[ ]`
Including what resume actually means for the user (reconnect and the
transfer picks up, doesn't restart) and where received files land
(configurable download dir).
*Files:* `docs/user-guide.md`.
*Depends:* T-M1.

### T-M5: Remote input walkthrough `[ ]`
Touchpad gestures, keyboard usage, the X11-vs-Wayland backend
distinction in user terms (not implementation terms) — what to expect
if the daemon logs "no remote-input backend available."
*Files:* `docs/user-guide.md`.
*Depends:* T-M1.

### T-M6: Troubleshooting section sourced from System Doctor `[ ]`
Reuse the diagnostics engine's own check titles/remediation strings
(don't duplicate/diverge from them) as the basis for a troubleshooting
table, with a pointer to running `connectibled doctor` or the in-app
Doctor panel for anything not covered here.
*Files:* `docs/user-guide.md`.
*Depends:* T-M1.
*Acceptance:* every remediation string quoted here matches what the
System Doctor registry actually says today — a stale copy-paste is
worse than a pointer to the live source.

### T-M7: Link from README and the GitHub Pages landing page `[ ]`
*Files:* `README.md`, `docs/index.html`.
*Depends:* T-M2 through T-M6 (link once there's real content).
*Acceptance:* the link resolves and lands on the right section from
both entry points.

### T-M8: Screenshot policy decision — **ASK FIRST** `[ ]`
The project's existing convention (documented in the archived
`TASKS-v1.0-pairing-ui.md`) is that no image files are kept in-repo for
design reference. A user guide benefits from real screenshots. This is
a repo-content-policy call, not an engineering one — ask Luna whether
screenshots are wanted at all, and if so, where they'd live
(`docs/assets/`, an external host, etc.) before adding any binary
image file to the repo.
*Depends:* none (can happen anytime; blocks nothing else in this
phase since T-M2-T-M6 are written to stand without screenshots).
*Acceptance:* a decision recorded, then followed — don't add images
preemptively.

---

## Phase N — T-B3, real-device battery verification (deferred)

**Why kept separate:** the only open Phase-relevant item that requires
real Android hardware. Luna asked to set device/adb work aside for now
— **do not start this phase without her explicitly asking for it.**
Re-tracked here (superseding `TASKS-v1.0-filetransfer.md`'s own T-B3)
purely so it isn't lost, not as a signal to pick it up.

### T-N1: Real-device battery impact measurement `[ ]`
Run the mobile app with an active paired session over several hours on
a real Android phone; compare battery drain against a baseline
(app not running, or running without an active sync session). Record
the result in this file once done.
*Files:* n/a (measurement task; results recorded here).
*Depends:* Luna's go-ahead.
*Acceptance:* a written measurement (not a pass/fail guess) showing
the drain is within a reasonable margin of the baseline, or a concrete
follow-up task opened if it isn't.

---

## Phase order and dependencies

Phases G and H (security foundations) have no dependency on each other
and can run in either order or in parallel. Phase I (legacy-path
removal) is independent of both but touches the most files across all
three stacks at once — doing it in isolation (not interleaved with G/H)
keeps the regression surface easy to reason about. Phases J, K, and L
are each fully independent features and can be sequenced by Luna's
priority preference. Phase M (docs) is best done last per section, once
the feature it documents is stable, though its skeleton (T-M1) can be
written anytime. Phase N stays parked until explicitly requested.
