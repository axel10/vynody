import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/artist_summary.dart';
import '../player/metadata/theaudiodb_artist_service.dart';
import 'artist_avatar.dart';
import 'artist_context_menu.dart';
import 'folder_layout_utils.dart';
import 'remote_media_badge.dart';

/// 艺术家条目，随档位在「列表（左侧头像）」与「网格（居中大头像）」之间连续平滑变形。
class ArtistZoomItem extends ConsumerStatefulWidget {
  const ArtistZoomItem({
    super.key,
    required this.artist,
    required this.metrics,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.onToggleSelect,
    this.onMultiSelect,
  });

  final ArtistSummary artist;
  final FolderZoomLayoutMetrics metrics;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final VoidCallback? onToggleSelect;
  final void Function(String artistKey)? onMultiSelect;

  @override
  ConsumerState<ArtistZoomItem> createState() => _ArtistZoomItemState();
}

class _ArtistZoomItemState extends ConsumerState<ArtistZoomItem> {
  String? _cachedImagePath;
  StreamSubscription<String>? _imageSub;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _cachedImagePath = widget.artist.cachedImagePath;
    _imageSub = TheAudioDbArtistService.instance.onArtistImageUpdated
        .listen((queryKey) {
      if (queryKey == widget.artist.queryKey && mounted) {
        _refreshImage();
      }
    });
    _scheduleFetchIfNeeded();
  }

  void _scheduleFetchIfNeeded() {
    if (_cachedImagePath != null &&
        _cachedImagePath!.isNotEmpty &&
        File(_cachedImagePath!).existsSync()) {
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      TheAudioDbArtistService.instance
          .fetchAndCacheArtistImage(widget.artist)
          .then((path) {
        if (!mounted) return;
        if (path != null && path.isNotEmpty && path != _cachedImagePath) {
          setState(() {
            _cachedImagePath = path;
          });
        }
      });
    });
  }

  Future<void> _refreshImage() async {
    final path = await TheAudioDbArtistService.instance
        .fetchAndCacheArtistImage(widget.artist);
    if (!mounted) return;
    if (path != null && path.isNotEmpty && path != _cachedImagePath) {
      setState(() {
        _cachedImagePath = path;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ArtistZoomItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.artist.queryKey != oldWidget.artist.queryKey) {
      _cachedImagePath = widget.artist.cachedImagePath;
      _scheduleFetchIfNeeded();
    } else if (widget.artist.cachedImagePath != null &&
        widget.artist.cachedImagePath != _cachedImagePath) {
      _cachedImagePath = widget.artist.cachedImagePath;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _imageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final artist = widget.artist;
    final metrics = widget.metrics;
    final gridMorph = metrics.gridMorph;
    final isSelected = widget.isSelected;

    final displayImagePath = _cachedImagePath ?? artist.cachedImagePath;

    final songCountLabel = l10n.songCount(artist.songCount);
    final subtitleParts = <String>[
      songCountLabel,
      if (artist.hasDistinctCanonicalName) artist.canonicalName!.trim(),
      if ((artist.country?.trim().isNotEmpty ?? false)) artist.country!.trim(),
    ];
    if (artist.disambiguation?.trim().isNotEmpty ?? false) {
      subtitleParts.add(artist.disambiguation!.trim());
    }

    final avatar = LayoutBuilder(
      builder: (context, constraints) {
        final size =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 48.0;
        return ArtistAvatar(
          diameter: size,
          imagePath: displayImagePath,
          imageUrl: artist.imageUrl,
        );
      },
    );

    final cover = ZoomItemCover(
      metrics: metrics,
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      isCircle: true,
      centerCheckboxInGrid: true,
      selectionOverlayColor: Colors.black38,
      onToggleSelect: (widget.onToggleSelect ?? widget.onTap),
      child: avatar,
    );

    final titleColor = widget.isSelectionMode && isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    final listCoverSize = getFolderListCoverSize(metrics.animatedZoomScale);
    final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
    final selectionOffset = (widget.isSelectionMode && gridMorph < 0.5)
        ? (28.0 * (1.0 - coverProgress))
        : 0.0;

    final fallbackCheckbox = Checkbox(
      value: isSelected,
      onChanged: (_) => (widget.onToggleSelect ?? widget.onTap)?.call(),
      fillColor: WidgetStateProperty.all(Colors.white),
      checkColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    );

    return ZoomItemScaffold(
      metrics: metrics,
      cover: cover,
      titleText: artist.name,
      subtitleText: subtitleParts.join(' · '),
      titleSuffix: RemoteMediaBadge.pillTrailing(
        songs: artist.songs,
        title: artist.name,
      ),
      gridAlignment: Alignment.topCenter,
      gridCrossAxisAlignment: CrossAxisAlignment.center,
      titleColor: titleColor,
      listTitleFontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      listTitleFontSize: 13.5,
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      selectionOffset: selectionOffset,
      fallbackLeadingWhenNoCover: widget.isSelectionMode && gridMorph < 0.5
          ? fallbackCheckbox
          : null,
      onTap: widget.onTap,
      onLongPress: () {
        if (widget.onLongPress != null) {
          widget.onLongPress!();
        } else if (!widget.isSelectionMode) {
          showArtistBottomSheet(
            context: context,
            ref: ref,
            artist: artist,
            onMultiSelect: widget.onMultiSelect,
          );
        }
      },
      onSecondaryTapDown: (details) {
        if (widget.onSecondaryTapDown != null) {
          widget.onSecondaryTapDown!(details);
        } else if (!widget.isSelectionMode) {
          showArtistContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            ref: ref,
            artist: artist,
            onMultiSelect: widget.onMultiSelect,
            showViewDetails: false,
          );
        }
      },
    );
  }
}
