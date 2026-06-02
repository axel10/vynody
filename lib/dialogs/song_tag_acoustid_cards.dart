import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/player/metadata/acoustid_service.dart';
import 'song_tag_completion_widgets.dart';

class SongTagAcoustIDResultCard extends StatelessWidget {
  const SongTagAcoustIDResultCard({
    super.key,
    required this.result,
    required this.index,
    required this.displayTitle,
    required this.isApplying,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.isReleaseGroupExpanded,
    required this.onToggleReleaseGroupExpanded,
    required this.onApplyReleaseGroup,
    required this.onApplyRelease,
  });

  final AcoustIDResult result;
  final int index;
  final String displayTitle;
  final bool isApplying;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final bool Function(String releaseGroupId) isReleaseGroupExpanded;
  final void Function(String releaseGroupId) onToggleReleaseGroupExpanded;
  final void Function(
    AcoustIDResult trackResult,
    AcoustIDRecording recording,
    AcoustIDReleaseGroup releaseGroup,
  )
  onApplyReleaseGroup;
  final void Function(
    AcoustIDResult trackResult,
    AcoustIDRecording recording,
    AcoustIDReleaseGroup releaseGroup,
    AcoustIDRelease release,
  )
  onApplyRelease;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: isDark
            ? const Color(0xFF46D27A).withValues(alpha: 0.1)
            : const Color(0xFF46D27A).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: isApplying ? null : onToggleExpanded,
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
                        color: isDark
                            ? const Color(0xFF46D27A).withValues(alpha: 0.2)
                            : const Color(0xFF46D27A).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SongTagAcoustIDCoverImage(result: result),
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
                                      : displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : theme.colorScheme.onSurface,
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
                                  color: isDark
                                      ? const Color(0xFF46D27A).withValues(alpha: 0.2)
                                      : const Color(0xFF1E824C).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF46D27A).withValues(alpha: 0.4)
                                        : const Color(0xFF1E824C).withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  'AcoustID',
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF46D27A) : const Color(0xFF1E824C),
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
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              l10n.recordingCountLabel(
                                result.recordings.length,
                              ),
                              result.durationLabel,
                              l10n.matchScoreLabel(
                                (result.score * 100).round(),
                              ),
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.45)
                                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: isDark
                          ? const Color(0xFF46D27A).withValues(alpha: 0.6)
                          : const Color(0xFF1E824C).withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: isExpanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: Column(
                          children: [
                            for (var i = 0; i < result.recordings.length; i++)
                              Padding(
                                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                                child: SongTagAcoustIDRecordingBlock(
                                  trackResult: result,
                                  recording: result.recordings[i],
                                  recordingIndex: i,
                                  isApplying: isApplying,
                                  isReleaseGroupExpanded:
                                      isReleaseGroupExpanded,
                                  onToggleReleaseGroupExpanded:
                                      onToggleReleaseGroupExpanded,
                                  onApplyReleaseGroup: onApplyReleaseGroup,
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
        ),
      ),
    );
  }
}

class SongTagAcoustIDRecordingBlock extends StatelessWidget {
  const SongTagAcoustIDRecordingBlock({
    super.key,
    required this.trackResult,
    required this.recording,
    required this.recordingIndex,
    required this.isApplying,
    required this.isReleaseGroupExpanded,
    required this.onToggleReleaseGroupExpanded,
    required this.onApplyReleaseGroup,
    required this.onApplyRelease,
  });

  final AcoustIDResult trackResult;
  final AcoustIDRecording recording;
  final int recordingIndex;
  final bool isApplying;
  final bool Function(String releaseGroupId) isReleaseGroupExpanded;
  final void Function(String releaseGroupId) onToggleReleaseGroupExpanded;
  final void Function(
    AcoustIDResult trackResult,
    AcoustIDRecording recording,
    AcoustIDReleaseGroup releaseGroup,
  )
  onApplyReleaseGroup;
  final void Function(
    AcoustIDResult trackResult,
    AcoustIDRecording recording,
    AcoustIDReleaseGroup releaseGroup,
    AcoustIDRelease release,
  )
  onApplyRelease;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
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
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${recordingIndex + 1}',
                    style: TextStyle(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.75)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.8),
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
                        style: TextStyle(
                          color: isDark ? Colors.white : theme.colorScheme.onSurface,
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
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.55)
                              : theme.colorScheme.onSurfaceVariant,
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
                l10n.noExpandableReleaseGroups,
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.42)
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              )
            else
              Column(
                children: [
                  for (var i = 0; i < recording.releaseGroups.length; i++)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                      child: SongTagAcoustIDReleaseGroupRow(
                        trackResult: trackResult,
                        recording: recording,
                        releaseGroup: recording.releaseGroups[i],
                        isExpanded: isReleaseGroupExpanded(
                          recording.releaseGroups[i].id,
                        ),
                        isApplying: isApplying,
                        onToggleExpanded: () => onToggleReleaseGroupExpanded(
                          recording.releaseGroups[i].id,
                        ),
                        onApplyReleaseGroup: onApplyReleaseGroup,
                        onApplyRelease: onApplyRelease,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class SongTagAcoustIDReleaseGroupRow extends StatelessWidget {
  const SongTagAcoustIDReleaseGroupRow({
    super.key,
    required this.trackResult,
    required this.recording,
    required this.releaseGroup,
    required this.isExpanded,
    required this.isApplying,
    required this.onToggleExpanded,
    required this.onApplyReleaseGroup,
    required this.onApplyRelease,
  });

  final AcoustIDResult trackResult;
  final AcoustIDRecording recording;
  final AcoustIDReleaseGroup releaseGroup;
  final bool isExpanded;
  final bool isApplying;
  final VoidCallback onToggleExpanded;
  final void Function(
    AcoustIDResult trackResult,
    AcoustIDRecording recording,
    AcoustIDReleaseGroup releaseGroup,
  )
  onApplyReleaseGroup;
  final void Function(
    AcoustIDResult trackResult,
    AcoustIDRecording recording,
    AcoustIDReleaseGroup releaseGroup,
    AcoustIDRelease release,
  )
  onApplyRelease;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasReleases = releaseGroup.releases.isNotEmpty;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
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
                  child: ProxyNetworkImage(
                    url: releaseGroup.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      child: Icon(
                        Icons.album_rounded,
                        color: isDark
                            ? Colors.white24
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: isApplying
                      ? null
                      : () => onApplyReleaseGroup(
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
                          style: TextStyle(
                            color: isDark ? Colors.white : theme.colorScheme.onSurface,
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
                            l10n.releaseCountLabel(
                              releaseGroup.releases.length,
                            ),
                          ].where((item) => item.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.55)
                                : theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: hasReleases ? onToggleExpanded : null,
                icon: AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: hasReleases
                        ? (isDark
                            ? Colors.white.withValues(alpha: 0.7)
                            : theme.colorScheme.onSurfaceVariant)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.2)
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: isExpanded && hasReleases
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      children: [
                        for (var i = 0; i < releaseGroup.releases.length; i++)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                            child: SongTagAcoustIDReleaseRow(
                              trackResult: trackResult,
                              recording: recording,
                              releaseGroup: releaseGroup,
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

class SongTagAcoustIDReleaseRow extends StatelessWidget {
  const SongTagAcoustIDReleaseRow({
    super.key,
    required this.trackResult,
    required this.recording,
    required this.releaseGroup,
    required this.release,
    required this.isApplying,
    required this.onApplyRelease,
  });

  final AcoustIDResult trackResult;
  final AcoustIDRecording recording;
  final AcoustIDReleaseGroup releaseGroup;
  final AcoustIDRelease release;
  final bool isApplying;
  final void Function(
    AcoustIDResult trackResult,
    AcoustIDRecording recording,
    AcoustIDReleaseGroup releaseGroup,
    AcoustIDRelease release,
  )
  onApplyRelease;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.02),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isApplying
            ? null
            : () =>
                  onApplyRelease(trackResult, recording, releaseGroup, release),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: ProxyNetworkImage(
                    url: release.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.03),
                      child: Icon(
                        Icons.album_outlined,
                        color: isDark
                            ? Colors.white24
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        size: 20,
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
                      style: TextStyle(
                        color: isDark ? Colors.white : theme.colorScheme.onSurface,
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
                          l10n.trackCountShort(release.trackCount!),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.5)
                            : theme.colorScheme.onSurfaceVariant,
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
}
