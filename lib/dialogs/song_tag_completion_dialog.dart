import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../utils/clean_helper.dart';
import '../player/musicbrainz_tag_completion_service.dart';
import '../player/acoustid_service.dart';
import '../player/metadata_helper.dart';
import '../player/metadata_database.dart';

class SongTagCompletionSheet extends StatefulWidget {
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
  State<SongTagCompletionSheet> createState() => _SongTagCompletionSheetState();
}

class _SongTagCompletionSheetState extends State<SongTagCompletionSheet> {
  final MusicBrainzTagCompletionService _service =
      MusicBrainzTagCompletionService();

  List<MusicBrainzTrackMatch> _matches = const [];
  bool _isLoading = true;
  bool _isApplying = false;
  String? _errorMessage;
  SongMetadata? _fileMetadata;
  List<AcoustIDResult> _acoustidResults = const [];
  bool _isAcoustIDLoading = true;
  AcoustIDService? _acoustidService;
  final Set<String> _expandedAcoustIDIds = <String>{};
  final Set<String> _expandedReleaseGroupIds = <String>{};
  final Set<String> _expandedMusicBrainzRecordingIds = <String>{};
  final Set<String> _expandedMusicBrainzReleaseGroupIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadAcoustIDResult();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      _fileMetadata = await MetadataHelper.readMetadataFromFile(
        widget.songPath,
      );
    } catch (e) {
      debugPrint('Error reading file tags: $e');
    }

    if (!mounted) return;
    _loadMatches();
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

  Future<void> _loadMatches() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await _service.searchMatches(
        songPath: widget.songPath,
        title: _fileMetadata?.title ?? widget.currentTitle,
        artist: _fileMetadata?.artist ?? widget.currentArtist,
        album: _fileMetadata?.album ?? widget.currentAlbum,
        durationMillis: _fileMetadata?.duration ?? widget.durationMillis,
      );

      if (!mounted) return;
      setState(() {
        _matches = results;
        _expandedMusicBrainzRecordingIds.clear();
        _expandedMusicBrainzReleaseGroupIds.clear();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAcoustIDResult() async {
    try {
      final apiKeyFile = File('api_keys.json');
      String apiKey;
      if (await apiKeyFile.exists()) {
        final content = await apiKeyFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        apiKey = json['AcoustID_API_KEY'] as String? ?? '';
      } else {
        debugPrint('AcoustID: api_keys.json not found');
        if (!mounted) return;
        setState(() => _isAcoustIDLoading = false);
        return;
      }

      if (apiKey.isEmpty) {
        debugPrint('AcoustID: API key is empty');
        if (!mounted) return;
        setState(() => _isAcoustIDLoading = false);
        return;
      }

      final acoustidService = AcoustIDService(apiKey: apiKey);
      _acoustidService = acoustidService;
      final durationSec =
          (_fileMetadata?.duration ?? widget.durationMillis ?? 0) ~/ 1000;
      final results = await acoustidService.lookupByFingerprint(
        filePath: widget.songPath,
        durationSeconds: durationSec,
      );

      if (!mounted) return;
      setState(() {
        _acoustidResults = results;
        _expandedAcoustIDIds.clear();
        _expandedReleaseGroupIds.clear();
        _expandedMusicBrainzRecordingIds.clear();
        _isAcoustIDLoading = false;
      });
    } catch (e) {
      debugPrint('AcoustID: Failed to load result: $e');
      if (!mounted) return;
      setState(() => _isAcoustIDLoading = false);
    }
  }

  Future<void> _applyAcoustIDSelection({
    required AcoustIDResult trackResult,
    required AcoustIDRecording recording,
    required String albumTitle,
    required String sourceLabel,
    String? releaseId,
    String? releaseGroupId,
    String? coverLargeUrl,
    String? coverThumbnailUrl,
    Map<String, dynamic>? raw,
    String? country,
    String? releaseDate,
  }) async {
    if (_isApplying) return;

    if (!mounted) return;
    setState(() {
      _isApplying = true;
      _errorMessage = null;
    });

    final coverArtBytes = await _acoustidService?.downloadCoverBytes(
      candidateUrls: [coverLargeUrl, coverThumbnailUrl],
    );

    try {
      final durationMillis = recording.durationMillis ?? widget.durationMillis;
      final saved = await MetadataHelper.saveSelectedSongMetadata(
        filePath: widget.songPath,
        title: recording.title,
        artist: recording.artist,
        album: albumTitle,
        duration: durationMillis,
        artworkBytes: coverArtBytes,
      );

      if (saved == null) {
        throw StateError('写入标签和文件同步失败');
      }

      final updated = saved.$1;
      final resolvedCover = coverLargeUrl != null || coverThumbnailUrl != null
          ? ResolvedCover(
              endpoint: releaseId != null ? 'release' : 'release-group',
              id: releaseId ?? releaseGroupId ?? '',
              largeUrl: coverLargeUrl,
              thumbnailUrl: coverThumbnailUrl ?? coverLargeUrl,
            )
          : null;

      if (!mounted) return;
      Navigator.of(context).pop(
        MusicBrainzTagSelectionResult(
          metadata: updated,
          artworkBytes: coverArtBytes,
          match: _buildAcoustIDSelectionMatch(
            trackResult: trackResult,
            recording: recording,
            albumTitle: albumTitle,
            releaseId: releaseId,
            releaseGroupId: releaseGroupId,
            releaseDate: releaseDate,
            country: country,
            raw: raw,
            resolvedCover: resolvedCover,
            sourceLabel: sourceLabel,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isApplying = false;
        _errorMessage = '保存失败：$e';
      });
    }
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

  MusicBrainzTrackMatch _buildAcoustIDSelectionMatch({
    required AcoustIDResult trackResult,
    required AcoustIDRecording recording,
    required String albumTitle,
    required String sourceLabel,
    String? releaseId,
    String? releaseGroupId,
    String? releaseDate,
    String? country,
    Map<String, dynamic>? raw,
    ResolvedCover? resolvedCover,
  }) {
    return MusicBrainzTrackMatch(
      recordingId: recording.id.isNotEmpty ? recording.id : trackResult.id,
      title: recording.title.isNotEmpty ? recording.title : _displayTitle,
      artist: recording.artist.isNotEmpty ? recording.artist : 'Unknown Artist',
      album: albumTitle,
      releaseId: releaseId,
      releaseGroupId: releaseGroupId,
      releaseDate: releaseDate,
      country: country,
      durationMillis: recording.durationMillis ?? widget.durationMillis,
      trackNumber: null,
      score: (trackResult.score * 100).round().clamp(0, 100),
      disambiguation: sourceLabel,
      releases: const [],
      raw: raw ?? {'track': trackResult.raw, 'recording': recording.raw},
    )..resolvedCover = resolvedCover;
  }

  Future<void> _applyMusicBrainzRelease(
    MusicBrainzTrackMatch match,
    MusicBrainzReleaseMatch release,
  ) async {
    if (_isApplying) return;

    if (!mounted) return;
    setState(() {
      _isApplying = true;
      _errorMessage = null;
    });

    try {
      final result = await _service.applySelection(
        songPath: widget.songPath,
        match: match,
        selectedRelease: release,
        fallbackDurationMillis: widget.durationMillis,
      );

      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isApplying = false;
        _errorMessage = '保存失败：$e';
      });
    }
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
      child: Row(
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
            onPressed: _isLoading ? null : _loadMatches,
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
    );
  }

  Widget _buildSummary(BuildContext context) {
    final chips = <Widget>[
      _InfoChip(label: '本地标题', value: _displayTitle),
      if ((_fileMetadata?.artist ?? widget.currentArtist ?? '')
          .trim()
          .isNotEmpty)
        _InfoChip(
          label: '艺术家',
          value: (_fileMetadata?.artist ?? widget.currentArtist!).trim(),
        ),
      if ((_fileMetadata?.album ?? widget.currentAlbum ?? '').trim().isNotEmpty)
        _InfoChip(
          label: '专辑',
          value: (_fileMetadata?.album ?? widget.currentAlbum!).trim(),
        ),
      if (_fileMetadata?.duration != null || widget.durationMillis != null)
        _InfoChip(
          label: '时长',
          value:
              '${((_fileMetadata?.duration ?? widget.durationMillis!) ~/ 60000).toString().padLeft(2, '0')}:${(((_fileMetadata?.duration ?? widget.durationMillis!) ~/ 1000) % 60).toString().padLeft(2, '0')}',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading && _isAcoustIDLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }

    if (_errorMessage != null && _acoustidResults.isEmpty && _matches.isEmpty) {
      return _EmptyState(
        icon: Icons.wifi_off_rounded,
        title: '检索失败',
        subtitle: _errorMessage!,
        actionLabel: '重试',
        onAction: () {
          _loadMatches();
          _loadAcoustIDResult();
        },
      );
    }

    final children = <Widget>[];

    if (_isAcoustIDLoading) {
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
    } else if (_acoustidResults.isNotEmpty) {
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
      for (var i = 0; i < _acoustidResults.length; i++) {
        children.add(_buildAcoustIDResultCard(_acoustidResults[i], i));
        if (i < _acoustidResults.length - 1) {
          children.add(const SizedBox(height: 8));
        }
      }
      children.add(const SizedBox(height: 10));
    }

    if (!_isLoading) {
      if (_matches.isEmpty && _acoustidResults.isEmpty) {
        return Center(
          child: _EmptyState(
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

      if (_matches.isNotEmpty) {
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

        for (var i = 0; i < _matches.length; i++) {
          children.add(_buildMusicBrainzRecordingCard(_matches[i], i));
          if (i < _matches.length - 1) {
            children.add(const SizedBox(height: 8));
          }
        }
      }
    }

    if (children.isEmpty) {
      return Center(
        child: _EmptyState(
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

  Widget _buildMusicBrainzRecordingCard(
    MusicBrainzTrackMatch match,
    int index,
  ) {
    final recordingKey = match.recordingId.isNotEmpty
        ? match.recordingId
        : 'recording_$index';
    final expanded = _expandedMusicBrainzRecordingIds.contains(recordingKey);
    final releaseGroups = match.releaseGroups;
    final releaseGroupCount = releaseGroups.length;
    final hasReleaseGroups = releaseGroupCount > 0;
    final durationText = match.durationLabel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _isApplying
                  ? null
                  : () {
                      setState(() {
                        if (expanded) {
                          _expandedMusicBrainzRecordingIds.remove(recordingKey);
                        } else {
                          _expandedMusicBrainzRecordingIds.add(recordingKey);
                        }
                      });
                    },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _MatchCoverImage(
                            match: match,
                            service: _service,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(6),
                                bottomRight: Radius.circular(10),
                              ),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            match.title.isNotEmpty
                                ? match.title
                                : _displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (match.artist.isNotEmpty) match.artist,
                              if (match.album != null &&
                                  match.album!.isNotEmpty)
                                match.album!,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              durationText,
                              '$releaseGroupCount 组发行版',
                              '评分 ${match.score}',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _ScoreBadge(score: match.score),
                        const SizedBox(height: 10),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            hasReleaseGroups
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.remove_rounded,
                            color: hasReleaseGroups
                                ? Colors.white.withValues(alpha: 0.45)
                                : Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: hasReleaseGroups
                          ? Column(
                              children: [
                                for (var i = 0; i < releaseGroups.length; i++)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: i == 0 ? 0 : 8,
                                    ),
                                    child: _buildMusicBrainzReleaseRow(
                                      match: match,
                                      releaseGroup: releaseGroups[i],
                                    ),
                                  ),
                              ],
                            )
                          : Text(
                              '没有可展开的发行版',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.42),
                                fontSize: 11,
                              ),
                            ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicBrainzReleaseRow({
    required MusicBrainzTrackMatch match,
    required MusicBrainzReleaseGroup releaseGroup,
  }) {
    final groupKey = '${match.recordingId}::${releaseGroup.key}';
    final expanded = _expandedMusicBrainzReleaseGroupIds.contains(groupKey);
    final releaseCount = releaseGroup.releases.length;
    final primaryRelease = releaseGroup.releases.first;

    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _isApplying
                ? null
                : () {
                    setState(() {
                      if (expanded) {
                        _expandedMusicBrainzReleaseGroupIds.remove(groupKey);
                      } else {
                        _expandedMusicBrainzReleaseGroupIds.add(groupKey);
                      }
                    });
                  },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: Image.network(
                        releaseGroup.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.white.withValues(alpha: 0.05),
                          child: const Icon(
                            Icons.album_outlined,
                            color: Colors.white24,
                            size: 20,
                          ),
                        ),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Center(
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          releaseGroup.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            '$releaseCount 个发行版',
                            if (primaryRelease.country != null &&
                                primaryRelease.country!.isNotEmpty)
                              primaryRelease.country!,
                            if (primaryRelease.dateLabel != null &&
                                primaryRelease.dateLabel!.isNotEmpty)
                              primaryRelease.dateLabel!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: Column(
                      children: [
                        for (var i = 0; i < releaseGroup.releases.length; i++)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                            child: _buildMusicBrainzReleaseItem(
                              match: match,
                              release: releaseGroup.releases[i],
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildMusicBrainzReleaseItem({
    required MusicBrainzTrackMatch match,
    required MusicBrainzReleaseMatch release,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: _isApplying
            ? null
            : () => _applyMusicBrainzRelease(match, release),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Image.network(
                    release.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child: const Icon(
                        Icons.album_outlined,
                        color: Colors.white24,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      release.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (release.country != null &&
                            release.country!.isNotEmpty)
                          release.country!,
                        if (release.dateLabel != null &&
                            release.dateLabel!.isNotEmpty)
                          release.dateLabel!,
                        if (release.trackCount != null)
                          '${release.trackCount} 首',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAcoustIDResultCard(AcoustIDResult result, int index) {
    final trackKey = result.id.isNotEmpty ? result.id : 'track_$index';
    final expanded = _expandedAcoustIDIds.contains(trackKey);
    final primaryRecording = result.primaryRecording;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: const Color(0xFF46D27A).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _isApplying
              ? null
              : () {
                  setState(() {
                    if (expanded) {
                      _expandedAcoustIDIds.remove(trackKey);
                    } else {
                      _expandedAcoustIDIds.add(trackKey);
                    }
                  });
                },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFF46D27A).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _AcoustIDCoverImage(result: result),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  result.title.isNotEmpty
                                      ? result.title
                                      : _displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF46D27A,
                                  ).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF46D27A,
                                    ).withValues(alpha: 0.4),
                                  ),
                                ),
                                child: const Text(
                                  'AcoustID',
                                  style: TextStyle(
                                    color: Color(0xFF46D27A),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (result.artist.isNotEmpty) result.artist,
                              if (result.album != null &&
                                  result.album!.isNotEmpty)
                                result.album!,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              '录音 ${result.recordings.length} 条',
                              result.durationLabel,
                              '匹配度 ${(result.score * 100).round()}%',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11,
                            ),
                          ),
                          if (primaryRecording != null &&
                              primaryRecording.releaseGroups.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '首个专辑：${primaryRecording.releaseGroups.first.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.38),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF46D27A).withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: Column(
                          children: [
                            for (var i = 0; i < result.recordings.length; i++)
                              Padding(
                                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                                child: _buildAcoustIDRecordingBlock(
                                  trackResult: result,
                                  recording: result.recordings[i],
                                  recordingIndex: i,
                                ),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAcoustIDRecordingBlock({
    required AcoustIDResult trackResult,
    required AcoustIDRecording recording,
    required int recordingIndex,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${recordingIndex + 1}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recording.title.isNotEmpty
                            ? recording.title
                            : trackResult.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (recording.artist.isNotEmpty) recording.artist,
                          recording.durationLabel,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (recording.releaseGroups.isEmpty)
              Text(
                '没有可展开的专辑列表',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontSize: 11,
                ),
              )
            else
              Column(
                children: [
                  for (var i = 0; i < recording.releaseGroups.length; i++)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                      child: _buildAcoustIDReleaseGroupRow(
                        trackResult: trackResult,
                        recording: recording,
                        releaseGroup: recording.releaseGroups[i],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcoustIDReleaseGroupRow({
    required AcoustIDResult trackResult,
    required AcoustIDRecording recording,
    required AcoustIDReleaseGroup releaseGroup,
  }) {
    final expanded = _expandedReleaseGroupIds.contains(releaseGroup.id);
    final hasReleases = releaseGroup.releases.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(12),
                ),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Image.network(
                    releaseGroup.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.white.withValues(alpha: 0.04),
                      child: const Icon(
                        Icons.album_rounded,
                        color: Colors.white24,
                        size: 22,
                      ),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _isApplying
                      ? null
                      : () => _applyAcoustIDReleaseGroup(
                          trackResult,
                          recording,
                          releaseGroup,
                        ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          releaseGroup.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (releaseGroup.type != null &&
                                releaseGroup.type!.isNotEmpty)
                              releaseGroup.type!,
                            if (releaseGroup.secondaryTypes.isNotEmpty)
                              releaseGroup.secondaryTypes.join('/'),
                            '${releaseGroup.releases.length} 个发行版',
                          ].where((item) => item.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: hasReleases
                    ? () {
                        setState(() {
                          if (expanded) {
                            _expandedReleaseGroupIds.remove(releaseGroup.id);
                          } else {
                            _expandedReleaseGroupIds.add(releaseGroup.id);
                          }
                        });
                      }
                    : null,
                icon: AnimatedRotation(
                  turns: expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: hasReleases
                        ? Colors.white.withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded && hasReleases
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      children: [
                        for (var i = 0; i < releaseGroup.releases.length; i++)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                            child: _buildAcoustIDReleaseRow(
                              trackResult: trackResult,
                              recording: recording,
                              releaseGroup: releaseGroup,
                              release: releaseGroup.releases[i],
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildAcoustIDReleaseRow({
    required AcoustIDResult trackResult,
    required AcoustIDRecording recording,
    required AcoustIDReleaseGroup releaseGroup,
    required AcoustIDRelease release,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _isApplying
            ? null
            : () => _applyAcoustIDRelease(
                trackResult,
                recording,
                releaseGroup,
                release,
              ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Image.network(
                    release.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child: const Icon(
                        Icons.album_outlined,
                        color: Colors.white24,
                        size: 20,
                      ),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      release.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (release.country != null &&
                            release.country!.isNotEmpty)
                          release.country!,
                        if (release.dateLabel != null &&
                            release.dateLabel!.isNotEmpty)
                          release.dateLabel!,
                        if (release.trackCount != null)
                          '${release.trackCount} 首',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    _buildHeader(context),
                    _buildSummary(context),
                    const SizedBox(height: 14),
                    Expanded(child: _buildBody(context)),
                  ],
                ),
                if (_isApplying)
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

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 90
        ? const Color(0xFF46D27A)
        : score >= 75
        ? const Color(0xFFFFC94D)
        : const Color(0xFF6EA8FF);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$score',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        '$label: $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.8),
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Colors.white.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _MatchCoverImage extends StatefulWidget {
  const _MatchCoverImage({required this.match, required this.service});

  final MusicBrainzTrackMatch match;
  final MusicBrainzTagCompletionService service;

  @override
  State<_MatchCoverImage> createState() => _MatchCoverImageState();
}

class _MatchCoverImageState extends State<_MatchCoverImage> {
  bool _isResolving = false;
  bool _hasResolved = false;

  @override
  void initState() {
    super.initState();
    if (widget.match.resolvedCover == null) {
      _resolve();
    } else {
      _hasResolved = true;
    }
  }

  Future<void> _resolve() async {
    if (_isResolving) return;
    if (!mounted) return;
    setState(() => _isResolving = true);
    try {
      await widget.service.resolveCover(widget.match);
      if (mounted) {
        setState(() {
          _isResolving = false;
          _hasResolved = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResolving = false;
          _hasResolved = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasResolved) {
      return Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.white.withValues(alpha: 0.15),
            ),
          ),
        ),
      );
    }

    final resolvedCover = widget.match.resolvedCover;
    if (resolvedCover != null && resolvedCover.thumbnailUrl != null) {
      final url = resolvedCover.thumbnailUrl!;
      return Image.network(
        url,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.music_note_rounded,
          color: Colors.white24,
          size: 24,
        ),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withValues(alpha: 0.15),
                ),
              ),
            ),
          );
        },
      );
    }

    return const Icon(
      Icons.music_note_rounded,
      color: Colors.white24,
      size: 24,
    );
  }
}

class _AcoustIDCoverImage extends StatelessWidget {
  const _AcoustIDCoverImage({required this.result});

  final AcoustIDResult result;

  @override
  Widget build(BuildContext context) {
    final url = result.thumbnailUrl;
    if (url == null) {
      return const Center(
        child: Icon(
          Icons.fingerprint_rounded,
          color: Color(0xFF46D27A),
          size: 28,
        ),
      );
    }

    return Center(
      child: Image.network(
        url,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.fingerprint_rounded,
          color: Color(0xFF46D27A),
          size: 28,
        ),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  const Color(0xFF46D27A).withValues(alpha: 0.5),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
