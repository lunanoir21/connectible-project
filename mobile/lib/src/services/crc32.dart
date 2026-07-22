/// Standard CRC32 (IEEE 802.3, reflected) matching Rust's `crc32fast`,
/// used for per-chunk checksums in file transfer so the daemon's
/// verification (daemon/src/transfer) accepts our chunks.
class Crc32 {
  static final List<int> _table = _makeTable();

  static List<int> _makeTable() {
    final table = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }

  static int compute(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc = _table[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
