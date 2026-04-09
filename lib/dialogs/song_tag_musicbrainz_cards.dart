import 'package:flutter/material.dart';

import '../player/musicbrainz_tag_completion_service.dart';
import 'song_tag_completion_widgets.dart';

class SongTagMusicBrainzRecordingCard extends StatelessWidget {
  const SongTagMusicBrainzRecordingCard({
    super.key,
    required this.match,
    required this.index,
    required this.displayTitle,
    required this.service,
    required this.isApplying,
    required this.isExpanded,
    required this.releaseGroups,
    required this.isReleaseGroupExpanded,
    required this.onToggleExpanded,
    required this.onToggleReleaseGroupExpanded,
    required this.onApplyRelease,
  });

  final MusicBrainzTrackMatch match;
  final int index;
  final String displayTitle;
  final MusicBrainzTagCompletionService service;
  final bool isApplying;
  final bool isExpanded;
  final List<MusicBrainzReleaseGroup> releaseGroups;
  final bool Function(String groupKey) isReleaseGroupExpanded;
  final VoidCallback onToggleExpanded;
  final void Function(String groupKey) onToggleReleaseGroupExpanded;
  final void Function(
    MusicBrainzTrackMatch match,
    MusicBrainzReleaseMatch release,
  )
  onApplyRelease;

  @override
  Widget build(BuildContext context) {
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
              onTap: isApplying ? null : onToggleExpanded,
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
                          child: SongTagMatchCoverImage(
                            match: match,
                            service: service,
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
                            match.title.isNotEmpty ? match.title : displayTitle,
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
                        SongTagScoreBadge(score: match.score),
                        const SizedBox(height: 10),
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0.0,
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
              child: isExpanded
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
                                    child: SongTagMusicBrainzReleaseGroupRow(
                                      match: match,
                                      releaseGroup: releaseGroups[i],
                                      isExpanded: isReleaseGroupExpanded(
                                        _groupKey(match, releaseGroups[i]),
                                      ),
                                      isApplying: isApplying,
                                      onToggleExpanded: () =>
                                          onToggleReleaseGroupExpanded(
                                            _groupKey(match, releaseGroups[i]),
                                          ),
                                      onApplyRelease: onApplyRelease,
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
}

class SongTagMusicBrainzReleaseGroupRow extends StatelessWidget {
  const SongTagMusicBrainzReleaseGroupRow({
    super.key,
    required this.match,
    required this.releaseGroup,
    required this.isExpanded,
    required this.isApplying,
    required this.onToggleExpanded,
    required this.onApplyRelease,
  });

  final MusicBrainzTrackMatch match;
  final MusicBrainzReleaseGroup releaseGroup;
  final bool isExpanded;
  final bool isApplying;
  final VoidCallback onToggleExpanded;
  final void Function(
    MusicBrainzTrackMatch match,
    MusicBrainzReleaseMatch release,
  )
  onApplyRelease;

  @override
  Widget build(BuildContext context) {
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
            onTap: isApplying ? null : onToggleExpanded,
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
                    turns: isExpanded ? 0.5 : 0.0,
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
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: Column(
                      children: [
                        for (var i = 0; i < releaseGroup.releases.length; i++)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                            child: SongTagMusicBrainzReleaseItem(
                              match: match,
                              release: releaseGroup.releases[i],
                              isApplying: isApplying,
                              onApplyRelease: onApplyRelease,
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
}

class SongTagMusicBrainzReleaseItem extends StatelessWidget {
  const SongTagMusicBrainzReleaseItem({
    super.key,
    required this.match,
    required this.release,
    required this.isApplying,
    required this.onApplyRelease,
  });

  final MusicBrainzTrackMatch match;
  final MusicBrainzReleaseMatch release;
  final bool isApplying;
  final void Function(
    MusicBrainzTrackMatch match,
    MusicBrainzReleaseMatch release,
  )
  onApplyRelease;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: isApplying ? null : () => onApplyRelease(match, release),
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
}

String _groupKey(MusicBrainzTrackMatch match, MusicBrainzReleaseGroup group) {
  return '${match.recordingId}::${group.key}';
}
