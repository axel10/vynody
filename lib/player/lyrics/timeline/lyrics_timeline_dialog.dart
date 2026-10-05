import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_bottom_sheet.dart';
import 'lyrics_timeline_entry.dart';
import 'lyrics_timeline_repository.dart';
import 'lyrics_timeline_service.dart';

Future<LyricsTimelineEntry?> showLyricsTimelineDialog(
  BuildContext context, {
  required String cacheKey,
  required String currentLyrics,
  int currentOffsetMillis = 0,
}) async {
  return showAppAdaptiveModal<LyricsTimelineEntry?>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) {
      return _LyricsTimelineModal(
        cacheKey: cacheKey,
        currentLyrics: currentLyrics,
        currentOffsetMillis: currentOffsetMillis,
      );
    },
  );
}

class _LyricsTimelineModal extends ConsumerStatefulWidget {
  const _LyricsTimelineModal({
    required this.cacheKey,
    required this.currentLyrics,
    required this.currentOffsetMillis,
  });

  final String cacheKey;
  final String currentLyrics;
  final int currentOffsetMillis;

  @override
  ConsumerState<_LyricsTimelineModal> createState() =>
      _LyricsTimelineModalState();
}

class _LyricsTimelineModalState extends ConsumerState<_LyricsTimelineModal> {
  List<LyricsTimelineEntry> _history = [];
  bool _isLoading = true;
  LyricsTimelineEntry? _selectedEntry;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final service = ref.read(lyricsTimelineServiceProvider);
    final history = await service.getHistory(widget.cacheKey);
    if (!mounted) return;
    setState(() {
      _history = history;
      _isLoading = false;
      if (history.isNotEmpty) {
        _selectedEntry = history.first;
      }
    });
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) {
      return '< 1 min';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24 && now.day == time.day) {
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else {
      final month = time.month.toString().padLeft(2, '0');
      final day = time.day.toString().padLeft(2, '0');
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$month-$day $hour:$minute';
    }
  }

  String _getActionTitle(String actionType, AppLocalizations l10n) {
    switch (actionType) {
      case LyricsTimelineActionType.manualEdit:
        return l10n.timelineActionManualEdit;
      case LyricsTimelineActionType.timelineAdjust:
        return l10n.timelineActionTimelineAdjust;
      case LyricsTimelineActionType.onlineMatch:
        return l10n.timelineActionOnlineMatch;
      case LyricsTimelineActionType.importFile:
        return l10n.timelineActionImportFile;
      case LyricsTimelineActionType.aiGenerate:
        return l10n.timelineActionAiGenerate;
      case LyricsTimelineActionType.initial:
        return l10n.timelineActionInitial;
      case LyricsTimelineActionType.restore:
        return l10n.timelineActionRestore;
      default:
        return actionType;
    }
  }

  IconData _getActionIcon(String actionType) {
    switch (actionType) {
      case LyricsTimelineActionType.manualEdit:
        return Icons.edit_note_rounded;
      case LyricsTimelineActionType.timelineAdjust:
        return Icons.more_time_rounded;
      case LyricsTimelineActionType.onlineMatch:
        return Icons.cloud_download_rounded;
      case LyricsTimelineActionType.importFile:
        return Icons.file_upload_outlined;
      case LyricsTimelineActionType.aiGenerate:
        return Icons.auto_awesome_rounded;
      case LyricsTimelineActionType.initial:
        return Icons.flag_outlined;
      case LyricsTimelineActionType.restore:
        return Icons.replay_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  bool _isEntryCurrent(LyricsTimelineEntry entry) {
    return entry.lyrics.trim() == widget.currentLyrics.trim() &&
        entry.timelineOffsetMillis == widget.currentOffsetMillis;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final countSubtitle = _history.isNotEmpty
        ? ' (${_history.length}/${LyricsTimelineRepository.maxHistoryCount})'
        : '';

    return AppAdaptiveSheet(
      title: '${l10n.lyricsTimelineTitle}$countSubtitle',
      subtitle: l10n.lyricsTimelineSubtitle,
      dialogMaxWidth: 720,
      dialogHeight: 520,
      sheetMaxWidth: 720,
      expandHeight: true,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _history.isEmpty
              ? _buildEmptyState(l10n, theme)
              : _buildTimelineContent(l10n, theme),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noTimelineHistory,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noTimelineHistoryHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineContent(AppLocalizations l10n, ThemeData theme) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 270,
            child: _buildVersionList(l10n, theme),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildPreviewAndAction(l10n, theme),
          ),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: _buildVersionList(l10n, theme),
        ),
        const Divider(height: 16),
        Expanded(
          child: _buildPreviewAndAction(l10n, theme),
        ),
      ],
    );
  }

  Widget _buildVersionList(AppLocalizations l10n, ThemeData theme) {
    return ListView.separated(
      itemCount: _history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final entry = _history[index];
        final isSelected = entry == _selectedEntry;
        final isCurrent = _isEntryCurrent(entry);

        final title = _getActionTitle(entry.actionType, l10n);
        final timeStr = _formatTime(entry.createdAt);

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _selectedEntry = entry;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.5)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getActionIcon(entry.actionType),
                  size: 18,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: isSelected || isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                l10n.currentVersion,
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.description} • $timeStr',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPreviewAndAction(AppLocalizations l10n, ThemeData theme) {
    final entry = _selectedEntry;
    if (entry == null) {
      return const SizedBox.shrink();
    }

    final isCurrent = _isEntryCurrent(entry);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_getActionTitle(entry.actionType, l10n)} (${entry.lyrics.split('\n').length} lines)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (entry.timelineOffsetMillis != 0)
              Text(
                'Offset: ${entry.timelineOffsetMillis > 0 ? "+" : ""}${entry.timelineOffsetMillis}ms',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: SelectableText(
              entry.lyrics,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.restore_rounded, size: 18),
          label: Text(l10n.restoreThisVersion),
          onPressed: isCurrent
              ? null
              : () {
                  Navigator.of(context).pop(entry);
                },
        ),
      ],
    );
  }
}
