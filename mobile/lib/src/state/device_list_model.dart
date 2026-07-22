import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/mdns_service.dart';
import '../generated/connectible.pbgrpc.dart' as pb;

/// Owns device discovery/mDNS and the paired-devices list (T-204). This is
/// the identity/roster half of what used to be the monolithic `AppModel`:
/// this device's own [localIdentity], the live mDNS-discovered [nearby]
/// list, and the persisted [devices] roster (paired devices, merged with
/// whatever the active session last reported via [mergeFromConnection]).
///
/// Deliberately has no notion of an active connection -- [PairingModel]
/// owns that and depends on this model (one-directional) to read/update
/// identity and the paired roster.
class DeviceListModel extends ChangeNotifier {
  DeviceListModel(this._prefs,
      {required String deviceName, bool pairableEnabled = true})
      : _pairableEnabled = pairableEnabled {
    _initIdentity(deviceName);
    _loadPairedStore();
  }

  final SharedPreferences _prefs;
  final MdnsService _mdns = MdnsService();

  /// Mirrors `SettingsModel.pairableEnabled` (T-308): whether this phone
  /// advertises itself as pairable over mDNS. Set at construction from
  /// the persisted setting and kept live-updatable via
  /// [setPairableEnabled] so the Settings screen's toggle takes effect
  /// immediately, without restarting the app.
  bool _pairableEnabled;
  bool get pairableEnabled => _pairableEnabled;

  /// Locally-remembered paired devices. On the responder path there is no
  /// outgoing connection to list peers from, so pairings are persisted
  /// here and merged into [devices].
  List<DeviceInfo> _pairedStore = const [];

  late pb.Identity localIdentity;
  String get deviceName => localIdentity.deviceName;

  List<NearbyDevice> nearby = const [];
  List<DeviceInfo> devices = const [];
  String? lastDiscoveryError;

  Timer? _discoveryTimer;

  // --- identity -----------------------------------------------------------

  void _initIdentity(String deviceName) {
    var id = _prefs.getString('connectible.device_id');
    if (id == null || id.isEmpty) {
      id = _uuidV4();
      _prefs.setString('connectible.device_id', id);
    }
    localIdentity = pb.Identity(
      deviceId: id,
      deviceName: deviceName,
      platform: _currentPlatform(),
      deviceType: pb.DeviceType.DEVICE_TYPE_PHONE,
      protocolVersion: 1,
      appVersion: '0.1.0',
      // Advertise only capabilities this app actually implements.
      // `battery` is really sent (Phase B / BatteryModel); `notifications`
      // is now implemented too (Phase B / NotificationModel, gated on the
      // user granting system Notification access at runtime). We advertise
      // support, not the runtime grant state -- matching how the desktop
      // advertises its capabilities.
      capabilities: const [
        'clipboard',
        'file_transfer',
        'remote_input',
        'battery',
        'notifications',
      ],
    );
  }

  /// The concrete platform this build runs on, so peers and mDNS TXT
  /// records report the truth instead of a hardcoded Android.
  static pb.Platform _currentPlatform() {
    if (Platform.isAndroid) return pb.Platform.PLATFORM_ANDROID;
    if (Platform.isIOS) return pb.Platform.PLATFORM_IOS;
    if (Platform.isMacOS) return pb.Platform.PLATFORM_MACOS;
    if (Platform.isWindows) return pb.Platform.PLATFORM_WINDOWS;
    if (Platform.isLinux) return pb.Platform.PLATFORM_LINUX_X11;
    return pb.Platform.PLATFORM_UNSPECIFIED;
  }

  /// The proto enum's string name (e.g. "PLATFORM_ANDROID"), computed
  /// explicitly rather than via `.name`, which the generated code blanks
  /// out when built with `protobuf.omit_enum_names`. Public so the gRPC
  /// service layer can label a paired peer's platform the same way when
  /// converting a wire Identity into a UI DeviceInfo (T-E6).
  static String platformName(pb.Platform p) => _platformName(p);

  static String _platformName(pb.Platform p) {
    if (p == pb.Platform.PLATFORM_ANDROID) return 'PLATFORM_ANDROID';
    if (p == pb.Platform.PLATFORM_IOS) return 'PLATFORM_IOS';
    if (p == pb.Platform.PLATFORM_MACOS) return 'PLATFORM_MACOS';
    if (p == pb.Platform.PLATFORM_WINDOWS) return 'PLATFORM_WINDOWS';
    if (p == pb.Platform.PLATFORM_LINUX_WAYLAND) {
      return 'PLATFORM_LINUX_WAYLAND';
    }
    if (p == pb.Platform.PLATFORM_LINUX_X11) return 'PLATFORM_LINUX_X11';
    return 'PLATFORM_UNSPECIFIED';
  }

  // --- paired-devices store ------------------------------------------------

  /// A remote peer completed pairing to this phone (responder side, PIN
  /// confirmed by the peer). Persists it as a known paired device. Called
  /// by [PairingModel.onPeerPaired].
  void addPairedDevice(pb.Identity requester) {
    _upsertPairedPeer(
      deviceId: requester.deviceId,
      deviceName: requester.deviceName,
      platform: _platformName(requester.platform),
    );
  }

  /// This phone completed pairing *to* a remote responder (requester side,
  /// PIN confirmed on this phone -- T-X1). Persists the peer using the
  /// identity data mDNS discovery / manual connect already provided, so a
  /// phone-initiated pairing survives an app restart exactly like a
  /// responder-side one, desktop->phone pushes pass the paired-store gate,
  /// and the TOFU fingerprint pin has a row to land on. Called by
  /// [PairingModel.confirmPin] on success.
  void addPairedDeviceFromNearby(NearbyDevice device) {
    _upsertPairedPeer(
      deviceId: device.deviceId,
      deviceName: device.deviceName,
      platform: device.platform,
    );
  }

  /// Shared upsert for both pairing directions: newest row wins (a
  /// deliberate re-pair replaces the old entry, dropping any stale cert
  /// fingerprint so the fresh one can be pinned right after).
  void _upsertPairedPeer({
    required String deviceId,
    required String deviceName,
    required String platform,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final peer = DeviceInfo(
      deviceId: deviceId,
      deviceName: deviceName.isEmpty ? 'Unknown device' : deviceName,
      online: true,
      pairedAtMs: now,
      lastSeenMs: now,
      platform: platform,
    );
    _pairedStore = [
      peer,
      for (final d in _pairedStore)
        if (d.deviceId != peer.deviceId) d,
    ];
    _savePairedStore();
    _mergeDevices();
    notifyListeners();
  }

  /// Paired devices to report to a peer's ListDevices call. Called by
  /// [PairingModel]'s `ServerDelegate` implementation.
  List<DeviceInfo> knownDevices() => _pairedStore;

  /// Permanently removes [deviceId] from the local paired-devices roster
  /// (T-307), distinct from [PairingModel.disconnect] which only drops the
  /// active session. Re-pairing afterward requires a fresh PIN exchange
  /// since the device no longer appears as a known peer to either side.
  void forgetDevice(String deviceId) {
    if (!_pairedStore.any((d) => d.deviceId == deviceId)) return;
    _pairedStore =
        _pairedStore.where((d) => d.deviceId != deviceId).toList(growable: false);
    _savePairedStore();
    _mergeDevices();
    notifyListeners();
  }

  /// Merges the active session's own `ListDevices` response into the
  /// roster, so a device paired from either direction stays visible.
  /// Called by [PairingModel.refreshDevices].
  void mergeFromConnection(List<DeviceInfo> fromConnection) {
    _mergeDevices(fromConnection);
    notifyListeners();
  }

  void _loadPairedStore() {
    final raw = _prefs.getString('connectible.paired_devices');
    if (raw == null || raw.isEmpty) {
      _mergeDevices();
      return;
    }
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _pairedStore = list
          .map((m) => DeviceInfo(
                deviceId: m['id'] as String,
                deviceName: m['name'] as String,
                online: false,
                pairedAtMs: (m['pairedAt'] as num?)?.toInt() ?? 0,
                lastSeenMs: (m['pairedAt'] as num?)?.toInt() ?? 0,
                platform: m['platform'] as String? ?? '',
                certFingerprint: m['certFingerprint'] as String? ?? '',
              ))
          .toList(growable: false);
    } catch (e) {
      debugPrint('paired store parse failed: $e');
      _pairedStore = const [];
    }
    _mergeDevices();
  }

  void _savePairedStore() {
    final json = jsonEncode(_pairedStore
        .map((d) => {
              'id': d.deviceId,
              'name': d.deviceName,
              'pairedAt': d.pairedAtMs,
              'platform': d.platform,
              'certFingerprint': d.certFingerprint,
            })
        .toList(growable: false));
    _prefs.setString('connectible.paired_devices', json);
  }

  /// TOFU (T-C4): the pinned cert fingerprint for a paired device, or
  /// `null` if it has none yet (a legacy entry awaiting first-use backfill).
  String? pinnedFingerprint(String deviceId) {
    for (final d in _pairedStore) {
      if (d.deviceId == deviceId) {
        return d.certFingerprint.isEmpty ? null : d.certFingerprint;
      }
    }
    return null;
  }

  /// TOFU (T-C4/C5): pins [fingerprint] for a paired device (record-on-
  /// first-use / backfill). No-op if the device is not in the paired store.
  void recordFingerprint(String deviceId, String fingerprint) {
    var changed = false;
    _pairedStore = _pairedStore.map((d) {
      if (d.deviceId != deviceId || d.certFingerprint == fingerprint) return d;
      changed = true;
      return DeviceInfo(
        deviceId: d.deviceId,
        deviceName: d.deviceName,
        online: d.online,
        pairedAtMs: d.pairedAtMs,
        lastSeenMs: d.lastSeenMs,
        platform: d.platform,
        certFingerprint: fingerprint,
      );
    }).toList(growable: false);
    if (changed) {
      _savePairedStore();
      _mergeDevices();
      notifyListeners();
    }
  }

  void _mergeDevices([List<DeviceInfo> fromConnection = const <DeviceInfo>[]]) {
    final byId = <String, DeviceInfo>{};
    for (final d in _pairedStore) {
      byId[d.deviceId] = d;
    }
    for (final d in fromConnection) {
      byId[d.deviceId] = d;
    }
    // A peer's ListDevices response includes *this phone* as one of its
    // paired devices; without this filter the phone showed up in its own
    // "Paired" list mid-session (T-X4).
    byId.remove(localIdentity.deviceId);
    devices = byId.values.toList(growable: false);
  }

  // --- discovery ------------------------------------------------------------

  void startDiscovery() {
    // Hold the Wi-Fi multicast lock for the duration of discovery (T-X20):
    // without it most devices filter the inbound mDNS multicast and browsing
    // silently finds nothing. No-op off Android.
    unawaited(_mdns.acquireMulticastLock());
    sweep();
    _discoveryTimer?.cancel();
    _discoveryTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => sweep());
    // Advertise this phone so the desktop daemon can discover it -- the
    // browse-only path alone left the desktop unable to see the phone.
    // Skipped entirely while the user has disabled "allow this phone to
    // be paired into" (T-308).
    if (_pairableEnabled) {
      _advertise();
    }
  }

  void stopDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    // Drop the multicast lock while not discovering (T-X20) so it is not held
    // needlessly (battery); reacquired on the next startDiscovery.
    unawaited(_mdns.releaseMulticastLock());
    unawaited(
      _mdns.stopAdvertising().catchError(
          (Object e) => debugPrint('mdns stop advertise failed: $e')),
    );
  }

  void _advertise() {
    unawaited(
      _mdns
          .startAdvertising(
            deviceId: localIdentity.deviceId,
            deviceName: localIdentity.deviceName,
            platform: _platformName(localIdentity.platform),
            protocolVersion: localIdentity.protocolVersion,
          )
          .catchError((Object e) => debugPrint('mdns advertise failed: $e')),
    );
  }

  /// Applies the Settings screen's "allow this phone to be paired into"
  /// toggle (T-308) live: stops advertising immediately when disabled
  /// (device browsing for *other* nearby devices keeps running), resumes
  /// it immediately when re-enabled if discovery is currently active.
  void setPairableEnabled(bool enabled) {
    if (enabled == _pairableEnabled) return;
    _pairableEnabled = enabled;
    if (enabled) {
      if (_discoveryTimer != null) _advertise();
    } else {
      unawaited(
        _mdns.stopAdvertising().catchError(
            (Object e) => debugPrint('mdns stop advertise failed: $e')),
      );
    }
  }

  /// Manual refresh used by the device action menu / pull-to-refresh:
  /// re-scan for nearby devices. Callers that also want the paired roster
  /// re-fetched from the active session should additionally call
  /// [PairingModel.refreshDevices].
  Future<void> refresh() => sweep();

  /// Runs on a 5-second timer while discovery is active. Most sweeps
  /// rediscover exactly the same peers, so this only calls
  /// [notifyListeners] when the visible set or the error state actually
  /// changed -- otherwise every tick would force a full Home-screen
  /// rebuild (every row, the status line, quick actions) for no visual
  /// change, which is exactly the kind of periodic jank that makes the
  /// UI feel less smooth than it should.
  Future<void> sweep() async {
    final previousNearby = nearby;
    final previousError = lastDiscoveryError;
    try {
      final result = await _mdns.discover();
      if (result.isError) {
        lastDiscoveryError = result.error;
      } else {
        lastDiscoveryError = null;
        nearby = result.devices!
            .where((d) => d.deviceId != localIdentity.deviceId)
            .toList(growable: false);
      }
    } catch (e) {
      lastDiscoveryError = 'mDNS sweep failed: $e';
      debugPrint('mdns sweep failed: $e');
    }
    if (lastDiscoveryError != previousError ||
        !_sameNearby(previousNearby, nearby)) {
      notifyListeners();
    }
  }

  static bool _sameNearby(List<NearbyDevice> a, List<NearbyDevice> b) {
    if (a.length != b.length) return false;
    final byId = {for (final d in a) d.deviceId: d};
    for (final d in b) {
      final prev = byId[d.deviceId];
      if (prev == null ||
          prev.deviceName != d.deviceName ||
          prev.platform != d.platform ||
          prev.host != d.host ||
          prev.port != d.port) {
        return false;
      }
    }
    return true;
  }

  static String _uuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  @override
  void dispose() {
    stopDiscovery();
    _mdns.dispose();
    super.dispose();
  }
}
