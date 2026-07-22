# Connectible - Architecture Diagrams

ASCII diagrams for component topology, message flow, and the pairing
sequence. See [PLAN.md](archive/PLAN.md) for narrative context and
[proto/connectible.proto](../proto/connectible.proto) for the messages
referenced below.

---

## 1. Component topology

```
  +-----------------------------+                 +-----------------------------+
  |      DESKTOP MACHINE        |                 |       MOBILE DEVICE          |
  |                             |                 |                             |
  |  +-----------------------+  |                 |  +-----------------------+  |
  |  |   Tauri v2 Desktop UI |  |                 |  |    Flutter Mobile App |  |
  |  |  React + TS + Tailwind|  |                 |  |   Dart + Provider     |  |
  |  |  + shadcn/ui (dark)   |  |                 |  |                       |  |
  |  +-----------+-----------+  |                 |  +-----------+-----------+  |
  |              | gRPC-Web      |                 |              | gRPC (Dart) |
  |              | (loopback,    |                 |              | client       |
  |              |  TLS 1.3)     |                 |              |              |
  |              v               |                 |              |             |
  |  +-----------------------+  |                 |              |             |
  |  |   connectibled (Rust) |  |                 |              |             |
  |  |-----------------------|  |                 |              |             |
  |  | tokio runtime          |  |                 |              |             |
  |  | tonic gRPC server      |  |                 |              |             |
  |  |  (HTTP/2 + rustls TLS  |<-+-----------------+--------------+             |
  |  |   1.3)                 |  |   TCP + TLS 1.3 gRPC            |             |
  |  | mdns-sd (discovery)    |<-+-----------------+--------------+             |
  |  |  <-- UDP multicast --> |  |   mDNS (_connectible._tcp)      |             |
  |  | sqlx + SQLite          |  |                 |                             |
  |  |  (devices.db)          |  |                 |  (no local daemon on        |
  |  | x11-clipboard /        |  |                 |   mobile; app speaks        |
  |  |  wayland-client        |  |                 |   the protocol directly)    |
  |  | ydotool / wayland-     |  |                 |                             |
  |  |  client (input inject) |  |                 |                             |
  |  +-----------------------+  |                 |                             |
  +-----------------------------+                 +-----------------------------+

  Both peers advertise + browse the same mDNS service type; either side
  can initiate the TCP+TLS connection once a peer is discovered.
```

---

## 2. Message flow (SyncStream)

All high-frequency, real-time traffic multiplexes over a single
bidirectional `SyncStream` RPC per active connection, using the
`SyncFrame` oneof envelope defined in `connectible.proto`.

```
   Device A                                            Device B
   (daemon)                                             (daemon)
      |                                                     |
      |============ SyncStream(stream SyncFrame) =========>|
      |<=========== SyncStream(stream SyncFrame) ==========|
      |                                                     |
      |  frame: Identity            (handshake refresh)     |
      |---------------------------------------------------->|
      |                                                     |
      |  frame: ClipboardData       (local copy detected)   |
      |---------------------------------------------------->|
      |                                     [applies to     |
      |                                      local clipboard,|
      |                                      records hash to |
      |                                      suppress echo] |
      |                                                     |
      |  frame: FileTransferStart   (announce incoming file)|
      |---------------------------------------------------->|
      |  frame: FileChunk (offset=0)                        |
      |---------------------------------------------------->|
      |  frame: FileChunk (offset=65536)                    |
      |---------------------------------------------------->|
      |                  ...                                |
      |  frame: FileChunk (is_last=true)                    |
      |---------------------------------------------------->|
      |                                     [verifies CRC32  |
      |                                      per chunk, then |
      |                                      SHA-256 whole   |
      |                                      file; renames   |
      |                                      into place]     |
      |                                                     |
      |<---------------------------------------------------- |
      |  frame: RemoteInputEvent    (mouse move, from B->A)  |
      |                                     [B is phone,     |
      |                                      A is desktop;   |
      |                                      A injects via   |
      |                                      ydotool/wayland]|
      |                                                     |
      |<----------------------------------------------------|
      |  frame: BatteryStatus       (phone -> desktop)       |
      |<----------------------------------------------------|
      |  frame: NotificationData    (phone -> desktop)       |
      |                                                     |
      |  frame: Error                (either direction,      |
      |                                async failure, e.g.   |
      |                                ERROR_CODE_CHECKSUM_  |
      |                                MISMATCH)              |
      |<===================================================>|
      |                                                     |

  Legend:
   ---> / <---   : single SyncFrame message
   ===> / <===   : the underlying persistent HTTP/2 stream
   [bracketed]   : receiver-side processing, not wire traffic
```

Unary RPCs (`Pair`, `ConfirmPin`, `ListDevices`, `Ping`) are separate
calls outside the `SyncStream`, used for control-plane operations that
have a clear single request/response shape rather than continuous
push traffic.

---

## 3. Pairing sequence

Full flow from PLAN.md section 1, matching `PairRequest` /
`PairResponse` / `ConfirmPinRequest` / `ConfirmPinResponse` in
`connectible.proto`.

```
  Device A (requester)              Network                Device B (responder)
  ---------------------              -------                ---------------------
        |                                                            |
        |  (B is running, advertising _connectible._tcp via mDNS)    |
        |<-------------------- mDNS advertisement --------------------|
        |                                                            |
        |  A browses mDNS, resolves B's IP:port                      |
        |                                                            |
        |------------- TCP connect + TLS 1.3 handshake -------------->|
        |                 (B's self-signed cert accepted,             |
        |                  no pinning in MVP)                         |
        |<-------------------- TLS established -----------------------|
        |                                                            |
        |------------------- Identity (A's info) --------------------->|
        |<------------------ Identity (B's info) -----------------------|
        |                                                            |
        |-------------------- Pair(PairRequest) ----------------------->|
        |                                            [B generates a   |
        |                                             cryptographically|
        |                                             random 6-digit  |
        |                                             PIN, stores it  |
        |                                             in-memory keyed |
        |                                             by A's device_id|
        |                                             with 30s expiry,|
        |                                             fires a local   |
        |                                             "pairing        |
        |                                             requested" event|
        |                                             for B's UI]     |
        |<----------- PairResponse(accepted, pin_expires_at_ms) --------|
        |                                                            |
        |   [A's UI prompts: "Enter the PIN shown on Device B"]       |
        |                                       [B's UI shows the PIN |
        |                                        dialog with a 30s    |
        |                                        countdown]           |
        |                                                            |
        |  (out-of-band: user reads PIN on B's screen, types into A)  |
        |                                                            |
        |------------- ConfirmPin(device_id=A, pin_code) -------------->|
        |                                            [B compares PIN  |
        |                                             in constant     |
        |                                             time; checks    |
        |                                             not expired;    |
        |                                             on 3rd wrong    |
        |                                             attempt,        |
        |                                             invalidates PIN |
        |                                             early]          |
        |<----------------- ConfirmPinResponse(verified) ---------------|
        |                                                            |
        |                    [if verified: both A and B persist       |
        |                     the peer to their local SQLite          |
        |                     `devices` table with paired_at_ms =     |
        |                     now]                                    |
        |                                                            |
        |==================== SyncStream opens ========================|
        |     (subsequent connections: TLS handshake only, no PIN     |
        |      required again -- v1.0 adds cert-pinning verification  |
        |      at this step; MVP trusts the TLS session as-is)        |
        |                                                            |

  Failure branches (see PLAN.md section 7 "Edge cases"):
   - ConfirmPin arrives after pin_expires_at_ms
       -> verified=false, ERROR_CODE_PAIRING_TIMEOUT
       -> A's UI must restart from Pair, not retry ConfirmPin.
   - A's device_id already present in B's devices table
       -> Pair short-circuits: accepted=true, no PIN dialog shown,
          last_seen updated (T-015).
   - 3 consecutive wrong PIN attempts
       -> PIN invalidated early, same as expiry case above.
```

---

## 4. Data storage layout (daemon)

```
  ~/.local/share/connectible/            (Linux XDG data dir)
  |-- connectibled.db                    SQLite: devices table
  |     devices(
  |       device_id      TEXT PRIMARY KEY,
  |       device_name    TEXT NOT NULL,
  |       platform       TEXT NOT NULL,
  |       device_type    TEXT NOT NULL,
  |       paired_at_ms   INTEGER NOT NULL,
  |       last_seen_ms   INTEGER NOT NULL
  |       -- cert fingerprint columns reserved, unused until v1.0
  |     )
  |
  |-- tls/
  |     |-- cert.pem                     0600, self-signed, generated
  |     |                                once on first run (T-008)
  |     +-- key.pem                      0600, never logged
  |
  +-- transfers/                          temp dir for in-progress
        |-- <transfer_id>.part            resumable file chunks land
        +-- <transfer_id>.offset           highest contiguous offset
                                            written, used for resume
                                            (T-025)
```

---

## 5. Runtime backend selection (remote input + clipboard)

Implemented in `daemon/src/clipboard/backend.rs` and
`daemon/src/input/backend.rs`'s `detect_backend()` (T-301/T-302/T-303,
T-802). Both follow the same fallback shape: try native Wayland first
on a Wayland session (it is the only path that sees native-Wayland
clients, not just XWayland ones), fall back to the X11/XWayland path
on failure, and disable the capability (never crash) if neither works.

```
                     daemon startup
                          |
                          v
             read $XDG_SESSION_TYPE / $WAYLAND_DISPLAY
                          |
              +-----------+-----------+
              |                       |
        "wayland session"       not wayland
              |                       |
              v                       |
   try wayland-client backend         |
   (wlr-data-control-v1 /             |
    wlr-virtual-pointer-v1 +          |
    virtual-keyboard-v1)              |
              |                       |
        succeeded? --- yes --> use it (native Wayland; sees
              |                 native-Wayland clients' clipboard/
              no                input, not just XWayland's)
              |                       |
              +-----------+-----------+
                          |
                          v
              try X11/XWayland backend
       (x11-clipboard; ydotool, which itself only needs
        /dev/uinput -- the X11 root-window query it does
        is *only* to size absolute pointer coordinates, and
        falls back to $CONNECTIBLE_SCREEN_WIDTH/HEIGHT or a
        1920x1080 default rather than disabling the whole
        backend when no X11 connection is reachable, T-802)
                          |
                succeeded? --- yes --> use it (works, but native
                          |             Wayland clients' clipboard/
                          no            input are invisible to it)
                          |
                          v
              tracing::warn! documenting what was tried and
              why it failed; capability left off entirely
                          |
                          v
          capability probe result feeds Identity.capabilities,
          advertised to peers so UIs can gray out unsupported
          features instead of failing silently at use-time.
```
