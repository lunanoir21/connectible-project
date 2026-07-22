import 'package:connectible_mobile/src/services/file_util.dart';
import 'package:flutter_test/flutter_test.dart';

// A received file's name comes from a remote peer, so it is untrusted:
// it must never be able to escape the received/ directory.
void main() {
  group('safeReceivedFileName', () {
    test('keeps a plain name', () {
      expect(safeReceivedFileName('photo.jpg'), 'photo.jpg');
    });

    test('strips POSIX path traversal', () {
      expect(safeReceivedFileName('../../etc/passwd'), 'passwd');
      expect(safeReceivedFileName('a/b/c.txt'), 'c.txt');
    });

    test('strips Windows-style separators', () {
      expect(safeReceivedFileName(r'dir\sub\file.bin'), 'file.bin');
      expect(safeReceivedFileName(r'..\..\secret'), 'secret');
    });

    test('rejects bare dot segments that name a directory', () {
      expect(safeReceivedFileName('..'), 'received_file');
      expect(safeReceivedFileName('.'), 'received_file');
      expect(safeReceivedFileName('foo/..'), 'received_file');
    });

    test('falls back when nothing usable remains', () {
      expect(safeReceivedFileName(''), 'received_file');
      expect(safeReceivedFileName('///'), 'received_file');
      expect(safeReceivedFileName('   '), 'received_file');
    });

    test('trims surrounding whitespace', () {
      expect(safeReceivedFileName('  spaced.txt  '), 'spaced.txt');
    });
  });

  // T-108: two incoming transfers that happen to share a file name must
  // not be able to collide, either while in flight (partialFileName is
  // keyed by transfer_id) or once finalized (uniqueFileName disambiguates
  // against what's already on disk).
  group('partialFileName', () {
    test('is unique per transfer_id even for the same eventual file name',
        () {
      final a = partialFileName('transfer-aaa');
      final b = partialFileName('transfer-bbb');
      expect(a, isNot(equals(b)));
    });

    test('sanitizes characters outside the safe set', () {
      expect(partialFileName('../../etc/passwd'),
          '.incoming-.._.._etc_passwd.part');
    });

    test('falls back to a stable name for an empty transfer_id', () {
      expect(partialFileName(''), '.incoming-unknown.part');
    });
  });

  group('uniqueFileName', () {
    test('returns the desired name when nothing collides', () {
      expect(uniqueFileName(const {'other.txt'}, 'photo.jpg'), 'photo.jpg');
    });

    test('appends a counter suffix on collision, preserving the extension',
        () {
      expect(uniqueFileName(const {'photo.jpg'}, 'photo.jpg'),
          'photo (1).jpg');
    });

    test('keeps incrementing past multiple prior collisions', () {
      final existing = {'photo.jpg', 'photo (1).jpg', 'photo (2).jpg'};
      expect(uniqueFileName(existing, 'photo.jpg'), 'photo (3).jpg');
    });

    test('handles a name with no extension', () {
      expect(uniqueFileName(const {'README'}, 'README'), 'README (1)');
    });
  });
}
