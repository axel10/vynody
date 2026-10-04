import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/utils/localized_text.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import '../widgets/app_bottom_sheet.dart';

AppLocalizations _l10n() => currentAppL10n;

typedef OnlineLyricsSearch =
    Future<List<LyricTrack>> Function({
      required String title,
      String? artist,
      String? album,
      String? q,
      CancelToken? cancelToken,
    });

Future<LyricTrack?> showOnlineLyricsSearchDialog({
  required BuildContext context,
  required String queryTitle,
  required LyricsService lyricsService,
  required OnlineLyricsSearch searchTracks,
  String? queryArtist,
  String? queryAlbum,
  Duration? queryDuration,
}) {
  return showAppAdaptiveModal<LyricTrack>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) {
      return _OnlineLyricsSearchDialog(
        queryTitle: queryTitle,
        lyricsService: lyricsService,
        searchTracks: searchTracks,
        queryArtist: queryArtist,
        queryAlbum: queryAlbum,
        queryDuration: queryDuration,
      );
    },
  );
}

class _OnlineLyricsSearchDialog extends StatefulWidget {
  const _OnlineLyricsSearchDialog({
    required this.queryTitle,
    required this.lyricsService,
    required this.searchTracks,
    this.queryArtist,
    this.queryAlbum,
    this.queryDuration,
  });

  final String queryTitle;
  final LyricsService lyricsService;
  final OnlineLyricsSearch searchTracks;
  final String? queryArtist;
  final String? queryAlbum;
  final Duration? queryDuration;

  @override
  State<_OnlineLyricsSearchDialog> createState() =>
      _OnlineLyricsSearchDialogState();
}

class _OnlineLyricsSearchDialogState extends State<_OnlineLyricsSearchDialog> {
  late final TextEditingController _searchController;
  List<ScoredLyricTrack> _tracks = const [];
  bool _isLoading = false;
  String? _lastErrorMessage;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    
    // Construct initial search query using only the track title (or filename without extension if no title is present)
    final initialQ = widget.queryTitle.trim();
    _searchController = TextEditingController(text: initialQ);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadTracks();
    });
  }

  @override
  void dispose() {
    _cancelToken?.cancel('Dialog disposed');
    _searchController.dispose();
    super.dispose();
  }

  String _textOrDash(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? '-' : normalized;
  }

  bool _isNetworkError(Object error) {
    if (error is! DioException) {
      final errStr = error.toString().toLowerCase();
      return errStr.contains('socketexception') ||
             errStr.contains('network') ||
             errStr.contains('connection');
    }
    final e = error;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    if (e.error is SocketException) {
      return true;
    }
    final text = [
      e.message,
      e.error?.toString(),
    ].whereType<String>().join(' ').toLowerCase();

    return text.contains('connection failed') ||
        text.contains('network is unreachable') ||
        text.contains('failed host lookup') ||
        text.contains('no address associated with hostname') ||
        text.contains('software caused connection abort') ||
        text.contains('connection refused') ||
        text.contains('os error: 101') ||
        text.contains('os error: 113') ||
        text.contains('socketexception');
  }

  Future<void> _reloadTracks() async {
    if (!mounted) return;

    final queryText = _searchController.text.trim();

    // Cancel the previous query if it is still in flight
    _cancelToken?.cancel('New query initiated');
    final currentCancelToken = CancelToken();
    _cancelToken = currentCancelToken;

    setState(() {
      _isLoading = true;
      _lastErrorMessage = null;
    });

    try {
      final tracks = await widget.searchTracks(
        title: widget.queryTitle,
        q: queryText.isNotEmpty ? queryText : null,
        cancelToken: currentCancelToken,
      );

      if (!mounted) return;
      if (currentCancelToken != _cancelToken) return;

      final scoredTracks = widget.lyricsService.scoreAndSortTracks(
        tracks: tracks,
        queryTitle: widget.queryTitle,
        queryArtist: widget.queryArtist,
        queryAlbum: widget.queryAlbum,
        queryDuration: widget.queryDuration,
      );

      setState(() {
        _tracks = scoredTracks;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (currentCancelToken != _cancelToken) return;

      if (error is DioException && CancelToken.isCancel(error)) {
        return;
      }

      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _isLoading = false;
        if (_isNetworkError(error)) {
          _lastErrorMessage = l10n.networkConnectionFailed;
        } else {
          _lastErrorMessage = error.toString();
        }
      });
      AppSnackBar.show(
        context,
        null,
        SnackBar(content: Text(_lastErrorMessage!)),
      );
    }
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

  Widget _buildMatchScoreBadge(double score, ThemeData theme) {
    final color = score >= 80
        ? Colors.green
        : score >= 60
            ? Colors.orange
            : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 1),
      ),
      child: Text(
        '${_l10n().matchScore} ${score.toStringAsFixed(0)}%',
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, AppLocalizations l10n) {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _reloadTracks(),
      decoration: InputDecoration(
        hintText: l10n.searchLyricsPlaceholder,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchController,
          builder: (context, value, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                    },
                  ),
                IconButton(
                  onPressed: _isLoading ? null : _reloadTracks,
                  icon: const Icon(Icons.send_rounded),
                  tooltip: l10n.requery,
                ),
              ],
            );
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final Widget content;
    if (_isLoading) {
      content = Center(
        child: CircularProgressIndicator(
          color: theme.colorScheme.primary,
        ),
      );
    } else if (_tracks.isEmpty) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Text(
            _lastErrorMessage?.trim().isNotEmpty == true
                ? _lastErrorMessage!
                : l10n.noMatchingResults,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else {
      content = ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: _tracks.length,
        separatorBuilder: (context, separatorIndex) =>
            const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final scoredTrack = _tracks[index];
          final track = scoredTrack.track;
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  track.displayTitle.isNotEmpty
                                      ? track.displayTitle
                                      : l10n.untitledLyrics,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildMatchScoreBadge(scoredTrack.score, theme),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${l10n.durationLabel}：${_formatDuration(track.duration)}',
                          ),
                          Text(
                            '${l10n.albumLabel}：${_textOrDash(track.albumName)}',
                          ),
                          Text(
                            '${l10n.artistLabel}：${_textOrDash(track.artistName)}',
                          ),
                          Text(
                            track.hasSyncedLyrics
                                ? '${l10n.hasTimeline}：${l10n.yes}'
                                : '${l10n.hasTimeline}：${l10n.no}',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: l10n.viewLyricsDetails,
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
      );
    }

    return AppAdaptiveSheet(
      title: l10n.onlineLyricsResults,
      sheetMaxWidth: 720,
      dialogMaxWidth: 680,
      dialogHeight: 580,
      expandHeight: true,
      padding: EdgeInsets.fromLTRB(24, 8, 24, bottomInset),
      headerBottom: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _buildSearchBar(context, l10n),
      ),
      child: content,
    );
  }

  Future<void> _showLyricsDetailDialog(
    BuildContext context,
    LyricTrack track,
  ) async {
    final lyricsText = track.syncedLyrics?.trim().isNotEmpty == true
        ? track.syncedLyrics!.trim()
        : track.plainLyrics?.trim() ?? '';
    final l10n = AppLocalizations.of(context)!;

    await showAppAdaptiveModal<void>(
      context: context,
      useRootNavigator: true,
      builder: (detailContext) {
        final theme = Theme.of(detailContext);
        return AppAdaptiveSheet(
          title: track.displayTitle.isNotEmpty
              ? track.displayTitle
              : l10n.lyricsDetails,
          dialogMaxWidth: 640,
          sheetMaxWidth: 720,
          dialogHeight: 520,
          expandHeight: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailLine(
                  label: l10n.durationLabel,
                  value: _formatDuration(track.duration),
                ),
                _DetailLine(
                  label: l10n.albumLabel,
                  value: _textOrDash(track.albumName),
                ),
                _DetailLine(
                  label: l10n.artistLabel,
                  value: _textOrDash(track.artistName),
                ),
                _DetailLine(
                  label: l10n.hasTimeline,
                  value: track.hasSyncedLyrics ? l10n.yes : l10n.no,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.lyricsContent,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  lyricsText.isEmpty ? l10n.noLyricsContent : lyricsText,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                ),
              ],
            ),
          ),
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
