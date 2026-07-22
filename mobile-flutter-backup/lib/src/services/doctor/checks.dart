import 'dart:io' show NetworkInterface, InternetAddressType;

import '../mdns_service.dart';
import '../notification_listener.dart';
import '../../state/pairing_model.dart';
import 'doctor.dart';

/// Builds the full mobile check set from the app's live models/services.
/// Kept as a factory (not hard-wired) so the Doctor screen injects real
/// instances and tests can inject fakes.
List<DoctorCheck> buildMobileChecks({
  required PairingModel pairing,
  required bool pairableEnabled,
  required NotificationListener notifications,
  MdnsService? mdns,
}) {
  return [
    ServerBoundCheck(pairing: pairing, pairableEnabled: pairableEnabled),
    NetworkCheck(),
    ActiveSessionCheck(pairing: pairing),
    DiscoveryCheck(mdns: mdns ?? MdnsService()),
    NotificationPermissionCheck(notifications: notifications),
    ClipboardAccessCheck(),
    BatteryOptimizationCheck(),
    StorageAccessCheck(),
  ];
}

// --- connectivity ----------------------------------------------------------

/// Is this phone's inbound gRPC/TLS server bound so peers can reach it?
class ServerBoundCheck extends DoctorCheck {
  ServerBoundCheck({required this.pairing, required this.pairableEnabled});
  final PairingModel pairing;
  final bool pairableEnabled;

  @override
  String get id => 'server-bound';
  @override
  String get title => 'Incoming server';
  @override
  DoctorCategory get category => DoctorCategory.connectivity;

  @override
  Future<DoctorCheckResult> run() async {
    if (pairing.serverRunning) {
      return DoctorCheckResult(
        id: id,
        title: title,
        category: category,
        status: DoctorStatus.ok,
        summary: 'Listening for incoming connections',
      );
    }
    if (!pairableEnabled) {
      return DoctorCheckResult(
        id: id,
        title: title,
        category: category,
        status: DoctorStatus.warn,
        summary: 'Not discoverable',
        detail: 'The incoming server is off because Discoverable is disabled.',
        remediation: 'Turn on Discoverable in Settings so other devices can pair and reach this phone.',
      );
    }
    return DoctorCheckResult(
      id: id,
      title: title,
      category: category,
      status: DoctorStatus.error,
      summary: 'Server not bound',
      detail: 'Discoverable is on but the inbound server is not listening.',
      remediation: 'Toggle Discoverable off and on again, or restart the app.',
    );
  }
}

/// Is the phone on a network (a non-loopback IPv4 address)?
class NetworkCheck extends DoctorCheck {
  @override
  String get id => 'network';
  @override
  String get title => 'Network connection';
  @override
  DoctorCategory get category => DoctorCategory.connectivity;

  @override
  Future<DoctorCheckResult> run() async {
    final ip = await _primaryIpv4();
    if (ip != null) {
      return DoctorCheckResult(
        id: id,
        title: title,
        category: category,
        status: DoctorStatus.ok,
        summary: 'Connected ($ip)',
      );
    }
    return DoctorCheckResult(
      id: id,
      title: title,
      category: category,
      status: DoctorStatus.error,
      summary: 'No network',
      detail: 'No non-loopback IPv4 address is available.',
      remediation: 'Join the same Wi-Fi/LAN as the device you want to reach.',
    );
  }

  Future<String?> _primaryIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {
      // Fall through to "no network".
    }
    return null;
  }
}

/// Is there a live paired-peer session right now? (Informational -- not
/// being connected is normal, so this never errors.)
class ActiveSessionCheck extends DoctorCheck {
  ActiveSessionCheck({required this.pairing});
  final PairingModel pairing;

  @override
  String get id => 'active-session';
  @override
  String get title => 'Active session';
  @override
  DoctorCategory get category => DoctorCategory.connectivity;

  @override
  Future<DoctorCheckResult> run() async {
    if (pairing.connected) {
      return DoctorCheckResult(
        id: id,
        title: title,
        category: category,
        status: DoctorStatus.ok,
        summary: 'Connected to ${pairing.activePeerName ?? 'a device'}',
      );
    }
    return DoctorCheckResult(
      id: id,
      title: title,
      category: category,
      status: DoctorStatus.ok,
      summary: 'No active session',
      detail: 'Not currently connected to a paired device (this is normal when idle).',
    );
  }
}

/// Does mDNS discovery find peers on the LAN?
class DiscoveryCheck extends DoctorCheck {
  DiscoveryCheck({required this.mdns});
  final MdnsService mdns;

  @override
  String get id => 'mdns-discovery';
  @override
  String get title => 'Device discovery';
  @override
  DoctorCategory get category => DoctorCategory.connectivity;

  @override
  Future<DoctorCheckResult> run() async {
    final result = await mdns.discover(timeout: const Duration(seconds: 3));
    if (result.error != null) {
      return DoctorCheckResult(
        id: id,
        title: title,
        category: category,
        status: DoctorStatus.warn,
        summary: 'Discovery failed',
        detail: result.error,
        remediation: 'Ensure Wi-Fi is on and the network allows multicast (some guest/AP-isolated networks block it).',
      );
    }
    final count = result.devices?.length ?? 0;
    return DoctorCheckResult(
      id: id,
      title: title,
      category: category,
      status: count > 0 ? DoctorStatus.ok : DoctorStatus.warn,
      summary: count > 0 ? '$count device(s) found nearby' : 'No devices found',
      remediation: count > 0
          ? null
          : 'Open Connectible on another device on the same network; if it still fails, the network may block mDNS.',
    );
  }
}

// --- permissions -----------------------------------------------------------

/// System "Notification access" grant state, with a deep link to fix it.
class NotificationPermissionCheck extends DoctorCheck {
  NotificationPermissionCheck({required this.notifications});
  final NotificationListener notifications;

  @override
  String get id => 'notification-access';
  @override
  String get title => 'Notification access';
  @override
  DoctorCategory get category => DoctorCategory.permissions;

  @override
  Future<DoctorCheckResult> run() async {
    final state = await notifications.accessState;
    final granted = state == NotificationAccessState.granted;
    return DoctorCheckResult(
      id: id,
      title: title,
      category: category,
      status: granted ? DoctorStatus.ok : DoctorStatus.warn,
      summary: granted ? 'Granted' : 'Not granted',
      detail: granted
          ? null
          : 'Notification mirroring needs system Notification access.',
      remediation: granted
          ? null
          : 'Grant "Notification access" to Connectible to mirror notifications.',
      action: granted ? null : () => notifications.openAccessSettings(),
      actionLabel: granted ? null : 'Open settings',
    );
  }
}

/// Android restricts background clipboard reads (Android 10+): only the
/// focused app can read the clipboard. Reported as info so the user
/// understands why auto-clipboard only works while the app is open.
class ClipboardAccessCheck extends DoctorCheck {
  @override
  String get id => 'clipboard-access';
  @override
  String get title => 'Clipboard access';
  @override
  DoctorCategory get category => DoctorCategory.permissions;

  @override
  Future<DoctorCheckResult> run() async {
    return DoctorCheckResult(
      id: id,
      title: title,
      category: category,
      status: DoctorStatus.ok,
      summary: 'Available while the app is open',
      detail: 'Android only allows clipboard reads while Connectible is in the foreground; auto-sync pauses in the background by design.',
    );
  }
}

/// Battery optimization can kill the app in the background, dropping
/// sessions. We cannot read the exemption state without a native call, so
/// this is a recommendation with guidance rather than a detected state.
class BatteryOptimizationCheck extends DoctorCheck {
  @override
  String get id => 'battery-optimization';
  @override
  String get title => 'Battery optimization';
  @override
  DoctorCategory get category => DoctorCategory.permissions;

  @override
  Future<DoctorCheckResult> run() async {
    return DoctorCheckResult(
      id: id,
      title: title,
      category: category,
      status: DoctorStatus.warn,
      summary: 'Exempt Connectible for reliable background sync',
      detail: 'If the system optimizes Connectible\'s battery use, it may be stopped in the background and drop connections.',
      remediation: 'In system Settings > Apps > Connectible > Battery, allow unrestricted background activity.',
    );
  }
}

// --- storage ---------------------------------------------------------------

/// Received files are exported via the system file picker (SAF), which
/// grants per-save access -- no standing storage permission is needed.
class StorageAccessCheck extends DoctorCheck {
  @override
  String get id => 'storage-access';
  @override
  String get title => 'Saving received files';
  @override
  DoctorCategory get category => DoctorCategory.storage;

  @override
  Future<DoctorCheckResult> run() async {
    return DoctorCheckResult(
      id: id,
      title: title,
      category: category,
      status: DoctorStatus.ok,
      summary: 'Save-to picker available',
      detail: 'Received files are saved with the system picker ("Save to..."), which grants access per file -- no storage permission required.',
    );
  }
}
