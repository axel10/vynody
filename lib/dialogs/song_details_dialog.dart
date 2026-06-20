import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_core/audio_core.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

Future<void> showSongDetailsDialog(BuildContext context, MusicFile song) async {
  await showDialog(
    context: context,
    builder: (dialogContext) {
      return _SongDetailsDialog(song: song);
    },
  );
}

class _SongDetailsDialog extends ConsumerStatefulWidget {
  const _SongDetailsDialog({required this.song});

  final MusicFile song;

  @override
  ConsumerState<_SongDetailsDialog> createState() => _SongDetailsDialogState();
}

class _SongDetailsDialogState extends ConsumerState<_SongDetailsDialog> {
  late final Future<AudioDetails> _detailsFuture;

  @override
  void initState() {
    super.initState();
    final audioService = ref.read(audioServiceProvider);
    _detailsFuture = audioService.getAudioDetails(path: widget.song.path);
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatChannels(int channels, bool isZh) {
    if (channels == 1) {
      return isZh ? '单声道 (Mono)' : 'Mono';
    } else if (channels == 2) {
      return isZh ? '立体声 (Stereo)' : 'Stereo';
    }
    return isZh ? '$channels 声道' : '$channels Channels';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final titleText = isZh ? '歌曲属性' : 'Song Properties';
    final closeText = isZh ? '关闭' : 'Close';

    return AlertDialog(
      title: Text(titleText),
      content: SizedBox(
        width: 480,
        child: FutureBuilder<AudioDetails>(
          future: _detailsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.hasError) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: theme.colorScheme.error,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isZh ? '无法获取详细信息' : 'Failed to load details',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final details = snapshot.data;
            if (details == null) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    isZh ? '暂无歌曲详细属性' : 'No properties available',
                  ),
                ),
              );
            }

            final rows = [
              _DetailRow(
                label: isZh ? '文件路径' : 'File Path',
                value: widget.song.path,
                selectable: true,
              ),
              _DetailRow(
                label: isZh ? '格式' : 'Format',
                value: details.formatName.toUpperCase(),
              ),
              _DetailRow(
                label: isZh ? '编码' : 'Codec',
                value: details.codecName.toUpperCase(),
              ),
              _DetailRow(
                label: isZh ? '时长' : 'Duration',
                value: _formatDuration(details.duration),
              ),
              _DetailRow(
                label: isZh ? '文件大小' : 'File Size',
                value: _formatFileSize(details.fileSize),
              ),
              _DetailRow(
                label: isZh ? '比特率' : 'Bitrate',
                value: '${(details.bitrate / 1000).round()} kbps',
              ),
              if (details.bitrateMode.isNotEmpty && details.bitrateMode != 'unknown')
                _DetailRow(
                  label: isZh ? '码率模式' : 'Bitrate Mode',
                  value: details.bitrateMode.toUpperCase(),
                ),
              _DetailRow(
                label: isZh ? '采样率' : 'Sample Rate',
                value: '${details.sampleRate} Hz',
              ),
              _DetailRow(
                label: isZh ? '声道数' : 'Channels',
                value: _formatChannels(details.channels, isZh),
              ),
              if (details.bitDepth != null && details.bitDepth! > 0)
                _DetailRow(
                  label: isZh ? '采样深度' : 'Bit Depth',
                  value: '${details.bitDepth} bit',
                ),
            ];

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Song info header card
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: SongThumbnail(
                            path: widget.song.path,
                            id: widget.song.id,
                            size: 64,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.song.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.song.artist ?? (isZh ? '未知艺术家' : 'Unknown Artist'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.song.album ?? (isZh ? '未知专辑' : 'Unknown Album'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  // Attributes table
                  ...rows,
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(closeText),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: selectable
                ? SelectableText(
                    value,
                    style: theme.textTheme.bodyMedium,
                  )
                : Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
