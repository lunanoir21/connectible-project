import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/save_file_service.dart';
import '../state/file_transfer_model.dart';
import '../state/pairing_model.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Transfers screen, rebuilt: a send composer that reflects who a file
/// will go to, live incoming/outgoing rows drawn as constellation-style
/// "ties" (an endpoint star per device) split into in-progress and
/// history, and a "Save to..." that copies a received file out of the
/// app-private inbox to a user-chosen location via the system picker.
class TransfersScreen extends StatelessWidget {
  const TransfersScreen(
      {super.key, this.saveFileService = const PlatformSaveFileService()});

  /// "Save to..." backend, injectable so widget tests can fake it;
  /// production streams through the platform implementation (T-X6).
  final SaveFileService saveFileService;

  Future<void> _pickAndSend(BuildContext context) async {
    final result = await FilePicker.pickFiles();
    final path = result?.files.single.path;
    if (path != null && context.mounted) {
      await context.read<FileTransferModel>().sendFile(path);
    }
  }

  /// Copies a completed incoming file out of the app-private received/
  /// directory to a user-chosen location via the OS document picker
  /// ("Save to..."). Received files otherwise land where the file
  /// manager can't reach them; this is how the user gets them out.
  /// The copy streams with a bounded buffer (T-X6) -- the receive path
  /// is deliberately constant-memory, and this exit path now is too.
  Future<void> _saveTo(
      BuildContext context, FileTransferModel model, TransferProgress t) async {
    final s = context.strings;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final path = model.incomingFilePath(t.transferId);
    if (path == null || !await File(path).exists()) {
      messenger?.showSnackBar(
          SnackBar(content: Text(s.t('transfers.saveUnavailable'))));
      return;
    }
    final outcome = await saveFileService.saveAs(
      sourcePath: path,
      fileName: t.fileName,
      dialogTitle: s.t('transfers.saveTo'),
    );
    switch (outcome) {
      case SaveFileOutcome.saved:
        messenger
            ?.showSnackBar(SnackBar(content: Text(s.t('transfers.saved'))));
      case SaveFileOutcome.canceled:
        break; // user backed out of the picker; nothing to report
      case SaveFileOutcome.failed:
        messenger?.showSnackBar(
            SnackBar(content: Text(s.t('transfers.saveFailed'))));
    }
  }

  String _bytes(int b) {
    if (b < 1024) return '$b B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var v = b / 1024;
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${units[i]}';
  }

  String _statusLabel(AppStrings s, TransferProgress t) {
    if (t.canceled) return s.t('transfers.canceled');
    if (t.failed) return s.t('transfers.failed');
    if (t.completed) return s.t('transfers.completed');
    return t.direction == TransferDirection.outgoing
        ? s.t('transfers.sending')
        : s.t('transfers.receiving');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final model = context.watch<FileTransferModel>();
    final pairing = context.watch<PairingModel>();
    final connected = pairing.connected;

    final rows = model.transfers.values.toList().reversed.toList();
    final active = rows.where((t) => t.active).toList();
    final liveHistory = rows.where((t) => !t.active).toList();

    // Phase J: merge in persisted history (survives an app restart,
    // unlike `model.transfers` which is purely in-memory) -- a
    // transferId present in both means it just finished this session,
    // so the live row (richer progress detail) wins.
    final liveHistoryIds = liveHistory.map((t) => t.transferId).toSet();
    final persistedRows = model.history
        .where((h) => !liveHistoryIds.contains(h.transferId))
        .map(_historyEntryToProgress);
    final history = [...liveHistory, ...persistedRows];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: _SendComposer(
            connected: connected,
            peerName: pairing.activePeerName,
            onSend: connected ? () => _pickAndSend(context) : null,
          ),
        ),
        Expanded(
          child: active.isEmpty && history.isEmpty
              ? EmptyState(
                  icon: Icons.swap_vert,
                  title: s.t('transfers.emptyTitle'),
                  hint: s.t('transfers.emptyHint'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    if (active.isNotEmpty) ...[
                      Eyebrow(s.t('transfers.sectionActive')),
                      const SizedBox(height: 10),
                      for (final t in active) ...[
                        _TransferTile(
                          t: t,
                          statusLabel: _statusLabel(s, t),
                          bytesLabel: _bytesLine(t),
                          onCancel: () => model.cancelTransfer(t.transferId),
                          onSaveTo: null,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                    if (history.isNotEmpty) ...[
                      if (active.isNotEmpty) const SizedBox(height: 6),
                      Eyebrow(s.t('transfers.sectionHistory')),
                      const SizedBox(height: 10),
                      for (final t in history) ...[
                        _TransferTile(
                          t: t,
                          statusLabel: _statusLabel(s, t),
                          bytesLabel: _bytesLine(t),
                          onCancel: null,
                          onSaveTo: (!t.completed ||
                                  t.direction == TransferDirection.outgoing)
                              ? null
                              : () => _saveTo(context, model, t),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  String _bytesLine(TransferProgress t) =>
      '${_bytes(t.bytesTransferred)}${t.totalBytes > 0 ? ' / ${_bytes(t.totalBytes)}' : ''}';

  /// Adapts a persisted (Phase J) history entry to the `TransferProgress`
  /// shape `_TransferTile` already knows how to render. Terminal by
  /// construction, so `bytesTransferred` is approximated as `totalBytes`.
  TransferProgress _historyEntryToProgress(TransferHistoryEntry h) {
    return TransferProgress(
      transferId: h.transferId,
      fileName: h.fileName,
      bytesTransferred: h.totalBytes,
      totalBytes: h.totalBytes,
      direction: h.direction,
      completed: h.status == 'completed',
      failed: h.status == 'failed' || h.status == 'canceled',
      canceled: h.status == 'canceled',
    );
  }
}

/// Compact "who am I sending to" card with the single primary Send
/// action. Disabled and explanatory when nothing is connected.
class _SendComposer extends StatelessWidget {
  const _SendComposer({
    required this.connected,
    required this.peerName,
    required this.onSend,
  });

  final bool connected;
  final String? peerName;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final name = peerName ?? s.t('transfers.aDevice');
    final hint = connected
        ? s.t('transfers.sendHint', {'name': name})
        : s.t('transfers.notConnectedHint');
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: p.surfaceOverlay,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.line),
            ),
            child: Icon(Icons.upload_file_outlined,
                size: 20, color: connected ? p.ink : p.inkFaint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hint,
              style: TextStyle(fontSize: 12, height: 1.4, color: p.inkMuted),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onSend,
            icon: const Icon(Icons.north, size: 15),
            label: Text(s.t('transfers.sendFile')),
            style: FilledButton.styleFrom(
              backgroundColor: p.paper,
              foregroundColor: Colors.black,
              disabledBackgroundColor: p.surfaceHover,
              disabledForegroundColor: p.inkFaint,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One transfer, drawn as a tie between two endpoint stars with the
/// bright segment travelling along it.
class _TransferTile extends StatelessWidget {
  const _TransferTile({
    required this.t,
    required this.statusLabel,
    required this.bytesLabel,
    required this.onCancel,
    required this.onSaveTo,
  });

  final TransferProgress t;
  final String statusLabel;
  final String bytesLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onSaveTo;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final outgoing = t.direction == TransferDirection.outgoing;
    final done = t.completed && !t.failed;

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: done
                      ? Colors.white.withValues(alpha: 0.08)
                      : p.surfaceOverlay,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.line),
                ),
                child: Icon(outgoing ? Icons.north : Icons.south,
                    size: 18,
                    color: t.failed
                        ? p.danger
                        : (done ? p.ink : p.inkFaint)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: p.ink)),
                    Text('$statusLabel - $bytesLabel',
                        style: TextStyle(fontSize: 11, color: p.inkFaint)),
                  ],
                ),
              ),
              Text('${(t.fraction * 100).round()}%',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: p.inkMuted)),
              if (onCancel != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 18),
                  color: p.inkFaint,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: s.t('transfers.cancel'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _Tie(fraction: t.fraction, done: done, failed: t.failed),
          if (onSaveTo != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onSaveTo,
                icon: const Icon(Icons.save_alt_rounded, size: 16),
                label: Text(s.t('transfers.saveTo')),
                style: TextButton.styleFrom(
                  foregroundColor: p.ink,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Progress as a tie between two endpoint stars: the source star lit,
/// the bright segment growing along the line, and the destination star
/// lighting up on completion.
class _Tie extends StatelessWidget {
  const _Tie({required this.fraction, required this.done, required this.failed});

  final double fraction;
  final bool done;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        _Star(filled: true, color: p.paper),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor:
                  AlwaysStoppedAnimation(failed ? p.danger : p.paper),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Star(
          filled: done,
          color: failed ? p.danger : p.paper,
          borderColor: p.line,
        ),
      ],
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.filled, required this.color, this.borderColor});

  final bool filled;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(
            color: filled ? color : (borderColor ?? color), width: 1.2),
      ),
    );
  }
}
