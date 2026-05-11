import 'package:flutter/material.dart';

import '../player/lyrics_service.dart';

Future<LyricTrack?> showOnlineLyricsSearchDialog({
  required BuildContext context,
  required String queryTitle,
  required List<LyricTrack> tracks,
}) {
  return showDialog<LyricTrack>(
    context: context,
    builder: (dialogContext) {
      return _OnlineLyricsSearchDialog(queryTitle: queryTitle, tracks: tracks);
    },
  );
}

class _OnlineLyricsSearchDialog extends StatelessWidget {
  const _OnlineLyricsSearchDialog({
    required this.queryTitle,
    required this.tracks,
  });

  final String queryTitle;
  final List<LyricTrack> tracks;

  String _formatDuration(double? seconds) {
    if (seconds == null ||
        seconds.isNaN ||
        seconds.isInfinite ||
        seconds <= 0) {
      return '-';
    }

    final safeSeconds = seconds.round();
    final minutes = safeSeconds ~/ 60;
    final remainingSeconds = safeSeconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _textOrDash(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? '-' : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogWidth = MediaQuery.sizeOf(
      context,
    ).width.clamp(320.0, 780.0).toDouble();
    final listHeight = (MediaQuery.sizeOf(context).height * 0.55)
        .clamp(240.0, 520.0)
        .toDouble();

    return AlertDialog(
      title: const Text('在线歌词结果'),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              queryTitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: listHeight,
              child: ListView.separated(
                itemCount: tracks.length,
                separatorBuilder: (context, separatorIndex) =>
                    const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return Material(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.36,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).pop(track),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              child: Text('${index + 1}'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.displayTitle.isNotEmpty
                                        ? track.displayTitle
                                        : '未命名歌词',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Text('时长：${_formatDuration(track.duration)}'),
                                  Text('专辑：${_textOrDash(track.albumName)}'),
                                  Text('艺术家：${_textOrDash(track.artistName)}'),
                                  Text(
                                    track.hasSyncedLyrics ? '带时间轴：是' : '带时间轴：否',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: '查看歌词详情',
                              onPressed: () {
                                _showLyricsDetailDialog(context, track);
                              },
                              icon: const Icon(Icons.info_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _showLyricsDetailDialog(
    BuildContext context,
    LyricTrack track,
  ) async {
    final lyricsText = track.syncedLyrics?.trim().isNotEmpty == true
        ? track.syncedLyrics!.trim()
        : track.plainLyrics?.trim() ?? '';

    await showDialog<void>(
      context: context,
      builder: (detailContext) {
        final theme = Theme.of(detailContext);
        return AlertDialog(
          title: Text(
            track.displayTitle.isNotEmpty ? track.displayTitle : '歌词详情',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DetailLine(
                    label: '时长',
                    value: _formatDuration(track.duration),
                  ),
                  _DetailLine(label: '专辑', value: _textOrDash(track.albumName)),
                  _DetailLine(
                    label: '艺术家',
                    value: _textOrDash(track.artistName),
                  ),
                  _DetailLine(
                    label: '带时间轴',
                    value: track.hasSyncedLyrics ? '是' : '否',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '歌词内容',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    lyricsText.isEmpty ? '无歌词内容' : lyricsText,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(detailContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label：',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
