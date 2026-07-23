import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:super_clipboard/super_clipboard.dart' as sc;

import '../models/models.dart';
import 'sync_connection.dart';
import '../generated/connectible.pbgrpc.dart' as pb;

const int _historyCap = 20;

/// T-L1/T-L8: hard cap on synced clipboard content, mirroring the
/// daemon's `MAX_CLIPBOARD_BYTES` (`daemon/src/clipboard/mod.rs`) --
/// clipboard sync must not double as a bulk file-transfer channel. Only
/// reachable via images on mobile; text never approaches this.
const int _maxClipboardBytes = 10 * 1024 * 1024;

/// Reads clipboard data for [format] as a single `Future`, since
/// [sc.DataReader.getFile] only exposes a callback-based progress API
/// (mirrors the equivalent helper in the super_clipboard example app).
Future<Uint8List?> _readClipboardFile(
    sc.DataReader reader, sc.FileFormat format) {
  final completer = Completer<Uint8List?>();
  final progress = reader.getFile(format, (file) async {
    try {
      completer.complete(await file.readAll());
    } catch (e) {
      completer.completeError(e);
    }
  }, onError: completer.completeError);
  if (progress == null) {
    completer.complete(null);
  }
  return completer.future;
}

/// How often the OS clipboard is polled for changes while the app is in
/// the foreground (T-304). Mirrors the daemon's clipboard poll cadence
/// closely enough to stay within RULES.md's "under 2 seconds end-to-end"
/// propagation target.
const Duration _defaultPollInterval = Duration(seconds: 2);

/// Pure change-detection/echo-suppression engine mirroring the daemon's
/// `ClipboardSync` (see `daemon/src/clipboard/mod.rs`): tracks the hash of
/// the last content observed locally and the hash of the last content this
/// device itself applied *from* a peer, so that reading the OS clipboard
/// back right after an inbound apply is never mistaken for a brand new
/// local change and re-broadcast to its own sender (an echo loop).
///
/// Kept separate from [ClipboardModel] (and free of any Flutter plugin
/// calls) so the suppression logic itself is unit-testable without a
/// platform-channel mock.
@visibleForTesting
class ClipboardEchoGuard {
  String? _lastLocalHash;
  String? _lastAppliedHash;

  @visibleForTesting
  String? get lastLocalHash => _lastLocalHash;
  @visibleForTesting
  String? get lastAppliedHash => _lastAppliedHash;

  /// Call with clipboard content observed locally (polled from the OS
  /// clipboard, or sent explicitly via the manual "Send" button). Returns
  /// `true` if this is a genuinely new local change that should be pushed
  /// to the peer; `false` if it is unchanged content or an echo of what
  /// this device most recently applied from a peer. Either way, the
  /// observation is recorded so repeated polls of the same content stay
  /// silent.
  bool observeLocalChange(String text) => _observeHash(hashContent(text));

  /// Same suppression logic as [observeLocalChange], but for arbitrary
  /// binary content (Phase L: image clipboard entries) instead of text.
  bool observeLocalBytes(List<int> bytes) => _observeHash(hashBytes(bytes));

  bool _observeHash(String hash) {
    if (_lastLocalHash == hash) return false;
    if (_lastAppliedHash == hash) {
      // Our own previously-applied peer update being read back from the
      // OS clipboard, not a new local change.
      _lastLocalHash = hash;
      return false;
    }
    _lastLocalHash = hash;
    return true;
  }

  /// Records that content with [contentHash] (from an inbound
  /// `ClipboardData` frame) was just applied to the OS clipboard.
  void recordApplied(String contentHash) {
    _lastAppliedHash = contentHash;
    _lastLocalHash = contentHash;
  }

  static String hashBytes(List<int> bytes) =>
      sha256.convert(bytes).toString();

  static String hashContent(String text) => hashBytes(utf8.encode(text));
}

/// Owns clipboard send/receive (T-204). Depends only on the narrow
/// [SyncConnection] interface to push frames onto the active session and
/// to gate sending on connectivity -- it never depends on [PairingModel]
/// concretely.
///
/// Background sync (T-304): polls the OS clipboard every
/// [_defaultPollInterval] while the app is foregrounded and auto-sends any
/// genuinely new content, and auto-applies inbound clipboard frames to the
/// OS clipboard. [ClipboardEchoGuard] prevents the resulting read-back from
/// looping back out to the peer that just sent it.
class ClipboardModel extends ChangeNotifier with WidgetsBindingObserver {
  ClipboardModel({
    required SyncConnection connection,
    Duration pollInterval = _defaultPollInterval,
    bool autoMonitor = true,
    bool autoApply = true,
  })  : _connection = connection,
        _pollInterval = pollInterval,
        _autoMonitor = autoMonitor,
        _autoApply = autoApply {
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  final SyncConnection _connection;
  final Duration _pollInterval;
  final ClipboardEchoGuard _echoGuard = ClipboardEchoGuard();
  Timer? _pollTimer;

  /// Auto-send local clipboard changes (T-B11 toggle). When off, the poll
  /// still runs but never pushes; the manual "Send" button is unaffected.
  bool _autoMonitor;

  /// Auto-apply inbound clipboard frames to the OS clipboard (T-B11
  /// toggle). When off, inbound content still lands in history but is not
  /// written to the OS clipboard.
  bool _autoApply;

  bool get autoMonitor => _autoMonitor;
  bool get autoApply => _autoApply;

  /// Live toggles, called by the Settings screen alongside the persisted
  /// `SettingsModel` flags so a change takes effect without a restart.
  void setAutoMonitor(bool value) {
    if (value == _autoMonitor) return;
    _autoMonitor = value;
    notifyListeners();
  }

  void setAutoApply(bool value) {
    if (value == _autoApply) return;
    _autoApply = value;
    notifyListeners();
  }

  List<ClipboardEntry> clipboard = const [];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollLocalChange());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollLocalChange() async {
    if (!_autoMonitor || !_connection.connected) return;
    // Image and text are mutually exclusive clipboard states, so a
    // handled image poll skips the text path for this tick.
    if (await _pollLocalImage()) return;
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (e) {
      debugPrint('clipboard poll failed: $e');
      return;
    }
    if (text == null || text.isEmpty) return;
    if (!_echoGuard.observeLocalChange(text)) return;
    await _pushLocal(text);
  }

  /// Polls for image clipboard content (Phase L, T-L7) via
  /// `super_clipboard`, since `flutter/services.dart`'s `Clipboard` API
  /// is text-only. Only `image/png` is checked, matching the daemon's
  /// own capture support (see `daemon/src/clipboard/backend.rs`'s
  /// `READ_TARGETS` / `wayland_backend.rs`'s `SUPPORTED_MIME_TYPES`).
  /// Returns true if image content was observed this tick (new,
  /// oversized, or an echo of a just-applied peer update) so the caller
  /// does not also poll the text clipboard.
  Future<bool> _pollLocalImage() async {
    final clipboard = sc.SystemClipboard.instance;
    if (clipboard == null) return false;
    try {
      final reader = await clipboard.read();
      if (!reader.canProvide(sc.Formats.png)) return false;
      final bytes = await _readClipboardFile(reader, sc.Formats.png);
      if (bytes == null || bytes.isEmpty) return false;
      if (!_echoGuard.observeLocalBytes(bytes)) return true;
      await _pushLocalImage(bytes, 'image/png');
      return true;
    } catch (e) {
      debugPrint('clipboard image poll failed: $e');
      return false;
    }
  }

  /// Called by [PairingModel] when an inbound `SyncFrame` carries
  /// clipboard data. Auto-applies it to the OS clipboard (T-304) and
  /// records its hash so the next poll does not echo it back.
  void handleInbound(pb.ClipboardData data) {
    final mimeType = data.mimeType.isEmpty ? 'text/plain' : data.mimeType;
    if (mimeType.startsWith('image/')) {
      _handleInboundImage(data, mimeType);
      return;
    }
    final text = utf8.decode(data.content, allowMalformed: true);
    if (_autoApply) {
      // Only record the applied hash when we actually write to the OS
      // clipboard -- otherwise there is nothing to echo-suppress, and a
      // stale applied-hash could wrongly swallow a later genuine local copy
      // of the same text.
      _echoGuard.recordApplied(data.contentHash);
      unawaited(Clipboard.setData(ClipboardData(text: text)).catchError((e) {
        debugPrint('clipboard auto-apply failed: $e');
      }));
    }
    _addClipboard(ClipboardEntry(
      content: text,
      capturedAtMs: data.capturedAtMs.toInt(),
      source: 'remote',
    ));
  }

  /// Image counterpart of [handleInbound]'s text path (Phase L, T-L5
  /// mirror on mobile). Defense in depth (T-L8): a well-behaved peer
  /// never sends oversized content -- the sending side enforces the
  /// cap in [_pushLocalImage] -- but this app must not trust that
  /// unconditionally.
  void _handleInboundImage(pb.ClipboardData data, String mimeType) {
    if (data.content.length > _maxClipboardBytes) {
      debugPrint(
          'rejecting inbound clipboard image (${data.content.length} bytes): exceeds the size cap');
      return;
    }
    final bytes = Uint8List.fromList(data.content);
    if (_autoApply) {
      _echoGuard.recordApplied(data.contentHash);
      unawaited(_writeImageToClipboard(bytes, mimeType).catchError((e) {
        debugPrint('clipboard image auto-apply failed: $e');
      }));
    }
    _addClipboard(ClipboardEntry(
      content: '',
      mimeType: mimeType,
      imageBytes: bytes,
      capturedAtMs: data.capturedAtMs.toInt(),
      source: 'remote',
      byteSize: bytes.length,
    ));
  }

  Future<void> _writeImageToClipboard(Uint8List bytes, String mimeType) async {
    final clipboard = sc.SystemClipboard.instance;
    if (clipboard == null) return;
    final item = sc.DataWriterItem();
    item.add(sc.Formats.png(bytes));
    await clipboard.write([item]);
  }

  /// Manual "Send" button: always pushes [text], independent of the echo
  /// guard's dedup state, since this is an explicit user action. Still
  /// records the observation so a subsequent poll of the same clipboard
  /// content is not treated as a new change.
  Future<void> sendClipboard(String text) async {
    if (!_connection.connected || text.isEmpty) return;
    _echoGuard.observeLocalChange(text);
    await _pushLocal(text);
  }

  Future<void> _pushLocal(String text) async {
    final bytes = utf8.encode(text);
    _connection.sendFrame(pb.SyncFrame(
      clipboard: pb.ClipboardData(
        mimeType: 'text/plain',
        content: bytes,
        capturedAtMs: Int64(DateTime.now().millisecondsSinceEpoch),
        contentHash: sha256.convert(bytes).toString(),
      ),
    ));
    _addClipboard(ClipboardEntry(
      content: text,
      capturedAtMs: DateTime.now().millisecondsSinceEpoch,
      source: 'local',
    ));
  }

  /// Image counterpart of [_pushLocal] (Phase L, T-L7). T-L8: oversized
  /// content is recorded to history for visibility but never sent, same
  /// contract as the daemon's `poll_local_change`.
  Future<void> _pushLocalImage(Uint8List bytes, String mimeType) async {
    final capturedAtMs = DateTime.now().millisecondsSinceEpoch;
    if (bytes.length > _maxClipboardBytes) {
      debugPrint(
          'clipboard image (${bytes.length} bytes) exceeds the sync size cap; not sent');
      _addClipboard(ClipboardEntry(
        content: '',
        mimeType: mimeType,
        capturedAtMs: capturedAtMs,
        source: 'local',
        oversized: true,
        byteSize: bytes.length,
      ));
      return;
    }
    _connection.sendFrame(pb.SyncFrame(
      clipboard: pb.ClipboardData(
        mimeType: mimeType,
        content: bytes,
        capturedAtMs: Int64(capturedAtMs),
        contentHash: sha256.convert(bytes).toString(),
      ),
    ));
    _addClipboard(ClipboardEntry(
      content: '',
      mimeType: mimeType,
      imageBytes: bytes,
      capturedAtMs: capturedAtMs,
      source: 'local',
      byteSize: bytes.length,
    ));
  }

  void _addClipboard(ClipboardEntry entry) {
    clipboard = [entry, ...clipboard].take(_historyCap).toList(growable: false);
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }
}
