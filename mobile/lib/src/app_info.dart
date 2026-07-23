/// Single source of truth for the app version string (T-X33), mirroring
/// `pubspec.yaml`'s `version:` field. Previously hand-written in two
/// places (`DeviceListModel.localIdentity.appVersion`, the Settings
/// "About" row) that could silently drift on a version bump.
const String kAppVersion = '0.1.0';
