import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:multicast_dns/multicast_dns.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../models/models.dart';

/// Result type for mDNS operations - either success with devices or error message.
class DiscoveryResult {
  const DiscoveryResult._({this.devices, this.error});

  final List<NearbyDevice>? devices;
  final String? error;

  factory DiscoveryResult.success(List<NearbyDevice> devices) =>
      DiscoveryResult._(devices: devices);

  factory DiscoveryResult.error(String error) =>
      DiscoveryResult._(error: error);

  bool get isSuccess => error == null;
  bool get isError => error != null;
}

/// Discovers Connectible daemons advertising `_connectible._tcp.local`
/// on the local network (T-043), parsing the TXT records the daemon
/// publishes (device_id, device_name, platform, protocol_version -- see
/// daemon/src/discovery/mod.rs) so a peer can be listed and dialed
/// without an extra RPC. Also advertises this phone as the same service
/// type so the desktop daemon can discover it (multicast_dns is
/// browse-only, so registration goes through the OS service-discovery
/// APIs via the `nsd` plugin).
class MdnsService {
  static const String _serviceType = '_connectible._tcp.local';

  /// Service type in the form the `nsd` plugin expects (no trailing
  /// `.local`, which it appends itself).
  static const String _nsdServiceType = '_connectible._tcp';

  /// Port published in the phone's SRV record. The phone runs its own
  /// gRPC/TLS server (see `ConnectibleServer`) on this port, so a
  /// desktop peer that discovers the phone via this advertisement can
  /// dial it directly and initiate pairing/sync -- pairing is
  /// bidirectional, not phone-initiated only. Kept equal to the
  /// protocol's default port for consistency.
  static const int _advertisedPort = 58231;

  MDnsClient? _client;
  nsd.Registration? _registration;

  /// Runs a single discovery sweep and returns the devices found within
  /// [timeout]. Callers can poll this periodically to refresh a list.
  /// Returns a [DiscoveryResult] with either the device list or an error.
  Future<DiscoveryResult> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final client = MDnsClient();
    _client = client;
    final Map<String, NearbyDevice> found = {};

    try {
      await client.start();

      await for (final PtrResourceRecord ptr in client
          .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(_serviceType))
          .timeout(timeout, onTimeout: (sink) => sink.close())) {
        final device = await _resolve(client, ptr.domainName);
        if (device != null) {
          found[device.deviceId] = device;
        }
      }
    } on TimeoutException {
      // Expected end-of-sweep; return whatever resolved.
    } catch (e) {
      return DiscoveryResult.error('mDNS discovery failed: $e');
    } finally {
      client.stop();
      _client = null;
    }

    return DiscoveryResult.success(found.values.toList(growable: false));
  }

  Future<NearbyDevice?> _resolve(MDnsClient client, String serviceName) async {
    SrvResourceRecord? srv;
    await for (final record in client.lookup<SrvResourceRecord>(
      ResourceRecordQuery.service(serviceName),
    )) {
      srv = record;
      break;
    }
    if (srv == null) return null;

    final props = <String, String>{};
    await for (final txt in client.lookup<TxtResourceRecord>(
      ResourceRecordQuery.text(serviceName),
    )) {
      for (final line in txt.text.split('\n')) {
        final idx = line.indexOf('=');
        if (idx > 0) {
          props[line.substring(0, idx)] = line.substring(idx + 1);
        }
      }
      break;
    }

    String? host;
    await for (final ip in client.lookup<IPAddressResourceRecord>(
      ResourceRecordQuery.addressIPv4(srv.target),
    )) {
      host = ip.address.address;
      break;
    }
    if (host == null) return null;

    final deviceId = props['device_id'];
    if (deviceId == null || deviceId.isEmpty) return null;

    return NearbyDevice(
      deviceId: deviceId,
      deviceName: props['device_name'] ?? 'Unknown device',
      platform: props['platform'] ?? 'PLATFORM_UNSPECIFIED',
      host: host,
      port: srv.port,
    );
  }

  /// Publishes this phone on `_connectible._tcp` with the same TXT keys
  /// the daemon uses, so the desktop's mDNS browser lists it. The mDNS
  /// instance name is the `deviceId` (matching the daemon's convention),
  /// so a peer's `ServiceRemoved` pruning -- which keys off the instance
  /// label -- correctly removes this phone when it goes away. Safe to
  /// call repeatedly; a prior registration is replaced.
  Future<void> startAdvertising({
    required String deviceId,
    required String deviceName,
    required String platform,
    required int protocolVersion,
  }) async {
    await stopAdvertising();
    Uint8List enc(String v) => Uint8List.fromList(utf8.encode(v));
    _registration = await nsd.register(
      nsd.Service(
        name: deviceId,
        type: _nsdServiceType,
        port: _advertisedPort,
        txt: {
          'device_id': enc(deviceId),
          'device_name': enc(deviceName),
          'platform': enc(platform),
          'protocol_version': enc('$protocolVersion'),
        },
      ),
    );
  }

  Future<void> stopAdvertising() async {
    final registration = _registration;
    _registration = null;
    if (registration != null) {
      await nsd.unregister(registration);
    }
  }

  void dispose() {
    _client?.stop();
    _client = null;
    // Fire-and-forget: unregister the mDNS advertisement on teardown.
    unawaited(stopAdvertising());
  }
}
