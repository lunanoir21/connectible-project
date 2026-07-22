import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Outcome of a "Save to..." attempt (T-X6).
enum SaveFileOutcome {
  /// The file was copied to the user-chosen destination.
  saved,

  /// The user backed out of the destination picker; nothing to report.
  canceled,

  /// The picker or the copy failed.
  failed,
}

/// Narrow seam the transfers screen's "Save to..." action goes through,
/// so widget tests can inject a fake without touching platform channels
/// (mirrors [NotificationListener]'s injectable-seam pattern).
abstract class SaveFileService {
  /// Copies the file at [sourcePath] to a destination the user picks.
  /// The copy must stream with a bounded buffer -- implementations never
  /// load the whole file into memory (the pre-T-X6 `readAsBytes` +
  /// `FilePicker.saveFile(bytes:)` route OOMed on GB-scale transfers).
  Future<SaveFileOutcome> saveAs({
    required String sourcePath,
    required String fileName,
    String? dialogTitle,
  });
}

/// The method channel `MainActivity`'s `SaveFilePlugin` listens on.
@visibleForTesting
const MethodChannel saveFileChannel = MethodChannel('connectible/savefile');

/// Production [SaveFileService]. On Android the entire flow is native
/// (T-X6): ACTION_CREATE_DOCUMENT picks the destination and Kotlin
/// streams the copy with a fixed 64 KiB buffer, so no file byte ever
/// crosses the platform channel or accumulates in the Dart heap. On
/// non-Android dev builds (the `linux/` shell) the system save dialog
/// yields a plain path and the copy streams through dart:io instead.
class PlatformSaveFileService implements SaveFileService {
  const PlatformSaveFileService();

  @override
  Future<SaveFileOutcome> saveAs({
    required String sourcePath,
    required String fileName,
    String? dialogTitle,
  }) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _saveViaAndroidChannel(sourcePath: sourcePath, fileName: fileName);
    }
    return _saveViaDialogPath(
      sourcePath: sourcePath,
      fileName: fileName,
      dialogTitle: dialogTitle,
    );
  }

  Future<SaveFileOutcome> _saveViaAndroidChannel({
    required String sourcePath,
    required String fileName,
  }) async {
    try {
      final saved = await saveFileChannel.invokeMethod<bool>('saveTo', {
        'sourcePath': sourcePath,
        'fileName': fileName,
      });
      if (saved == null) return SaveFileOutcome.failed;
      return saved ? SaveFileOutcome.saved : SaveFileOutcome.canceled;
    } on PlatformException catch (e) {
      debugPrint('save-to native call failed: ${e.code} ${e.message}');
      return SaveFileOutcome.failed;
    } on MissingPluginException {
      return SaveFileOutcome.failed;
    }
  }

  Future<SaveFileOutcome> _saveViaDialogPath({
    required String sourcePath,
    required String fileName,
    String? dialogTitle,
  }) async {
    try {
      // No `bytes:` on purpose -- desktop implementations return the
      // chosen path and the copy below streams from disk to disk.
      final destination = await FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
      );
      if (destination == null) return SaveFileOutcome.canceled;
      final sink = File(destination).openWrite();
      try {
        await sink.addStream(File(sourcePath).openRead());
      } finally {
        await sink.close();
      }
      return SaveFileOutcome.saved;
    } catch (e) {
      debugPrint('save-to copy failed: $e');
      return SaveFileOutcome.failed;
    }
  }
}
