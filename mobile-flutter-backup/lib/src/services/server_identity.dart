import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// This device's TLS server identity: a self-signed certificate + private
/// key in PEM, used by [ConnectibleServer] to terminate TLS 1.3 for
/// inbound connections from a desktop peer.
///
/// Trust model (MVP): peers accept any self-signed certificate (the
/// desktop's `AcceptSelfSignedCert` verifier skips chain/identity checks);
/// pairing security comes from the 6-digit PIN, not cert pinning. Each
/// device still generates its own cert once and persists it, matching the
/// daemon's `tls.rs` behavior, so certificate pinning can be layered on in
/// v1.0 without a protocol change.
class ServerIdentity {
  const ServerIdentity({required this.certPem, required this.keyPem});

  final String certPem;
  final String keyPem;

  List<int> get certBytes => utf8.encode(certPem);
  List<int> get keyBytes => utf8.encode(keyPem);

  static const _certFile = 'server_cert.pem';
  static const _keyFile = 'server_key.pem';

  /// Loads the persisted cert/key, generating and saving them on first
  /// run. Generation (RSA-2048) can take a second or two, so callers
  /// should await this off the first frame.
  static Future<ServerIdentity> loadOrCreate() async {
    final dir = await getApplicationSupportDirectory();
    final certPath = File('${dir.path}/$_certFile');
    final keyPath = File('${dir.path}/$_keyFile');

    if (await certPath.exists() && await keyPath.exists()) {
      final cert = await certPath.readAsString();
      final key = await keyPath.readAsString();
      if (cert.contains('BEGIN CERTIFICATE') && key.contains('PRIVATE KEY')) {
        return ServerIdentity(certPem: cert, keyPem: key);
      }
    }

    final identity = await compute(_generateIsolate, null);
    await certPath.writeAsString(identity.certPem, flush: true);
    await keyPath.writeAsString(identity.keyPem, flush: true);
    await _restrictPermissions(certPath, keyPath);
    return identity;
  }

  /// T-402: locks the cert/key files down to owner-only (0600),
  /// matching the daemon's `tls.rs` hardening. Android's per-app
  /// sandboxed storage already makes these files inaccessible to other
  /// apps regardless (there is no `chmod`-equivalent to run there, nor
  /// a meaningful multi-user threat model to defend against), so this
  /// only runs on Linux/macOS Flutter targets where the process could
  /// otherwise share a filesystem with other users/processes. A
  /// failure here is logged, not fatal -- the files are still usable,
  /// just not as hardened as intended.
  static Future<void> _restrictPermissions(File certPath, File keyPath) async {
    if (!(Platform.isLinux || Platform.isMacOS)) return;
    for (final path in [certPath.path, keyPath.path]) {
      try {
        final result = await Process.run('chmod', ['600', path]);
        if (result.exitCode != 0) {
          debugPrint('server identity: chmod 600 failed for $path: '
              '${result.stderr}');
        }
      } catch (e) {
        debugPrint('server identity: chmod 600 failed for $path: $e');
      }
    }
  }

  /// Runs on a background isolate (via [compute]) since RSA key
  /// generation is CPU-bound and would otherwise jank the UI.
  static ServerIdentity _generateIsolate(void _) => generate();

  /// Generates a fresh self-signed cert + key. Synchronous and IO-free,
  /// so it is also used directly by tests. Exposed for that reason.
  @visibleForTesting
  static ServerIdentity generate() {
    final pair = CryptoUtils.generateRSAKeyPair();
    final priv = pair.privateKey as RSAPrivateKey;
    final pub = pair.publicKey as RSAPublicKey;

    const dn = {'CN': 'connectible', 'O': 'Connectible'};
    final csr = X509Utils.generateRsaCsrPem(dn, priv, pub, san: ['localhost']);
    final certPem = X509Utils.generateSelfSignedCertificate(
      priv,
      csr,
      3650,
      sans: ['localhost'],
    );
    final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(priv);
    return ServerIdentity(certPem: certPem, keyPem: keyPem);
  }
}
