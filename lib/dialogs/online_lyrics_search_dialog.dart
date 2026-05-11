import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../player/lyrics_service.dart';
import '../widgets/query_condition_chip.dart';

typedef OnlineLyricsSearch =
    Future<List<LyricTrack>> Function({
      required String title,
      String? artist,
      String? album,
    });

Future<LyricTrack?> showOnlineLyricsSearchDialog({
  required BuildContext context,
  required String queryTitle,
  required List<LyricTrack> tracks,
  required OnlineLyricsSearch searchTracks,
  String? queryArtist,
  String? queryAlbum,
}) {
  return showDialog<LyricTrack>(
    context: context,
    builder: (dialogContext) {
      return _OnlineLyricsSearchDialog(
        queryTitle: queryTitle,
        tracks: tracks,
        searchTracks: searchTracks,
        queryArtist: queryArtist,
        queryAlbum: queryAlbum,
      );
    },
  );
}

enum _OnlineLyricsCondition { artist, album }

class _OnlineLyricsSearchDialog extends StatefulWidget {
  const _OnlineLyricsSearchDialog({
    required this.queryTitle,
    required this.tracks,
    required this.searchTracks,
    this.queryArtist,
    this.queryAlbum,
  });

  final String queryTitle;
  final List<LyricTrack> tracks;
  final OnlineLyricsSearch searchTracks;
  final String? queryArtist;
  final String? queryAlbum;

  @override
  State<_OnlineLyricsSearchDialog> createState() =>
      _OnlineLyricsSearchDialogState();
}

class _OnlineLyricsSearchDialogState extends State<_OnlineLyricsSearchDialog> {
  final Map<_OnlineLyricsCondition, String> _editedConditionTexts =
      <_OnlineLyricsCondition, String>{};
  final Set<_OnlineLyricsCondition> _disabledConditions =
      <_OnlineLyricsCondition>{
        _OnlineLyricsCondition.artist,
        _OnlineLyricsCondition.album,
      };

  List<LyricTrack> _tracks = const [];
  bool _isLoading = false;
  String? _lastErrorMessage;

  @override
  void initState() {
    super.initState();
    _tracks = widget.tracks;
  }

  String _textOrDash(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? '-' : normalized;
  }

  String? _conditionSourceText(_OnlineLyricsCondition condition) {
    return switch (condition) {
      _OnlineLyricsCondition.artist => widget.queryArtist,
      _OnlineLyricsCondition.album => widget.queryAlbum,
    };
  }

  bool _isConditionEnabled(_OnlineLyricsCondition condition) {
    return !_disabledConditions.contains(condition);
  }

  String? _conditionText(_OnlineLyricsCondition condition) {
    final edited = _editedConditionTexts[condition];
    if (_hasMeaningfulText(edited)) return edited!.trim();
    return _conditionSourceText(condition);
  }

  bool _hasMeaningfulText(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    return trimmed.isNotEmpty;
  }

  Future<void> _toggleCondition(_OnlineLyricsCondition condition) async {
    if (!mounted) return;
    setState(() {
      if (_disabledConditions.contains(condition)) {
        _disabledConditions.remove(condition);
      } else {
        _disabledConditions.add(condition);
      }
    });

    await _reloadTracks();
  }

  Future<void> _editCondition(_OnlineLyricsCondition condition) async {
    final initialValue = _conditionText(condition) ?? '';
    final editedValue = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return _EditLyricsQueryConditionDialog(initialValue: initialValue);
      },
    );

    if (!mounted || editedValue == null) return;

    final trimmed = editedValue.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      final sourceValue = _conditionSourceText(condition)?.trim() ?? '';
      if (trimmed == sourceValue) {
        _editedConditionTexts.remove(condition);
      } else {
        _editedConditionTexts[condition] = trimmed;
      }
    });

    await _reloadTracks();
  }

  Future<void> _reloadTracks() async {
    if (!mounted) return;

    final artist = _isConditionEnabled(_OnlineLyricsCondition.artist)
        ? _conditionText(_OnlineLyricsCondition.artist)
        : null;
    final album = _isConditionEnabled(_OnlineLyricsCondition.album)
        ? _conditionText(_OnlineLyricsCondition.album)
        : null;

    setState(() {
      _isLoading = true;
      _lastErrorMessage = null;
    });

    try {
      final tracks = await widget.searchTracks(
        title: widget.queryTitle,
        artist: artist,
        album: album,
      );

      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _lastErrorMessage = error.toString();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_lastErrorMessage!)));
    }
  }

  String _conditionValue(_OnlineLyricsCondition condition) {
    final value = _conditionText(condition);
    return _textOrDash(value);
  }

  Widget _buildConditionChips(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chips = <Widget>[
      QueryConditionChip(
        label: '艺术家',
        value: _conditionValue(_OnlineLyricsCondition.artist),
        enabled: _isConditionEnabled(_OnlineLyricsCondition.artist),
        onTap: () => _toggleCondition(_OnlineLyricsCondition.artist),
        onEdit: () => _editCondition(_OnlineLyricsCondition.artist),
        editTooltip: l10n.editQueryCondition,
      ),
      QueryConditionChip(
        label: '专辑',
        value: _conditionValue(_OnlineLyricsCondition.album),
        enabled: _isConditionEnabled(_OnlineLyricsCondition.album),
        onTap: () => _toggleCondition(_OnlineLyricsCondition.album),
        onEdit: () => _editCondition(_OnlineLyricsCondition.album),
        editTooltip: l10n.editQueryCondition,
      ),
    ];

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogWidth = MediaQuery.sizeOf(
      context,
    ).width.clamp(320.0, 780.0).toDouble();
    final listHeight = (MediaQuery.sizeOf(context).height * 0.48)
        .clamp(220.0, 480.0)
        .toDouble();
    final conditionChips = _buildConditionChips(context);

    return AlertDialog(
      title: const Text('在线歌词结果'),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.queryTitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoading ? null : _reloadTracks,
                  icon: _isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded),
                  tooltip: '重新查询',
                ),
              ],
            ),
            const SizedBox(height: 10),
            conditionChips,
            const SizedBox(height: 12),
            SizedBox(
              height: listHeight,
              child: _tracks.isEmpty && !_isLoading
                  ? Center(
                      child: Text(
                        _lastErrorMessage?.trim().isNotEmpty == true
                            ? _lastErrorMessage!
                            : '无结果',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _tracks.length,
                      separatorBuilder: (context, separatorIndex) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final track = _tracks[index];
                        return Material(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.36),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.of(context).pop(track),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                10,
                                12,
                              ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          track.displayTitle.isNotEmpty
                                              ? track.displayTitle
                                              : '未命名歌词',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '时长：${_formatDuration(track.duration)}',
                                        ),
                                        Text(
                                          '专辑：${_textOrDash(track.albumName)}',
                                        ),
                                        Text(
                                          '艺术家：${_textOrDash(track.artistName)}',
                                        ),
                                        Text(
                                          track.hasSyncedLyrics
                                              ? '带时间轴：是'
                                              : '带时间轴：否',
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

class _EditLyricsQueryConditionDialog extends StatefulWidget {
  const _EditLyricsQueryConditionDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_EditLyricsQueryConditionDialog> createState() =>
      _EditLyricsQueryConditionDialogState();
}

class _EditLyricsQueryConditionDialogState
    extends State<_EditLyricsQueryConditionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentValue = _controller.text;
    final canSave = currentValue.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('编辑查询条件'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '内容',
            alignLabelWithHint: true,
          ),
          onChanged: (_) {
            setState(() {});
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: canSave
              ? () => Navigator.of(context).pop(currentValue.trim())
              : null,
          child: const Text('确认'),
        ),
      ],
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
