import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../models/models.dart';
import '../services/connectible_server.dart' show kServerPort;
import '../state/device_list_model.dart';
import '../state/pairing_model.dart';
import '../theme/app_theme.dart';
import '../widgets/pairing_sheet.dart';
import '../widgets/ui.dart';

/// A parsed `connectible://pair?...` QR payload -- the desktop-side
/// encoder lives at desktop/src/lib/pairingCode.ts, keep the two in
/// sync. Carries the PIN directly (pre-armed by the desktop before
/// showing the code, see daemon PairingManager::pre_arm), so scanning
/// it needs no manual PIN entry.
class ScannedPairingCode {
  const ScannedPairingCode({
    required this.host,
    required this.port,
    required this.pin,
    required this.deviceId,
    required this.deviceName,
  });

  final String host;
  final int port;
  final String pin;
  final String deviceId;
  final String deviceName;

  static ScannedPairingCode? tryParse(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'connectible' || uri.host != 'pair') {
      return null;
    }
    final q = uri.queryParameters;
    final host = q['host'];
    final port = int.tryParse(q['port'] ?? '');
    final pin = q['pin'];
    final id = q['id'];
    final name = q['name'];
    if (host == null ||
        host.isEmpty ||
        port == null ||
        pin == null ||
        pin.length != 6 ||
        id == null ||
        id.isEmpty) {
      return null;
    }
    return ScannedPairingCode(
      host: host,
      port: port,
      pin: pin,
      deviceId: id,
      deviceName: name ?? host,
    );
  }
}

/// Camera-based pairing scanner (scan-to-pair). A real detected QR is
/// parsed as a [ScannedPairingCode] and paired immediately -- the PIN
/// travels inside the code itself (pre-armed by the desktop, see
/// PairingQrDialog), so there's no PIN sheet to fill in. The
/// "Simulate scan" button is a dev/no-camera fallback (Linux desktop
/// target, §0): it still uses the mock-against-nearby-device path with
/// the manual [PairingSheet], since there's no real QR to decode there.
class PairScanScreen extends StatefulWidget {
  const PairScanScreen({super.key});

  @override
  State<PairScanScreen> createState() => _PairScanScreenState();
}

class _PairScanScreenState extends State<PairScanScreen> {
  // mobile_scanner has no Linux/Windows implementation; checking the
  // platform up front avoids depending on the plugin's internal
  // error-recovery path on desktop dev targets (§0's flutter run -d linux).
  static final bool _cameraSupported =
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  MobileScannerController? _controller;
  bool _handled = false;

  /// Guards against spamming a SnackBar on every single camera frame
  /// while it stays pointed at a real but non-Connectible QR code; reset
  /// after a short cooldown so a *different* invalid code (or the same
  /// one scanned again later) still gets feedback.
  bool _invalidCodeNoticeShown = false;

  @override
  void initState() {
    super.initState();
    if (_cameraSupported) {
      _controller = MobileScannerController();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  NearbyDevice _mockDevice() {
    final nearby = context.read<DeviceListModel>().nearby;
    if (nearby.isNotEmpty) return nearby.first;
    return const NearbyDevice(
      deviceId: 'mock:qr-pair',
      deviceName: 'Desktop (simulated)',
      platform: 'PLATFORM_LINUX_X11',
      host: '127.0.0.1',
      port: kServerPort,
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final code = ScannedPairingCode.tryParse(raw);
      if (code != null) {
        unawaited(_pairWithScannedCode(code));
        return;
      }
      // A real barcode was decoded but it isn't a `connectible://pair`
      // code -- tell the user instead of silently doing nothing (the
      // previous behavior made a scanned-but-wrong QR indistinguishable
      // from the camera just not having detected anything yet).
      if (!_invalidCodeNoticeShown) {
        _invalidCodeNoticeShown = true;
        _showError(context.strings.t('pairing.scan.invalidCode'));
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _invalidCodeNoticeShown = false;
        });
      }
    }
  }

  /// Real scan-to-pair: the code carries a PIN the desktop already
  /// pre-armed with the daemon, so `startPair` + `confirmPin` run back
  /// to back with no human PIN entry in between.
  Future<void> _pairWithScannedCode(ScannedPairingCode code) async {
    _handled = true;
    final s = context.strings;
    final model = context.read<PairingModel>();
    final device = NearbyDevice(
      deviceId: code.deviceId,
      deviceName: code.deviceName,
      platform: '',
      host: code.host,
      port: code.port,
    );
    final started = await model.startPair(device);
    if (!mounted) return;
    if (!started) {
      // T-X32: rejected gets the same translated string home_screen.dart
      // uses; anything else falls back to the model's own message
      // (arbitrary transport/peer text with no i18n key of its own).
      final message = model.lastErrorKind == PairingErrorKind.rejected
          ? s.t('home.pairingRejected')
          : model.lastError ?? s.t('pairing.incorrectPin');
      _showError(message);
      _handled = false;
      return;
    }
    final verified = await model.confirmPin(code.pin);
    if (!mounted) return;
    if (verified) {
      Navigator.of(context).pop();
    } else {
      _showError(s.t('pairing.incorrectPin'));
      _handled = false;
    }
  }

  /// Dev/no-camera fallback: mocks a scan against a nearby-discovered
  /// device (or a hardcoded one) and shows the normal manual PIN sheet,
  /// exactly like the tap-a-star flow -- there's no real QR to decode
  /// on the Linux desktop dev target.
  Future<void> _onSimulate() async {
    if (_handled) return;
    _handled = true;
    final device = _mockDevice();
    final model = context.read<PairingModel>();
    final ok = await model.startPair(device);
    if (!mounted) return;
    final pending = model.pendingPairing;
    if (ok && pending != null) {
      await PairingSheet.show(context,
          deviceName: displayDeviceName(device.deviceName, context.strings),
          pinExpiresAtMs: pending.pinExpiresAtMs);
      if (!mounted) return;
      Navigator.of(context).pop();
    } else {
      _handled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final controller = _controller;

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        backgroundColor: p.canvas,
        elevation: 0,
        iconTheme: IconThemeData(color: p.ink),
        title: Text(s.t('pairing.scan.title'),
            style: TextStyle(
                color: p.ink, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (controller != null)
                  MobileScanner(
                    controller: controller,
                    onDetect: _onDetect,
                    // A runtime CAMERA-permission denial and actual
                    // missing camera hardware both used to show the same
                    // "this device has no camera" copy, which is actively
                    // misleading for the permission case -- the user can
                    // fix that by granting access, not by getting new
                    // hardware. mobile_scanner reports which one it was
                    // via MobileScannerException.errorCode.
                    errorBuilder: (context, error) =>
                        error.errorCode == MobileScannerErrorCode.permissionDenied
                            ? EmptyState(
                                icon: Icons.no_photography_outlined,
                                title: s.t('pairing.scan.permissionDenied'),
                                hint: s.t('pairing.scan.permissionDeniedHint'),
                              )
                            : EmptyState(
                                icon: Icons.videocam_off_outlined,
                                title: s.t('pairing.scan.noCamera'),
                                hint: s.t('pairing.scan.noCameraHint'),
                              ),
                  )
                else
                  EmptyState(
                    icon: Icons.videocam_off_outlined,
                    title: s.t('pairing.scan.noCamera'),
                    hint: s.t('pairing.scan.noCameraHint'),
                  ),
                const IgnorePointer(child: _ReticleOverlay()),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              children: [
                Text(
                  s.t('pairing.scan.hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: p.inkMuted),
                ),
                const SizedBox(height: 16),
                _SimulateButton(
                  label: s.t('pairing.scan.simulate'),
                  onTap: _onSimulate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Static reticle square; no per-frame animation (§1.3 perf rule).
class _ReticleOverlay extends StatelessWidget {
  const _ReticleOverlay();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: p.ink.withValues(alpha: 0.5), width: 2),
        ),
      ),
    );
  }
}

class _SimulateButton extends StatelessWidget {
  const _SimulateButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: p.line),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
        ),
      ),
    );
  }
}
