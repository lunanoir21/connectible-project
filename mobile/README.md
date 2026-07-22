# Connectible Mobile

Flutter (Dart) mobile client for Connectible. Same monochrome black/grey
design language, radar home screen, i18n (EN/TR), and theme switching as
the desktop app.

## Architecture

```
mobile/
  lib/
    main.dart                bootstrap: SharedPreferences + Providers
    src/
      app.dart               MaterialApp + theme/strings scopes
      theme/app_theme.dart    3 monochrome themes (charcoal/onyx/graphite)
      i18n/strings.dart       EN/TR dictionaries (localization resource)
      models/models.dart      UI models (device, clipboard, transfer, ...)
      state/
        settings_model.dart   theme + locale (Provider, persisted)
        app_model.dart         identity, mDNS, pairing, sync stream, files
      services/
        mdns_service.dart      _connectible._tcp discovery (T-043)
        grpc_service.dart      gRPC client over TLS 1.3 (T-044)
        crc32.dart             per-chunk checksum for file transfer
      screens/                 home (radar), clipboard, transfers, remote, settings
      widgets/                 radar painter, pairing sheet, shared UI
      generated/               gRPC stubs (generate; see below)
```

State management is **Provider** (per project spec). `AppModel` and
`SettingsModel` are `ChangeNotifier`s exposed via `MultiProvider`.

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

- Monochrome only (black/grey), near-white accent; no blue/gold.
- Radar home: this device at the center, online paired devices on an
  inner orbit, pairable nearby devices (platform icons) on an outer
  orbit, animated sonar + rotating sweep painted with `CustomPainter`.
- Settings: theme cards (charcoal/onyx/graphite) + EN/TR language, both
  persisted via `shared_preferences`.
- Pairing: bottom sheet with 6-digit PIN entry and a 30-second countdown
  (T-045).

## Known limitations (MVP)

- Self-signed daemon certs are accepted without pinning (see
  `grpc_service.dart`); cert pinning is a v1.0 item, matching the daemon.
- Notification forwarding + battery reporting (T-048a) are scaffolded in
  the protocol but not yet surfaced in the mobile UI.

## Integration test (daemon)

```sh
cargo build -p connectibled && RUN_DAEMON_INTEGRATION=1 flutter test test/integration/daemon_integration_test.dart
```
