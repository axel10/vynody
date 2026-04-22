import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../l10n/app_localizations.dart';
import '../models/artist_summary.dart';
import '../player/artist_library.dart';
import '../player/audio_riverpod.dart';
import 'artist_detail_page.dart';

class ArtistsTab extends ConsumerStatefulWidget {
  const ArtistsTab({super.key});

  @override
  ConsumerState<ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends ConsumerState<ArtistsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artistsAsync = ref.watch(artistLibraryProvider);
    final l10n = AppLocalizations.of(context)!;

    return artistsAsync.when(
      loading: () => const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
      data: (artists) {
        final visibleArtists = _filterArtists(artists);

        return LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = switch (constraints.maxWidth) {
              >= 1200 => 5,
              >= 900 => 4,
              >= 700 => 3,
              _ => 2,
            };

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _ArtistsToolbar(
                    searchController: _searchController,
                    searchQuery: _searchQuery,
                    artistCount: visibleArtists.length,
                    onSearchChanged: (value) {
                      setState(() {
                        _searchQuery = value.trim();
                      });
                    },
                    onSearchCleared: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  ),
                ),
                if (visibleArtists.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        l10n.noArtists,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.72,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _ArtistCard(artist: visibleArtists[index]),
                        childCount: visibleArtists.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ],
            );
          },
        );
      },
    );
  }

  List<ArtistSummary> _filterArtists(List<ArtistSummary> artists) {
    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) {
      return artists.toList(growable: false);
    }

    return artists
        .where(
          (artist) =>
              artist.name.toLowerCase().contains(query) ||
              artist.disambiguation?.toLowerCase().contains(query) == true ||
              artist.country?.toLowerCase().contains(query) == true ||
              artist.tags.any((tag) => tag.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }
}

class _ArtistCard extends ConsumerWidget {
  const _ArtistCard({required this.artist});

  final ArtistSummary artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final audio = ref.read(audioServiceProvider);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) {
          _showArtistContextMenu(context, ref, details.globalPosition);
        },
        onLongPressStart: (details) {
          _showArtistContextMenu(context, ref, details.globalPosition);
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _openArtistDetail(context),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
                  theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                ],
              ),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Hero(
                      tag: 'artist-cover-${artist.queryKey}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _ArtistCover(artist: artist),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    artist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _artistSubtitle(artist),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.songCount(artist.songCount),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.playAll,
                        onPressed: () => audio.playPlaylist(artist.songs),
                        icon: const Icon(Icons.play_arrow),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openArtistDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ArtistDetailPage(artist: artist)),
    );
  }

  Future<void> _showArtistContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'play_all', child: Text(l10n.playAll)),
        PopupMenuItem(value: 'shuffle', child: Text(l10n.shufflePlay)),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'view_details',
          child: Text(l10n.viewArtistDetails),
        ),
        PopupMenuItem(value: 'copy_artist', child: Text(l10n.copyArtistName)),
      ],
    );

    if (!context.mounted || selected == null) return;

    switch (selected) {
      case 'play_all':
        await ref.read(audioServiceProvider).playPlaylist(artist.songs);
        break;
      case 'shuffle':
        await ref
            .read(audioServiceProvider)
            .playPlaylist(List.of(artist.songs)..shuffle());
        break;
      case 'view_details':
        _openArtistDetail(context);
        break;
      case 'copy_artist':
        await Clipboard.setData(ClipboardData(text: artist.name));
        break;
    }
  }
}

class _ArtistCover extends StatelessWidget {
  const _ArtistCover({required this.artist});

  final ArtistSummary artist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imageUrl = artist.imageUrl?.trim();
    if (imageUrl == null || imageUrl.isEmpty) {
      return _fallback(theme);
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _fallback(theme),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _CoverShimmer(
          baseColor: colorScheme.surfaceContainerHighest,
          highlightColor: colorScheme.surfaceContainerLow,
        );
      },
    );
  }

  Widget _fallback(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
            theme.colorScheme.secondaryContainer.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Icon(
        Icons.person_rounded,
        size: 54,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class _CoverShimmer extends StatelessWidget {
  const _CoverShimmer({required this.baseColor, required this.highlightColor});

  final Color baseColor;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        decoration: BoxDecoration(
          color: baseColor,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [baseColor, highlightColor],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: baseColor.withValues(alpha: 0.85)),
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: highlightColor.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistsToolbar extends StatelessWidget {
  const _ArtistsToolbar({
    required this.searchController,
    required this.searchQuery,
    required this.artistCount,
    required this.onSearchChanged,
    required this.onSearchCleared,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final int artistCount;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.artists,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.songCount(artistCount),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: l10n.searchArtists,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchQuery.isEmpty
                  ? null
                  : IconButton(
                      onPressed: onSearchCleared,
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _artistSubtitle(ArtistSummary artist) {
  final parts = <String>[];
  if (artist.disambiguation != null &&
      artist.disambiguation!.trim().isNotEmpty) {
    parts.add(artist.disambiguation!.trim());
  }
  if (artist.country != null && artist.country!.trim().isNotEmpty) {
    parts.add(artist.country!.trim());
  }
  if (artist.beginDate != null && artist.beginDate!.trim().isNotEmpty) {
    parts.add(artist.beginDate!.trim());
  }
  if (parts.isEmpty) {
    return 'MusicBrainz';
  }
  return parts.join(' · ');
}
