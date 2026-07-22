/// Strips any directory components a peer might embed in a file name, so
/// a received file is always written *inside* the received/ directory and
/// can never escape it (path traversal). Also rejects the bare "." and
/// ".." segments, which name a directory rather than a file and would
/// otherwise resolve to the received/ dir or its parent.
String safeReceivedFileName(String name) {
  final base = name.split(RegExp(r'[\\/]')).last.trim();
  if (base.isEmpty || base == '.' || base == '..') return 'received_file';
  return base;
}

/// Destination file name for the *in-progress* (not yet verified) bytes of
/// an incoming transfer, keyed by `transfer_id` rather than the peer-
/// supplied file name (T-108). Two concurrent or sequential transfers that
/// happen to share a file name would otherwise both write to the same
/// path and corrupt each other; keying by transfer_id keeps every
/// in-flight transfer's bytes in its own file. A resumed transfer reuses
/// the same transfer_id and therefore the same partial file, preserving
/// the existing resume-by-append behavior.
String partialFileName(String transferId) {
  final safeId = transferId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  final base = safeId.isEmpty ? 'unknown' : safeId;
  return '.incoming-$base.part';
}

/// Given the file names already present in the destination directory,
/// returns a collision-free variant of [desiredName]: the name itself if
/// it is not already taken, otherwise "name (1).ext", "name (2).ext", and
/// so on. Used once a transfer completes and is hash-verified, to rename
/// its partial file to a final, user-visible name that cannot silently
/// overwrite an existing file.
String uniqueFileName(Iterable<String> existingNames, String desiredName) {
  final existing = existingNames.toSet();
  if (!existing.contains(desiredName)) return desiredName;

  final dot = desiredName.lastIndexOf('.');
  final hasExt = dot > 0;
  final stem = hasExt ? desiredName.substring(0, dot) : desiredName;
  final ext = hasExt ? desiredName.substring(dot) : '';

  var n = 1;
  while (true) {
    final candidate = '$stem ($n)$ext';
    if (!existing.contains(candidate)) return candidate;
    n++;
  }
}
