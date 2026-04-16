import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/clean_helper.dart';
import '../player/acoustid_service.dart';
import '../player/metadata_helper.dart';
import '../player/metadata_database.dart';
import '../player/musicbrainz_tag_completion_service.dart';
import '../pages/main_layout.dart';
import 'song_tag_completion_widgets.dart';
import 'song_tag_musicbrainz_cards.dart';
import 'song_tag_acoustid_cards.dart';
import 'song_tag_completion_riverpod.dart';

enum _SummaryCondition { title, artist, album, duration }

class SongTagCompletionSheet extends ConsumerStatefulWidget {
  const SongTagCompletionSheet({
    super.key,
    required this.songPath,
    required this.currentTitle,
    required this.currentArtist,
    required this.currentAlbum,
    required this.durationMillis,
  });

  final String songPath;
  final String? currentTitle;
  final String? currentArtist;
  final String? currentAlbum;
  final int? durationMillis;

  @override
  ConsumerState<SongTagCompletionSheet> createState() =>
      _SongTagCompletionSheetState();
}

class _SongTagCompletionSheetState
    extends ConsumerState<SongTagCompletionSheet> {
  final TextEditingController _musicBrainzSearchController =
      TextEditingController();
  final FocusNode _musicBrainzSearchFocusNode = FocusNode();
  late final SongTagCompletionController _controller;

  bool _isMusicBrainzSearchExpanded = false;
  SongMetadata? _fileMetadata;
  final Set<String> _expandedAcoustIDIds = <String>{};
  final Set<String> _expandedReleaseGroupIds = <String>{};
  final Set<String> _expandedMusicBrainzRecordingIds = <String>{};
  String? _lastAcoustIDClientErrorMessage;
  final Set<_SummaryCondition> _disabledSummaryConditions =
      <_SummaryCondition>{};
  final Map<_SummaryCondition, String> _editedSummaryConditionTexts =
      <_SummaryCondition, String>{};

  @override
  void initState() {
    super.initState();
    _controller = ref.read(
      songTagCompletionControllerProvider(widget.songPath),
    );
    _musicBrainzSearchController.addListener(_onMusicBrainzSearchChanged);
    _loadInitialData();
  }

  @override
  void dispose() {
    _musicBrainzSearchController.removeListener(_onMusicBrainzSearchChanged);
    _musicBrainzSearchController.dispose();
    _musicBrainzSearchFocusNode.dispose();
    super.dispose();
  }

  void _onMusicBrainzSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    try {
      final metadata = await MetadataHelper.readMetadataFromFile(
        widget.songPath,
      );
      if (!mounted) return;
      setState(() {
        _fileMetadata = metadata;
      });
    } catch (e) {
      debugPrint('Error reading file tags: $e');
    }

    if (!mounted) return;
    _loadMatches();
    _loadAcoustIDResult();
  }

  String get _displayTitle {
    final fileTitle = _fileMetadata?.title.trim();
    if (fileTitle != null && fileTitle.isNotEmpty) {
      return fileTitle;
    }
    final title = widget.currentTitle?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return CleanHelper.deriveCleanTitleFromFileName(widget.songPath);
  }

  bool _isSummaryConditionEnabled(_SummaryCondition condition) {
    return !_disabledSummaryConditions.contains(condition);
  }

  String? _summaryConditionSourceText(_SummaryCondition condition) {
    switch (condition) {
      case _SummaryCondition.title:
        return _displayTitle;
      case _SummaryCondition.artist:
        return _preferredMetadataText(
          _fileMetadata?.artist,
          widget.currentArtist,
        );
      case _SummaryCondition.album:
        return _preferredMetadataText(
          _fileMetadata?.album,
          widget.currentAlbum,
        );
      case _SummaryCondition.duration:
        final duration = _fileMetadata?.duration ?? widget.durationMillis;
        if (duration == null) return null;
        final minutes = duration ~/ 60000;
        final seconds = (duration ~/ 1000) % 60;
        return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  String? _summaryConditionText(_SummaryCondition condition) {
    final edited = _editedSummaryConditionTexts[condition];
    if (_hasMeaningfulText(edited)) return edited!.trim();
    return _summaryConditionSourceText(condition);
  }

  bool _canEditSummaryCondition(_SummaryCondition condition) {
    return condition != _SummaryCondition.duration;
  }

  String get _musicBrainzSearchQuery =>
      _musicBrainzSearchController.text.trim().toLowerCase();

  bool get _hasMusicBrainzSearchQuery => _musicBrainzSearchQuery.isNotEmpty;

  String? _preferredMetadataText(String? primary, String? fallback) {
    if (_hasMeaningfulText(primary)) return primary!.trim();
    if (_hasMeaningfulText(fallback)) return fallback!.trim();
    return null;
  }

  List<MusicBrainzTrackMatch> _filteredMusicBrainzMatches(
    SongTagCompletionController controller,
  ) {
    if (!_hasMusicBrainzSearchQuery) return controller.musicBrainzMatches;

    final query = _musicBrainzSearchQuery;
    return controller.musicBrainzMatches
        .where((match) => _musicBrainzMatchMatchesQuery(match, query))
        .toList(growable: false);
  }

  bool _musicBrainzMatchMatchesQuery(
    MusicBrainzTrackMatch match,
    String query,
  ) {
    if (_musicBrainzReleaseTitleMatches(match.title, query) ||
        _musicBrainzReleaseTitleMatches(match.artist, query) ||
        (match.album != null &&
            _musicBrainzReleaseTitleMatches(match.album!, query))) {
      return true;
    }

    return match.releases.any(
      (release) =>
          _musicBrainzReleaseTitleMatches(release.title, query) ||
          (release.country != null &&
              _musicBrainzReleaseTitleMatches(release.country!, query)) ||
          (release.dateLabel != null &&
              _musicBrainzReleaseTitleMatches(release.dateLabel!, query)),
    );
  }

  bool _musicBrainzReleaseTitleMatches(String title, String query) {
    return title.trim().toLowerCase().contains(query);
  }

  String _musicBrainzLoadingSubtitle(SongTagCompletionController controller) {
    if (controller.acoustidResults.isNotEmpty) {
      return 'MusicBrainz 正在查询中，现有结果会先保留在面板里。';
    }
    return 'MusicBrainz 正在查询中，请稍候。';
  }

  String _musicBrainzEmptySubtitle(
    SongTagCompletionController controller, {
    required bool isFilteredSearch,
  }) {
    final errorMessage = controller.musicBrainzErrorMessage;
    if (errorMessage != null && errorMessage.isNotEmpty) {
      final lower = errorMessage.toLowerCase();
      if (lower.contains('socketexception') ||
          lower.contains('connection') ||
          lower.contains('network') ||
          lower.contains('timeout') ||
          lower.contains('dioexception')) {
        return 'MusicBrainz 请求失败，通常是网络连接不稳定、超时或被服务端拒绝。可以稍后重试。';
      }
      return errorMessage;
    }

    if (isFilteredSearch) {
      return '当前过滤条件下没有包含该关键词的 release 标题。';
    }

    return 'MusicBrainz 没有返回可用结果。可以放宽标题、艺人或专辑条件后再试一次。';
  }

  bool _hasMeaningfulText(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    return lower != 'unknown' &&
        lower != 'unknown artist' &&
        lower != 'unknown album';
  }

  void _toggleMusicBrainzSearchPanel() {
    setState(() {
      _isMusicBrainzSearchExpanded = !_isMusicBrainzSearchExpanded;
    });

    if (_isMusicBrainzSearchExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _musicBrainzSearchFocusNode.requestFocus();
      });
    } else {
      _musicBrainzSearchFocusNode.unfocus();
    }
  }

  void _clearMusicBrainzSearch() {
    if (_musicBrainzSearchController.text.isEmpty) return;
    _musicBrainzSearchController.clear();
  }

  Future<void> _editSummaryCondition(_SummaryCondition condition) async {
    if (!_canEditSummaryCondition(condition)) return;

    final initialValue = _summaryConditionText(condition) ?? '';
    final controller = TextEditingController(text: initialValue);

    final editedValue = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        var currentValue = initialValue;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final canSave = currentValue.trim().isNotEmpty;
            return AlertDialog(
              backgroundColor: const Color(0xFF171717),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                '编辑查询条件',
                style: TextStyle(color: Colors.white),
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: const Color(0xFF46D27A),
                decoration: InputDecoration(
                  hintText: '输入新的查询文字',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                onChanged: (value) {
                  setDialogState(() {
                    currentValue = value;
                  });
                },
                onSubmitted: canSave
                    ? (_) =>
                          Navigator.of(dialogContext).pop(currentValue.trim())
                    : null,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: canSave
                      ? () =>
                            Navigator.of(dialogContext).pop(currentValue.trim())
                      : null,
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (!mounted || editedValue == null) return;
    final trimmed = editedValue.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      final sourceValue = _summaryConditionSourceText(condition)?.trim() ?? '';
      if (trimmed == sourceValue) {
        _editedSummaryConditionTexts.remove(condition);
      } else {
        _editedSummaryConditionTexts[condition] = trimmed;
      }
    });

    await _loadMatches();
  }

  Future<void> _toggleSummaryCondition(_SummaryCondition condition) async {
    if (!mounted) return;
    setState(() {
      if (_disabledSummaryConditions.contains(condition)) {
        _disabledSummaryConditions.remove(condition);
      } else {
        _disabledSummaryConditions.add(condition);
      }
    });

    await _loadMatches();
  }

  Future<void> _loadMatches() async {
    if (!mounted) return;
    final title = _summaryConditionText(_SummaryCondition.title);
    final artist = _summaryConditionText(_SummaryCondition.artist);
    final album = _summaryConditionText(_SummaryCondition.album);

    await _controller.loadMusicBrainzMatches(
      title: title,
      artist: artist,
      album: album,
      durationMillis: _fileMetadata?.duration ?? widget.durationMillis,
      enableTitleQuery: _isSummaryConditionEnabled(_SummaryCondition.title),
      enableArtistQuery: _isSummaryConditionEnabled(_SummaryCondition.artist),
      enableAlbumQuery: _isSummaryConditionEnabled(_SummaryCondition.album),
      enableDurationQuery: _isSummaryConditionEnabled(
        _SummaryCondition.duration,
      ),
    );

    if (!mounted) return;
    setState(() {
      _expandedMusicBrainzRecordingIds.clear();
    });
  }

  Future<void> _loadAcoustIDResult() async {
    _lastAcoustIDClientErrorMessage = null;
    final durationSec = (_fileMetadata?.duration ?? widget.durationMillis ?? 0);
    await _controller.loadAcoustIDResult(durationMillis: durationSec);

    final acoustidErrorMessage = _controller.acoustidClientErrorMessage;
    if (mounted &&
        acoustidErrorMessage != null &&
        acoustidErrorMessage != _lastAcoustIDClientErrorMessage) {
      _lastAcoustIDClientErrorMessage = acoustidErrorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(acoustidErrorMessage),
          action: SnackBarAction(
            label: '去设置页',
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pushReplacement(
                buildMainLayoutRoute(args: const [], initialIndex: 4),
              );
            },
          ),
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _expandedAcoustIDIds.clear();
      _expandedReleaseGroupIds.clear();
      _expandedMusicBrainzRecordingIds.clear();
    });
  }

  Future<void> _applyAcoustIDSelection({
    required AcoustIDResult trackResult,
    required AcoustIDRecording recording,
    required String albumTitle,
    required String sourceLabel,
    required String fallbackTitle,
    required int? fallbackDurationMillis,
    String? releaseId,
    String? releaseGroupId,
    String? coverLargeUrl,
    String? coverThumbnailUrl,
    Map<String, dynamic>? raw,
    String? country,
    String? releaseDate,
  }) async {
    final result = await _controller.applyAcoustIDSelection(
      trackResult: trackResult,
      recording: recording,
      albumTitle: albumTitle,
      sourceLabel: sourceLabel,
      fallbackTitle: fallbackTitle,
      fallbackDurationMillis: fallbackDurationMillis,
      releaseId: releaseId,
      releaseGroupId: releaseGroupId,
      coverLargeUrl: coverLargeUrl,
      coverThumbnailUrl: coverThumbnailUrl,
      raw: raw,
      country: country,
      releaseDate: releaseDate,
      existingMetadata: _fileMetadata,
    );
    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _applyAcoustIDReleaseGroup(
    AcoustIDResult trackResult,
    AcoustIDRecording recording,
    AcoustIDReleaseGroup releaseGroup,
  ) async {
    await _applyAcoustIDSelection(
      trackResult: trackResult,
      recording: recording,
      albumTitle: releaseGroup.title,
      sourceLabel: 'AcoustID release-group',
      fallbackTitle: _displayTitle,
      fallbackDurationMillis: _fileMetadata?.duration ?? widget.durationMillis,
      releaseGroupId: releaseGroup.id,
      coverLargeUrl: releaseGroup.largeUrl,
      coverThumbnailUrl: releaseGroup.thumbnailUrl,
      raw: {
        'track': trackResult.raw,
        'recording': recording.raw,
        'releaseGroup': releaseGroup.raw,
      },
    );
  }

  Future<void> _applyAcoustIDRelease(
    AcoustIDResult trackResult,
    AcoustIDRecording recording,
    AcoustIDReleaseGroup releaseGroup,
    AcoustIDRelease release,
  ) async {
    await _applyAcoustIDSelection(
      trackResult: trackResult,
      recording: recording,
      albumTitle: release.title,
      sourceLabel: 'AcoustID release',
      fallbackTitle: _displayTitle,
      fallbackDurationMillis: _fileMetadata?.duration ?? widget.durationMillis,
      releaseId: release.id,
      releaseGroupId: releaseGroup.id,
      coverLargeUrl: release.largeUrl,
      coverThumbnailUrl: release.thumbnailUrl,
      country: release.country,
      releaseDate: release.dateLabel,
      raw: {
        'track': trackResult.raw,
        'recording': recording.raw,
        'releaseGroup': releaseGroup.raw,
        'release': release.raw,
      },
    );
  }

  Future<void> _applyMusicBrainzRelease(
    MusicBrainzTrackMatch match,
    MusicBrainzReleaseMatch release,
  ) async {
    final result = await _controller.applyMusicBrainzRelease(
      match: match,
      release: release,
      fallbackDurationMillis: _fileMetadata?.duration ?? widget.durationMillis,
      existingMetadata: _fileMetadata,
    );

    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  Widget _buildHeader(
    BuildContext context,
    SongTagCompletionController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '歌曲标签补全',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '根据音频指纹检索 AcoustID，同时检索 MusicBrainz 的录音结果；点开录音后选择具体 release 封面来补全信息。',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _toggleMusicBrainzSearchPanel,
                icon: Icon(
                  _isMusicBrainzSearchExpanded
                      ? Icons.search_off_rounded
                      : Icons.search_rounded,
                  color: _hasMusicBrainzSearchQuery
                      ? const Color(0xFF46D27A)
                      : Colors.white70,
                ),
                tooltip: _isMusicBrainzSearchExpanded
                    ? '关闭搜索'
                    : '搜索 release 标题',
              ),
              IconButton(
                onPressed: controller.isMusicBrainzLoading
                    ? null
                    : _loadMatches,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                tooltip: '刷新结果',
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                tooltip: '关闭',
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _isMusicBrainzSearchExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: _musicBrainzSearchController,
                      focusNode: _musicBrainzSearchFocusNode,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: const Color(0xFF46D27A),
                      decoration: InputDecoration(
                        hintText: '过滤 MusicBrainz release 标题',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                        suffixIcon: _hasMusicBrainzSearchQuery
                            ? IconButton(
                                onPressed: _clearMusicBrainzSearch,
                                icon: Icon(
                                  Icons.clear_rounded,
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                                tooltip: '清空搜索',
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF46D27A),
                            width: 1.1,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(
    BuildContext context,
    SongTagCompletionController controller,
  ) {
    final summaryItems = <Widget>[
      SongTagSummaryChip(
        label: '本地标题',
        value: _summaryConditionText(_SummaryCondition.title) ?? _displayTitle,
        enabled: _isSummaryConditionEnabled(_SummaryCondition.title),
        onTap: () => _toggleSummaryCondition(_SummaryCondition.title),
        onEdit: () => _editSummaryCondition(_SummaryCondition.title),
      ),
      if ((_fileMetadata?.artist ?? widget.currentArtist ?? '')
          .trim()
          .isNotEmpty)
        SongTagSummaryChip(
          label: '艺术家',
          value:
              _summaryConditionText(_SummaryCondition.artist) ??
              (_fileMetadata?.artist ?? widget.currentArtist!).trim(),
          enabled: _isSummaryConditionEnabled(_SummaryCondition.artist),
          onTap: () => _toggleSummaryCondition(_SummaryCondition.artist),
          onEdit: () => _editSummaryCondition(_SummaryCondition.artist),
        ),
      if ((_fileMetadata?.album ?? widget.currentAlbum ?? '').trim().isNotEmpty)
        SongTagSummaryChip(
          label: '专辑',
          value:
              _summaryConditionText(_SummaryCondition.album) ??
              (_fileMetadata?.album ?? widget.currentAlbum!).trim(),
          enabled: _isSummaryConditionEnabled(_SummaryCondition.album),
          onTap: () => _toggleSummaryCondition(_SummaryCondition.album),
          onEdit: () => _editSummaryCondition(_SummaryCondition.album),
        ),
      if (_fileMetadata?.duration != null || widget.durationMillis != null)
        SongTagSummaryChip(
          label: '时长',
          value:
              '${((_fileMetadata?.duration ?? widget.durationMillis!) ~/ 60000).toString().padLeft(2, '0')}:${(((_fileMetadata?.duration ?? widget.durationMillis!) ~/ 1000) % 60).toString().padLeft(2, '0')}',
          enabled: _isSummaryConditionEnabled(_SummaryCondition.duration),
          onTap: () => _toggleSummaryCondition(_SummaryCondition.duration),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '查询条件',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: summaryItems),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SongTagCompletionController controller,
  ) {
    final filteredMusicBrainzMatches = _filteredMusicBrainzMatches(controller);
    final hasFilteredMusicBrainzMatches = filteredMusicBrainzMatches.isNotEmpty;
    final hasAnyResults =
        controller.acoustidResults.isNotEmpty || hasFilteredMusicBrainzMatches;
    final isMusicBrainzFilteringEmpty =
        controller.musicBrainzMatches.isNotEmpty &&
        _hasMusicBrainzSearchQuery &&
        filteredMusicBrainzMatches.isEmpty;

    if (controller.isMusicBrainzLoading &&
        controller.acoustidResults.isEmpty &&
        !hasFilteredMusicBrainzMatches) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: const Color(0xFF46D27A).withValues(alpha: 0.95),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '正在查询 MusicBrainz',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _musicBrainzLoadingSubtitle(controller),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!controller.isMusicBrainzLoading &&
        controller.musicBrainzErrorMessage != null &&
        controller.acoustidResults.isEmpty &&
        !hasFilteredMusicBrainzMatches) {
      return SongTagEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'MusicBrainz 查询失败',
        subtitle: _musicBrainzEmptySubtitle(
          controller,
          isFilteredSearch: isMusicBrainzFilteringEmpty,
        ),
        actionLabel: '重试',
        onAction: () {
          _loadMatches();
          _loadAcoustIDResult();
        },
      );
    }

    final children = <Widget>[];

    if (controller.isMusicBrainzLoading) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: const Color(0xFF46D27A).withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _musicBrainzLoadingSubtitle(controller),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (controller.acoustidResults.isNotEmpty ||
          hasFilteredMusicBrainzMatches) {
        children.add(const SizedBox(height: 10));
      }
    }

    if (controller.isAcoustIDLoading) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      );
    } else if (controller.acoustidResults.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
          child: Text(
            'AcoustID 识别记录',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      for (var i = 0; i < controller.acoustidResults.length; i++) {
        final result = controller.acoustidResults[i];
        final trackKey = result.id.isNotEmpty ? result.id : 'track_$i';
        children.add(
          SongTagAcoustIDResultCard(
            result: result,
            index: i,
            displayTitle: _displayTitle,
            isApplying: controller.isApplying,
            isExpanded: _expandedAcoustIDIds.contains(trackKey),
            onToggleExpanded: () {
              setState(() {
                if (_expandedAcoustIDIds.contains(trackKey)) {
                  _expandedAcoustIDIds.remove(trackKey);
                } else {
                  _expandedAcoustIDIds.add(trackKey);
                }
              });
            },
            isReleaseGroupExpanded: (releaseGroupId) =>
                _expandedReleaseGroupIds.contains(releaseGroupId),
            onToggleReleaseGroupExpanded: (releaseGroupId) {
              setState(() {
                if (_expandedReleaseGroupIds.contains(releaseGroupId)) {
                  _expandedReleaseGroupIds.remove(releaseGroupId);
                } else {
                  _expandedReleaseGroupIds.add(releaseGroupId);
                }
              });
            },
            onApplyReleaseGroup: _applyAcoustIDReleaseGroup,
            onApplyRelease: _applyAcoustIDRelease,
          ),
        );
        if (i < controller.acoustidResults.length - 1) {
          children.add(const SizedBox(height: 8));
        }
      }
      children.add(const SizedBox(height: 10));
    }

    if (!controller.isMusicBrainzLoading) {
      if (!hasAnyResults) {
        return Center(
          child: SongTagEmptyState(
            icon: Icons.search_off_rounded,
            title: _hasMusicBrainzSearchQuery ? '没有找到匹配的 release' : '没有找到匹配结果',
            subtitle: _musicBrainzEmptySubtitle(
              controller,
              isFilteredSearch: isMusicBrainzFilteringEmpty,
            ),
            actionLabel: _hasMusicBrainzSearchQuery ? '清空搜索' : '重新搜索',
            onAction: () {
              if (_hasMusicBrainzSearchQuery) {
                _clearMusicBrainzSearch();
              } else {
                _loadMatches();
                _loadAcoustIDResult();
              }
            },
          ),
        );
      }

      if (hasFilteredMusicBrainzMatches) {
        if (children.isNotEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
              child: Text(
                'MusicBrainz 录音',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }

        for (var i = 0; i < filteredMusicBrainzMatches.length; i++) {
          final match = filteredMusicBrainzMatches[i];
          final recordingKey = match.recordingId.isNotEmpty
              ? match.recordingId
              : 'recording_$i';
          children.add(
            SongTagMusicBrainzRecordingCard(
              match: match,
              index: i,
              displayTitle: _displayTitle,
              service: controller.service,
              isApplying: controller.isApplying,
              isExpanded: _expandedMusicBrainzRecordingIds.contains(
                recordingKey,
              ),
              onToggleExpanded: () {
                setState(() {
                  if (_expandedMusicBrainzRecordingIds.contains(recordingKey)) {
                    _expandedMusicBrainzRecordingIds.remove(recordingKey);
                  } else {
                    _expandedMusicBrainzRecordingIds.add(recordingKey);
                  }
                });
              },
              onApplyRelease: _applyMusicBrainzRelease,
            ),
          );
          if (i < filteredMusicBrainzMatches.length - 1) {
            children.add(const SizedBox(height: 8));
          }
        }
      }
    }

    if (children.isEmpty) {
      return Center(
        child: SongTagEmptyState(
          icon: Icons.search_off_rounded,
          title: '没有找到匹配结果',
          subtitle: '可以稍后重试，或者确认当前歌曲标题/艺人信息是否更完整。',
          actionLabel: '重新搜索',
          onAction: () {
            _loadMatches();
            _loadAcoustIDResult();
          },
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(
      songTagCompletionControllerProvider(widget.songPath),
    );

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.82),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, controller),
                    _buildSummary(context, controller),
                    const SizedBox(height: 14),
                    Expanded(child: _buildBody(context, controller)),
                  ],
                ),
                if (controller.isApplying)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.35),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
