import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/player/metadata/musicbrainz_tag_completion_service.dart';
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
    required this.onToggleExpanded,
    required this.onApplyRelease,
  });

  final MusicBrainzTrackMatch match;
  final int index;
  final String displayTitle;
  final MusicBrainzTagCompletionService service;
  final bool isApplying;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final void Function(
    MusicBrainzTrackMatch match,
    MusicBrainzReleaseMatch release,
  )
  onApplyRelease;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final releaseCount = match.releases.length;
    final hasReleases = releaseCount > 0;
    final durationText = match.durationLabel;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: isDark ? Colors.white.withValues(alpha: 0.045) : Colors.black.withValues(alpha: 0.03),
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
                            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
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
                            style: TextStyle(
                              color: isDark ? Colors.white : theme.colorScheme.onSurface,
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
                              color: isDark ? Colors.white.withValues(alpha: 0.7) : theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              durationText,
                              l10n.releaseCountLabel(releaseCount),
                              l10n.scoreLabel(match.score),
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? Colors.white.withValues(alpha: 0.45) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
                            hasReleases
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.remove_rounded,
                            color: hasReleases
                                ? (isDark ? Colors.white.withValues(alpha: 0.45) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6))
                                : (isDark ? Colors.white.withValues(alpha: 0.2) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
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
                      child: hasReleases
                          ? Column(
                              children: [
                                for (var i = 0; i < match.releases.length; i++)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: i == 0 ? 0 : 8,
                                    ),
                                    child: SongTagMusicBrainzReleaseItem(
                                      match: match,
                                      release: match.releases[i],
                                      isApplying: isApplying,
                                      onApplyRelease: onApplyRelease,
                                    ),
                                  ),
                              ],
                            )
                          : Text(
                              l10n.noExpandableReleases,
                              style: TextStyle(
                                color: isDark ? Colors.white.withValues(alpha: 0.42) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
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
                  child: ProxyNetworkImage(
                    url: release.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                      child: Icon(
                        Icons.album_outlined,
                        color: isDark ? Colors.white24 : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
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
                        color: isDark ? Colors.white.withValues(alpha: 0.5) : theme.colorScheme.onSurfaceVariant,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.white.withValues(alpha: 0.3) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
