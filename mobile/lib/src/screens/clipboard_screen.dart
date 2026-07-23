import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:super_clipboard/super_clipboard.dart' as sc;

import '../models/models.dart';
import '../state/clipboard_model.dart';
import '../state/pairing_model.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

String _formatBytes(int b) {
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

/// Copies an entry back to the OS clipboard (Phase L, T-L7): images go
/// through `super_clipboard` (flutter/services.dart's `Clipboard` is
/// text-only), text through the existing platform channel.
Future<void> _copyBack(ClipboardEntry entry) async {
  if (entry.oversized) return;
  if (entry.isImage) {
    final bytes = entry.imageBytes;
    if (bytes == null) return;
    final clipboard = sc.SystemClipboard.instance;
    if (clipboard == null) return;
    final item = sc.DataWriterItem();
    item.add(sc.Formats.png(bytes));
    await clipboard.write([item]);
  } else {
    await Clipboard.setData(ClipboardData(text: entry.content));
  }
}

class ClipboardScreen extends StatelessWidget {
  const ClipboardScreen({super.key});

  Future<void> _sendCurrent(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isNotEmpty && context.mounted) {
      await context.read<ClipboardModel>().sendClipboard(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final model = context.watch<ClipboardModel>();
    final connected = context.watch<PairingModel>().connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              const Spacer(),
              FilledButton.icon(
                onPressed: connected ? () => _sendCurrent(context) : null,
                icon: const Icon(Icons.north, size: 16),
                label: Text(s.t('clipboard.send')),
                style: FilledButton.styleFrom(
                  backgroundColor: p.paper,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: p.surfaceHover,
                  disabledForegroundColor: p.inkFaint,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: model.clipboard.isEmpty
              ? EmptyState(
                  icon: Icons.content_paste_outlined,
                  title: s.t('clipboard.emptyTitle'),
                  hint: s.t('clipboard.emptyHint'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: model.clipboard.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final entry = model.clipboard[i];
                    final local = entry.source == 'local';
                    return AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: entry.oversized
                                    ? Text(
                                        s.t('clipboard.oversized', {
                                          'size': _formatBytes(entry.byteSize),
                                        }),
                                        style: TextStyle(
                                            fontSize: 13, color: p.inkFaint),
                                      )
                                    : entry.isImage
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            child: Image.memory(
                                              entry.imageBytes!,
                                              height: 96,
                                              fit: BoxFit.contain,
                                              alignment: Alignment.centerLeft,
                                            ),
                                          )
                                        : Text(entry.content,
                                            maxLines: 4,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 13,
                                                height: 1.4,
                                                color: p.ink,
                                                fontFamily: 'monospace')),
                              ),
                              if (!entry.oversized)
                                IconButton(
                                  icon: Icon(Icons.copy_outlined,
                                      size: 18, color: p.inkMuted),
                                  tooltip: s.t('clipboard.copy'),
                                  onPressed: () => _copyBack(entry),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                      color: local ? p.inkGhost : p.paper,
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Text(
                                  local
                                      ? s.t('status.thisDevice')
                                      : s.t('clipboard.remoteSource'),
                                  style: TextStyle(
                                      fontSize: 11, color: p.inkFaint)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
