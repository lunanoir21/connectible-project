# Per-chunk re-request design (T-202)

Problem (from FINDINGS.md): `FileChunk.chunk_checksum`'s doc comment in
`proto/connectible.proto` already claims a corrupted chunk lets "the
receiver detect a corrupted chunk immediately and request a re-send of
just that chunk instead of failing the whole transfer" -- but no such
request message exists. Today a bad CRC32 only produces an
`Error(ERROR_CODE_CHECKSUM_MISMATCH)` frame; nothing re-requests the
specific chunk, so the sender doesn't know to resend it and the
transfer either stalls or must fall back to the coarser whole-transfer
resume path (T-025's `resume_offset_bytes`).

## Proto change

Add a new message and a new `SyncFrame` oneof case (additive, matches
the project's "new messages + new RPCs only" post-freeze versioning
policy already used for `SubscribeLocalEvents`/`GetLocalState`):

```protobuf
// ---------------------------------------------------------------------
// Message 9: FileChunkRequest
// ---------------------------------------------------------------------

// Sent by the receiver back to the sender when a FileChunk fails its
// CRC32 check, asking for that one chunk to be resent rather than
// aborting or falling back to a full resume-from-offset. The sender
// treats this exactly like a fresh FileChunk send at offset_bytes.
message FileChunkRequest {
  string transfer_id = 1;
  int64 offset_bytes = 2;
}
```

```protobuf
message SyncFrame {
  oneof payload {
    ClipboardData clipboard = 1;
    RemoteInputEvent input_event = 2;
    FileTransferStart file_transfer_start = 3;
    FileChunk file_chunk = 4;
    BatteryStatus battery_status = 5;
    NotificationData notification = 6;
    Error error = 7;
    Identity identity = 8;
    FileChunkRequest file_chunk_request = 9; // new, additive
  }
}
```

## Daemon-side behavior (implementation target: T-306)

- Receiver (`daemon/src/transfer/mod.rs`'s chunk-write path, currently
  producing `ChunkOutcome::Corrupted`): on `Corrupted`, instead of only
  emitting `Error(ChecksumMismatch)`, also emit a `FileChunkRequest`
  frame for that `transfer_id`/`offset_bytes` on the same stream
  (`daemon/src/grpc/service.rs` dispatch, near the existing handling
  around the old line 208-215).
- Sender (wherever `TransferManager`'s send loop lives / the send-side
  equivalent in `desktop/core/src/remote.rs` and mobile's
  `app_model.dart` send path): on receiving `FileChunkRequest`, look up
  the already-open file handle for `transfer_id`, seek to
  `offset_bytes`, and resend that one chunk -- exactly the same code
  path used for a normal chunk send, just re-triggered.
- The whole-transfer `resume_offset_bytes` path (T-025) is unaffected
  and remains the fallback for a full reconnect after a dropped
  connection; `FileChunkRequest` only handles the narrower
  single-corrupted-chunk-on-an-otherwise-healthy-connection case.
- Bound the number of re-requests per chunk (e.g. 3 attempts) before
  falling back to aborting the transfer with `Error(ChecksumMismatch)`,
  to avoid an infinite request/corrupt loop against a systematically
  broken link.

## Test shape (feeds T-306's acceptance criteria + T-901's
fault-injection harness)

A fault-injection test corrupts exactly one chunk in transit, asserts
a `FileChunkRequest` is emitted, the sender resends just that chunk,
and the transfer completes successfully with a correct whole-file hash
-- distinct from T-901's connection-drop scenario, which exercises the
coarser resume-from-offset path instead.
