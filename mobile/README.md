# Connectible Mobile

Flutter (Dart) mobile client for Connectible. Same monochrome black/grey
design language, plain device list (paired + nearby, no radar/orbit),
i18n (EN/TR), and theme switching as the desktop app. Also runs its own
gRPC/TLS server so a desktop peer can pair into the phone, not just the
other way around.

## Architecture

```
mobile/
  lib/
    main.dart                bootstrap: SharedPreferences + Providers
    src/
      app.dart               MaterialApp + theme/strings scopes
      app_info.dart          shared app-version const
      theme/app_theme.dart    3 monochrome themes (charcoal/onyx/graphite)
      i18n/strings.dart       EN/TR dictionaries (localization resource)
      models/models.dart      UI models (device, clipboard, transfer, ...)
      state/
        settings_model.dart    theme + locale (Provider, persisted)
        device_list_model.dart paired/nearby roster, mDNS discovery, TOFU pins
        pairing_model.dart     pairing flow (both directions) + active session
                                lifecycle (SyncStream, heartbeat, reconnect)
        file_transfer_model.dart send/receive (PrepareUpload/UploadFile) + history
        clipboard_model.dart    clipboard sync
        battery_model.dart      battery level reporting
        notification_model.dart notification mirroring (Android)
      services/
        mdns_service.dart       _connectible._tcp discovery
        grpc_service.dart       outbound gRPC client over TLS 1.3
        connectible_server.dart inbound gRPC/TLS server (phone as responder)
        pairing_manager.dart    responder-side PIN issuing/verification
        server_identity.dart    this device's TLS cert/key identity
        notification_listener.dart native notification-access bridge
        doctor/                 System Doctor diagnostics engine
      screens/                  home, clipboard, transfers, remote input,
                                 notifications, doctor, settings, pairing
      widgets/                  pairing sheets, shared UI (monogram, icons, ...)
      generated/                gRPC stubs (generate; see below)
```

State management is **Provider**; every `*_model.dart` above is a
`ChangeNotifier` exposed via `MultiProvider` (see `state/app_providers.dart`).

## Prerequisites

- Flutter SDK 3.22+ (Dart 3.4+)
- A running `connectibled` daemon on the same LAN to pair with.

## Build and run

```sh
# 1. Scaffold the platform folders (android/ios) if not present.
flutter create --platforms=android,ios .

# 2. Fetch packages.
flutter pub get

# 3. Generate the Dart gRPC stubs from the shared proto.
dart pub global activate protoc_plugin 21.1.2
export PATH="$PATH:$HOME/.pub-cache/bin"
./tool/gen_proto.sh

# 4. Run.
flutter run
```

The app will not compile until step 3 has generated
`lib/src/generated/connectible.pbgrpc.dart` (see that folder's README).

## Design parity with desktop

- Monochrome only (black/grey), near-white accent; danger red is the
  only accent color (no blue/gold).
- Home: this device's own row, a "Paired" section, and a "Nearby"
  section for unpaired mDNS-discovered peers -- a plain grouped-card
  device list, not an orbit/radar visualization.
- Settings: theme cards (charcoal/onyx/graphite) + EN/TR language, both
  persisted via `shared_preferences`; notification mirroring, clipboard
  sync, and System Doctor diagnostics all live here too.
- Pairing: bottom sheet with 6-digit PIN entry and a 30-second
  countdown, plus QR scan-to-pair; works in both directions (phone can
  initiate pairing to a desktop, or a desktop/phone can pair into this
  phone via its own inbound server).

## Known limitations

- Self-signed peer certs are accepted on first connect and then pinned
  (TOFU) per device_id; there is no CA-based identity verification, so
  security rests on the PIN exchange at pairing time, not certificate
  identity -- matching the daemon's own trust model.
- The phone's own inbound server has no TLS-layer client-certificate
  verification (a `dart:io` limitation on the responder side); inbound
  frames are gated on the claimed device_id being paired instead. See
  `ConnectibleServer.start`'s doc comment for the full account.
- Being remotely controlled (a desktop sending input events to this
  phone) is not implemented -- the phone can only be the controller,
  not the controlled device.

## Integration test (daemon)

```sh
cargo build -p connectibled && RUN_DAEMON_INTEGRATION=1 flutter test test/integration/daemon_integration_test.dart
```
