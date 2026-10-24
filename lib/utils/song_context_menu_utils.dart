import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/utils/time_format_utils.dart';

import '../dialogs/add_to_playlist_dialog.dart';
import '../dialogs/song_tag_edit_dialog.dart';
import '../dialogs/transcode_dialog.dart';
import '../dialogs/song_details_dialog.dart';
import '../l10n/app_localizations.dart';
import 'package:oktoast/oktoast.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/lyrics/lyrics_riverpod.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/file_selector_helper.dart';
import 'package:vynody/utils/lrc_utils.dart';
import 'package:vynody/utils/language_code_utils.dart';
import 'package:vynody/widgets/song_thumbnail.dart';
import 'package:vynody/widgets/app_context_menu.dart';
import 'package:vynody/utils/app_snack_bar.dart';

enum SongContextMenuMode { full, title, artistAlbum }

bool isVisibleSongText(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  return lower != 'unknown' &&
      lower != 'unknown artist' &&
      lower != 'unknown album';
}

Future<void> openSongFileLocation(String filePath) async {
  if (filePath.trim().isEmpty) return;

  final normalizedPath = File(filePath).absolute.path;
  if (!File(normalizedPath).existsSync()) {
    debugPrint(
      '[SongContextMenu] Cannot open file location, file missing: $normalizedPath',
    );
    return;
  }

  try {
    if (Platform.isWindows) {
      final cmd = 'explorer.exe /select,"$normalizedPath"';
      // windows上只能用Process.run(cmd, [])这种方式打开，不要尝试修改
      await Process.run(cmd, []);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', normalizedPath]);
    } else if (Platform.isLinux) {
      final parentDir = File(normalizedPath).parent.path;

      final launchers = <List<String>>[
        ['nautilus', '--select', normalizedPath],
        ['dolphin', '--select', normalizedPath],
        ['nemo', '--no-desktop', normalizedPath],
        ['thunar', parentDir],
        ['xdg-open', parentDir],
      ];

      for (final launcher in launchers) {
        try {
          final result = await Process.run(
            launcher.first,
            launcher.skip(1).toList(growable: false),
          );
          if (result.exitCode == 0) {
            return;
          }
        } catch (_) {
          // Try the next file manager command.
        }
      }
    }
  } catch (e) {
    debugPrint('[SongContextMenu] Failed to open file location: $e');
  }
}

Future<void> openFolderLocation(String folderPath) async {
  if (folderPath.trim().isEmpty) return;

  final normalizedPath = Directory(folderPath).absolute.path;
  if (!Directory(normalizedPath).existsSync()) {
    debugPrint(
      '[FolderContextMenu] Cannot open folder location, folder missing: $normalizedPath',
    );
    return;
  }

  try {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [normalizedPath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [normalizedPath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [normalizedPath]);
    }
  } catch (e) {
    debugPrint('[FolderContextMenu] Failed to open folder location: $e');
  }
}

Future<void> importLyricsForSong(
  BuildContext context,
  WidgetRef ref,
  MusicFile song,
) async {
  await importLyricsForSongWithContainer(context, ref.container, song);
}

Future<void> importLyricsForSongWithContainer(
  BuildContext context,
  ProviderContainer container,
  MusicFile song,
) async {
  final l10n = AppLocalizations.of(context)!;

  try {
    final filePath = await FileSelectorHelper.pickFile(
      label: l10n.importLyrics,
      extensions: ['lrc', 'txt'],
    );
    if (filePath == null || filePath.trim().isEmpty) return;
    if (!context.mounted) return;

    final file = File(filePath);
    if (!await file.exists()) {
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        null,
        SnackBar(content: Text(l10n.importLyricsFailed)),
      );
      return;
    }

    String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      try {
        final bytes = await file.readAsBytes();
        content = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        if (!context.mounted) return;
        AppSnackBar.show(
          context,
          null,
          SnackBar(content: Text(l10n.importLyricsFailed)),
        );
        return;
      }
    }

    final normalizedText = content.replaceAll('\r\n', '\n').trim();
    if (normalizedText.isEmpty) {
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        null,
        SnackBar(content: Text(l10n.emptyLyricsFile)),
      );
      return;
    }

    final lyricsController = container.read(lyricsControllerProvider.notifier);
    final lyricsCacheRepo = container.read(lyricsCacheRepositoryProvider);

    final query = await lyricsController.buildLyricsQueryForSong(song) ??
        LyricsQuery(
          filePath: song.path,
          fileName: song.name,
          title: song.title?.trim().isNotEmpty == true
              ? song.title!.trim()
              : song.name,
          artist: song.artist?.trim() ?? '',
          album: song.album?.trim() ?? '',
          duration: song.durationMillis != null
              ? Duration(milliseconds: song.durationMillis!)
              : Duration.zero,
        );
    final cacheKey = query.cacheKey;

    final parsedResult = LrcUtils.parseLyricsWithTranslation(normalizedText);
    final isSynced = parsedResult.syncedLines.isNotEmpty;

    final cacheRecord = LyricsCacheRecord(
      cacheKey: cacheKey,
      source: LyricsCacheSource.manualAdjust,
      isSynced: isSynced,
      syncedLyrics: normalizedText,
      syncedLines: parsedResult.syncedLines,
      timelineOffsetMillis: 0,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    if (cacheKey.isNotEmpty) {
      await lyricsCacheRepo.clearLyricsCacheByKey(cacheKey);
    }
    await lyricsCacheRepo.saveLyricsCache(cacheRecord);

    if (parsedResult.hasTranslation) {
      final preferredLang = LanguageCodeUtils.currentAppLanguageCode();
      final langCode = preferredLang.isNotEmpty ? preferredLang : 'zh';
      await lyricsCacheRepo.saveLyricsTranslationCache(
        LyricsTranslationCacheRecord(
          cacheKey: cacheKey,
          languageCode: langCode,
          translatedText: parsedResult.translatedLines!.join('\n'),
          translatedLines: parsedResult.translatedLines!,
          provider: 'imported_lrc',
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    // If the imported song is currently playing, update lyricsController
    final currentMusic = container.read(audioCurrentMusicProvider);
    if (currentMusic != null && currentMusic.path == song.path) {
      await container.read(lyricsControllerProvider.notifier).fillLyricsForCurrentSong(
        normalizedText,
        source: LyricsCacheSource.manualAdjust,
      );
    }

    // Save to external companion .lrc file if configured in settings and local file
    final settings = container.read(settingsServiceProvider);
    final isRemote = RemoteMediaResolver.isRemoteUri(song.path);
    if (settings.lyricsSaveMethod == LyricsSaveMethod.lrcFile && !isRemote) {
      try {
        await MetadataHelper.saveLyricsToExternalLrc(song.path, normalizedText);
      } catch (e) {
        debugPrint('[ImportLyrics] Failed to save external .lrc file: $e');
      }
    }

    if (!context.mounted) return;
    AppSnackBar.show(
      context,
      null,
      SnackBar(content: Text(l10n.importLyricsSuccess)),
    );
  } catch (e) {
    debugPrint('[ImportLyrics] Error importing lyrics: $e');
    if (context.mounted) {
      AppSnackBar.show(
        context,
        null,
        SnackBar(content: Text(l10n.importLyricsFailed)),
      );
    }
  }
}

String _getRemoveFromQueueLabel(BuildContext context) {
  return AppLocalizations.of(context)!.removeFromQueue;
}

String _getRemoveFromPlaylistLabel(BuildContext context) {
  return AppLocalizations.of(context)!.removeFromPlaylist;
}

Future<void> showSongContextMenu(
  BuildContext context,
  Offset globalPosition, {
  required MusicFile? song,
  List<MusicFile>? songs,
  SongContextMenuMode mode = SongContextMenuMode.full,
  Future<void> Function()? onAddToPlaylist,
  VoidCallback? onPlayNext,
  VoidCallback? onAddToQueue,
  VoidCallback? onRemoveFromQueue,
  VoidCallback? onRemoveFromPlaylist,
  VoidCallback? onDownload,
  VoidCallback? onImportLyrics,
  VoidCallback? onEditTags,
  /// 传了才显示「多选」这一项。只有列表里的曲目行才该传：播放页标题、
  /// 队列面板里的复制入口不给（那里没有选择态）。
  VoidCallback? onMultiSelect,
}) async {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await showSongBottomSheet(
      context,
      song: song,
      songs: songs,
      mode: mode,
      onAddToPlaylist: onAddToPlaylist,
      onPlayNext: onPlayNext,
      onAddToQueue: onAddToQueue,
      onRemoveFromQueue: onRemoveFromQueue,
      onRemoveFromPlaylist: onRemoveFromPlaylist,
      onDownload: onDownload,
      onImportLyrics: onImportLyrics,
      onEditTags: onEditTags,
      onMultiSelect: onMultiSelect,
    );
    return;
  }

  final l10n = AppLocalizations.of(context)!;

  final effectiveSongs = (songs != null && songs.isNotEmpty)
      ? songs
      : (song != null ? [song] : <MusicFile>[]);
  final isBatch = effectiveSongs.length > 1;
  final canEditTags = effectiveSongs.isNotEmpty &&
      effectiveSongs.any((s) => !RemoteMediaResolver.isRemoteUri(s.path));

  final titleText = song?.displayName.trim() ?? '';
  final artistText = song?.artist?.trim() ?? '';
  final albumText = song?.album?.trim() ?? '';
  final hasTitle = titleText.isNotEmpty;
  final hasArtist = isVisibleSongText(artistText);
  final hasAlbum = isVisibleSongText(albumText);
  final isRemoteSong = song != null && RemoteMediaResolver.isRemoteUri(song.path);
  final hasFilePath = song != null && song.path.trim().isNotEmpty;
  final canOpenLocation =
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
      hasFilePath &&
      !isRemoteSong;

  final items = <PopupMenuEntry<String>>[];

  // 1. Playback actions (Top)
  if (onPlayNext != null) {
    items.add(
      buildContextMenuItem<String>(
        value: 'play_next',
        label: l10n.playNext,
        icon: Icons.queue_play_next_rounded,
        context: context,
      ),
    );
  }
  if (onAddToQueue != null) {
    items.add(
      buildContextMenuItem<String>(
        value: 'add_to_queue',
        label: l10n.addToQueue,
        icon: Icons.queue_music_rounded,
        context: context,
      ),
    );
  }
  if (onDownload != null) {
    items.add(
      buildContextMenuItem<String>(
        value: 'download',
        label: l10n.download,
        icon: Icons.download_rounded,
        context: context,
      ),
    );
  }
  if (onRemoveFromQueue != null) {
    items.add(
      buildContextMenuItem<String>(
        value: 'remove_from_queue',
        label: _getRemoveFromQueueLabel(context),
        icon: Icons.playlist_remove_rounded,
        context: context,
      ),
    );
  }
  if (onRemoveFromPlaylist != null) {
    items.add(
      buildContextMenuItem<String>(
        value: 'remove_from_playlist',
        label: _getRemoveFromPlaylistLabel(context),
        icon: Icons.delete_outline_rounded,
        context: context,
      ),
    );
  }

  final hasPlaybackActions =
      onPlayNext != null ||
      onAddToQueue != null ||
      onDownload != null ||
      onRemoveFromQueue != null ||
      onRemoveFromPlaylist != null;

  final hasStandardActions =
      mode != SongContextMenuMode.full ||
      canOpenLocation ||
      hasTitle ||
      hasArtist ||
      hasAlbum ||
      song != null ||
      onAddToPlaylist != null;

  if (hasPlaybackActions && hasStandardActions) {
    items.add(const PopupMenuDivider());
  }

  // 2. Standard Metadata / File Actions
  switch (mode) {
    case SongContextMenuMode.full:
      items.addAll([
        if (canOpenLocation)
          buildContextMenuItem<String>(
            value: 'open_file_location',
            enabled: canOpenLocation,
            label: l10n.openFileLocation,
            icon: Icons.folder_open_rounded,
            context: context,
          ),
        buildContextMenuItem<String>(
          value: 'import_lyrics',
          enabled: song != null,
          label: l10n.importLyrics,
          icon: Icons.lyrics_outlined,
          context: context,
        ),
        buildContextMenuItem<String>(
          value: 'song_details',
          enabled: song != null,
          label: l10n.songProperties,
          icon: Icons.info_outline_rounded,
          context: context,
        ),
        buildContextMenuItem<String>(
          value: 'edit_tags',
          enabled: canEditTags,
          label: isBatch
              ? '${l10n.batchEditSongTagsTitle} (${effectiveSongs.length})'
              : l10n.editSongTagsTitle,
          icon: Icons.edit_note_rounded,
          context: context,
        ),
        const PopupMenuDivider(),
        buildContextMenuItem<String>(
          value: 'copy_title',
          enabled: hasTitle,
          label: l10n.copyTitle,
          icon: Icons.title_rounded,
          context: context,
        ),
        buildContextMenuItem<String>(
          value: 'copy_album',
          enabled: hasAlbum,
          label: l10n.copyAlbumTitle,
          icon: Icons.album_rounded,
          context: context,
        ),
        buildContextMenuItem<String>(
          value: 'copy_artist',
          enabled: hasArtist,
          label: l10n.copyArtistName,
          icon: Icons.mic_rounded,
          context: context,
        ),
        const PopupMenuDivider(),
        buildContextMenuItem<String>(
          value: 'transcode',
          enabled: song != null || (songs != null && songs.isNotEmpty),
          label: l10n.transcodeAction,
          icon: Icons.sync_rounded,
          context: context,
        ),
      ]);
      break;
    case SongContextMenuMode.title:
      items.addAll([
        buildContextMenuItem<String>(
          value: 'copy_title',
          enabled: hasTitle,
          label: l10n.copyTitle,
          icon: Icons.title_rounded,
          context: context,
        ),
        if (canOpenLocation) ...[
          const PopupMenuDivider(),
          buildContextMenuItem<String>(
            value: 'open_file_location',
            enabled: canOpenLocation,
            label: l10n.openFileLocation,
            icon: Icons.folder_open_rounded,
            context: context,
          ),
        ],
      ]);
      break;
    case SongContextMenuMode.artistAlbum:
      items.addAll([
        buildContextMenuItem<String>(
          value: 'copy_artist',
          enabled: hasArtist,
          label: l10n.copyArtistName,
          icon: Icons.mic_rounded,
          context: context,
        ),
        buildContextMenuItem<String>(
          value: 'copy_album',
          enabled: hasAlbum,
          label: l10n.copyAlbumTitle,
          icon: Icons.album_rounded,
          context: context,
        ),
      ]);
      break;
  }

  if (onAddToPlaylist != null) {
    if (items.isNotEmpty && items.last is! PopupMenuDivider) {
      items.add(const PopupMenuDivider());
    }
    items.add(
      buildContextMenuItem<String>(
        value: 'add_to_playlist',
        label: l10n.addToPlaylist,
        icon: Icons.playlist_add_rounded,
        context: context,
      ),
    );
  }

  // 多选入口独立成组。title / artistAlbum 是「复制文案」语境，没有选择态，
  // 即使调用方传了也不显示。
  if (onMultiSelect != null && mode == SongContextMenuMode.full) {
    if (items.isNotEmpty && items.last is! PopupMenuDivider) {
      items.add(const PopupMenuDivider());
    }
    items.add(
      buildContextMenuItem<String>(
        value: 'multi_select',
        label: l10n.multiSelect,
        icon: Icons.checklist_rounded,
        context: context,
      ),
    );
  }

  final selected = await AppContextMenu.show<String>(
    context: context,
    position: globalPosition,
    items: items,
  );

  if (!context.mounted || selected == null) return;
  if (selected == 'multi_select') {
    onMultiSelect?.call();
    return;
  }

  await handleSongAction(
    selected: selected,
    context: context,
    song: song,
    effectiveSongs: effectiveSongs,
    isBatch: isBatch,
    canOpenLocation: canOpenLocation,
    hasTitle: hasTitle,
    hasArtist: hasArtist,
    hasAlbum: hasAlbum,
    titleText: titleText,
    artistText: artistText,
    albumText: albumText,
    onAddToPlaylist: onAddToPlaylist,
    onPlayNext: onPlayNext,
    onAddToQueue: onAddToQueue,
    onRemoveFromQueue: onRemoveFromQueue,
    onRemoveFromPlaylist: onRemoveFromPlaylist,
    onDownload: onDownload,
    onImportLyrics: onImportLyrics,
    onEditTags: onEditTags,
  );
}

/// 歌曲面板的行。行本身由 [buildContextMenuSheetItem] 统一渲染，这里只保留
/// 歌曲菜单特有的「紧凑行高」，20 多个调用点不必各自搬运参数。
Widget _buildSongBottomSheetItem({
  required BuildContext context,
  required String value,
  required String label,
  required IconData icon,
  bool enabled = true,
  Color? iconColor,
}) {
  return buildContextMenuSheetItem(
    context,
    ContextMenuAction(
      value: value,
      label: label,
      icon: icon,
      enabled: enabled,
      accentColor: iconColor,
    ),
    dense: true,
  );
}

Widget _buildSongBottomSheetHeader({
  required BuildContext context,
  required MusicFile? song,
  required List<MusicFile> effectiveSongs,
  required bool isBatch,
}) {
  final theme = Theme.of(context);
  final l10n = AppLocalizations.of(context)!;

  final Widget leadingWidget;
  final String title;
  final String subtitle;
  String? metaInfo;

  if (isBatch) {
    leadingWidget = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.library_music_rounded,
        size: 28,
        color: theme.colorScheme.primary,
      ),
    );
    title = l10n.songCount(effectiveSongs.length);
    subtitle = l10n.multiSelect;
  } else if (song != null) {
    leadingWidget = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 52,
        height: 52,
        child: SongThumbnail.fromSong(
          song,
          size: 52,
        ),
      ),
    );
    title = song.displayName.trim().isNotEmpty
        ? song.displayName
        : l10n.unknown;

    final artist = isVisibleSongText(song.artist) ? song.artist!.trim() : null;
    final album = isVisibleSongText(song.album) ? song.album!.trim() : null;
    if (artist != null && album != null) {
      subtitle = '$artist · $album';
    } else if (artist != null) {
      subtitle = artist;
    } else if (album != null) {
      subtitle = album;
    } else {
      subtitle = l10n.unknownArtist;
    }

    final durationMillis = song.durationMillis;
    final durationStr = (durationMillis != null && durationMillis > 0)
        ? durationMillis.toFormattedDuration()
        : null;
    final ext = song.path.contains('.')
        ? song.path.split('.').last.toUpperCase()
        : null;
    final formatStr =
        (ext != null && ext.isNotEmpty && ext.length <= 5) ? ext : null;
    final metaParts = [durationStr, formatStr].whereType<String>().toList();
    if (metaParts.isNotEmpty) {
      metaInfo = metaParts.join(' | ');
    }
  } else {
    return const SizedBox.shrink();
  }

  return Row(
    children: [
      leadingWidget,
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (metaInfo != null) ...[
              const SizedBox(height: 2),
              Text(
                metaInfo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

/// Shows a bottom sheet with action items for a music file.
/// Standard presentation for mobile devices (Android / iOS).
Future<void> showSongBottomSheet(
  BuildContext context, {
  required MusicFile? song,
  List<MusicFile>? songs,
  SongContextMenuMode mode = SongContextMenuMode.full,
  Future<void> Function()? onAddToPlaylist,
  VoidCallback? onPlayNext,
  VoidCallback? onAddToQueue,
  VoidCallback? onRemoveFromQueue,
  VoidCallback? onRemoveFromPlaylist,
  VoidCallback? onDownload,
  VoidCallback? onImportLyrics,
  VoidCallback? onEditTags,
  VoidCallback? onMultiSelect,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);

  final effectiveSongs = (songs != null && songs.isNotEmpty)
      ? songs
      : (song != null ? [song] : <MusicFile>[]);
  final isBatch = effectiveSongs.length > 1;
  final canEditTags = effectiveSongs.isNotEmpty &&
      effectiveSongs.any((s) => !RemoteMediaResolver.isRemoteUri(s.path));

  final titleText = song?.displayName.trim() ?? '';
  final artistText = song?.artist?.trim() ?? '';
  final albumText = song?.album?.trim() ?? '';
  final hasTitle = titleText.isNotEmpty;
  final hasArtist = isVisibleSongText(artistText);
  final hasAlbum = isVisibleSongText(albumText);
  final isRemoteSong =
      song != null && RemoteMediaResolver.isRemoteUri(song.path);
  final hasFilePath = song != null && song.path.trim().isNotEmpty;
  final canOpenLocation =
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
          hasFilePath &&
          !isRemoteSong;

  // 面板行在面板自己的 context 下构建，见下方 showAppActionSheet 的说明。
  List<Widget> buildActions(BuildContext context) {
    final actions = <Widget>[];

    // 1. Playback actions (Top)
    if (onPlayNext != null) {
      actions.add(
        _buildSongBottomSheetItem(
          context: context,
          value: 'play_next',
          label: l10n.playNext,
          icon: Icons.queue_play_next_rounded,
        ),
      );
    }
    if (onAddToQueue != null) {
      actions.add(
        _buildSongBottomSheetItem(
          context: context,
          value: 'add_to_queue',
          label: l10n.addToQueue,
          icon: Icons.queue_music_rounded,
        ),
      );
    }
    if (onAddToPlaylist != null) {
      actions.add(
        _buildSongBottomSheetItem(
          context: context,
          value: 'add_to_playlist',
          label: l10n.addToPlaylist,
          icon: Icons.playlist_add_rounded,
        ),
      );
    }
    if (onDownload != null) {
      actions.add(
        _buildSongBottomSheetItem(
          context: context,
          value: 'download',
          label: l10n.download,
          icon: Icons.download_rounded,
        ),
      );
    }
    if (onRemoveFromQueue != null) {
      actions.add(
        _buildSongBottomSheetItem(
          context: context,
          value: 'remove_from_queue',
          label: _getRemoveFromQueueLabel(context),
          icon: Icons.playlist_remove_rounded,
        ),
      );
    }
    if (onRemoveFromPlaylist != null) {
      actions.add(
        _buildSongBottomSheetItem(
          context: context,
          value: 'remove_from_playlist',
          label: _getRemoveFromPlaylistLabel(context),
          icon: Icons.delete_outline_rounded,
          iconColor: theme.colorScheme.error,
        ),
      );
    }

    // 2. Standard Metadata / File Actions
    switch (mode) {
      case SongContextMenuMode.full:
        if (canEditTags) {
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'edit_tags',
              label: isBatch
                  ? '${l10n.batchEditSongTagsTitle} (${effectiveSongs.length})'
                  : l10n.editSongTagsTitle,
              icon: Icons.edit_note_rounded,
            ),
          );
        }
        if (song != null) {
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'song_details',
              label: l10n.songProperties,
              icon: Icons.info_outline_rounded,
            ),
          );
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'import_lyrics',
              label: l10n.importLyrics,
              icon: Icons.lyrics_outlined,
            ),
          );
        }
        if (song != null || effectiveSongs.isNotEmpty) {
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'transcode',
              label: l10n.transcodeAction,
              icon: Icons.sync_rounded,
            ),
          );
        }
        if (canOpenLocation) {
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'open_file_location',
              label: l10n.openFileLocation,
              icon: Icons.folder_open_rounded,
            ),
          );
        }
        if (hasTitle) {
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'copy_title',
              label: l10n.copyTitle,
              icon: Icons.title_rounded,
            ),
          );
        }
        if (hasAlbum) {
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'copy_album',
              label: l10n.copyAlbumTitle,
              icon: Icons.album_rounded,
            ),
          );
        }
        if (hasArtist) {
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'copy_artist',
              label: l10n.copyArtistName,
              icon: Icons.mic_rounded,
            ),
          );
        }
        break;

      case SongContextMenuMode.title:
        if (hasTitle) {
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'copy_title',
              label: l10n.copyTitle,
              icon: Icons.title_rounded,
            ),
          );
        }
        if (canOpenLocation) {
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'open_file_location',
              label: l10n.openFileLocation,
              icon: Icons.folder_open_rounded,
            ),
          );
        }
        break;

      case SongContextMenuMode.artistAlbum:
        if (hasArtist) {
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'copy_artist',
              label: l10n.copyArtistName,
              icon: Icons.mic_rounded,
            ),
          );
        }
        if (hasAlbum) {
          actions.add(
            _buildSongBottomSheetItem(
              context: context,
              value: 'copy_album',
              label: l10n.copyAlbumTitle,
              icon: Icons.album_rounded,
            ),
          );
        }
        break;
    }

    if (onMultiSelect != null && mode == SongContextMenuMode.full) {
      actions.add(
        _buildSongBottomSheetItem(
          context: context,
          value: 'multi_select',
          label: l10n.multiSelect,
          icon: Icons.checklist_rounded,
        ),
      );
    }

    return actions;
  }

  // 行内动作必须用面板自己的 context 关闭自己：用外层页面的 context 会 pop 到
  // 页面所在的嵌套 Navigator 上（库页的每个分类各有一条 Navigator），面板反而
  // 不会被关掉、返回值也永远收不到。
  final selected = await showAppActionSheet<String>(
    context: context,
    scrollable: true,
    header: _buildSongBottomSheetHeader(
      context: context,
      song: song,
      effectiveSongs: effectiveSongs,
      isBatch: isBatch,
    ),
    itemsBuilder: buildActions,
  );

  if (!context.mounted || selected == null) return;
  if (selected == 'multi_select') {
    onMultiSelect?.call();
    return;
  }

  await handleSongAction(
    selected: selected,
    context: context,
    song: song,
    effectiveSongs: effectiveSongs,
    isBatch: isBatch,
    canOpenLocation: canOpenLocation,
    hasTitle: hasTitle,
    hasArtist: hasArtist,
    hasAlbum: hasAlbum,
    titleText: titleText,
    artistText: artistText,
    albumText: albumText,
    onAddToPlaylist: onAddToPlaylist,
    onPlayNext: onPlayNext,
    onAddToQueue: onAddToQueue,
    onRemoveFromQueue: onRemoveFromQueue,
    onRemoveFromPlaylist: onRemoveFromPlaylist,
    onDownload: onDownload,
    onImportLyrics: onImportLyrics,
    onEditTags: onEditTags,
  );
}

Future<void> handleSongAction({
  required String selected,
  required BuildContext context,
  required MusicFile? song,
  required List<MusicFile> effectiveSongs,
  required bool isBatch,
  required bool canOpenLocation,
  required bool hasTitle,
  required bool hasArtist,
  required bool hasAlbum,
  required String titleText,
  required String artistText,
  required String albumText,
  Future<void> Function()? onAddToPlaylist,
  VoidCallback? onPlayNext,
  VoidCallback? onAddToQueue,
  VoidCallback? onRemoveFromQueue,
  VoidCallback? onRemoveFromPlaylist,
  VoidCallback? onDownload,
  VoidCallback? onImportLyrics,
  VoidCallback? onEditTags,
}) async {
  final l10n = AppLocalizations.of(context)!;

  switch (selected) {
    case 'play_next':
      onPlayNext?.call();
      break;
    case 'add_to_queue':
      onAddToQueue?.call();
      break;
    case 'download':
      onDownload?.call();
      break;
    case 'remove_from_queue':
      onRemoveFromQueue?.call();
      break;
    case 'remove_from_playlist':
      onRemoveFromPlaylist?.call();
      break;
    case 'copy_title':
      if (hasTitle) {
        await Clipboard.setData(ClipboardData(text: titleText));
      }
      break;
    case 'copy_artist':
      if (hasArtist) {
        await Clipboard.setData(ClipboardData(text: artistText));
      }
      break;
    case 'copy_album':
      if (hasAlbum) {
        await Clipboard.setData(ClipboardData(text: albumText));
      }
      break;
    case 'open_file_location':
      if (canOpenLocation && song != null) {
        await openSongFileLocation(song.path);
      }
      break;
    case 'import_lyrics':
      if (song != null) {
        if (onImportLyrics != null) {
          onImportLyrics();
        } else {
          final container = ProviderScope.containerOf(context, listen: false);
          await importLyricsForSongWithContainer(context, container, song);
        }
      }
      break;
    case 'song_details':
      if (song != null) {
        await showSongDetailsDialog(context, song);
      }
      break;
    case 'edit_tags':
      if (onEditTags != null) {
        onEditTags();
      } else if (effectiveSongs.isNotEmpty) {
        final result = await showSongTagEditSheet(
          context,
          songs: effectiveSongs,
        );
        if (result != null && context.mounted) {
          final container = ProviderScope.containerOf(context, listen: false);
          final scanner = container.read(scannerServiceProvider);
          final audio = container.read(audioServiceProvider);
          final playlistService = container.read(playlistServiceProvider);

          final items = result.allUpdatedMetadata.isNotEmpty
              ? result.allUpdatedMetadata
              : [(result.metadata, result.artworkBytes)];

          for (final (metadata, artworkBytes) in items) {
            await audio.applyUpdatedSongMetadata(
              metadata,
              artworkBytes: artworkBytes,
            );
            scanner.updateMetadataForPath(
              metadata,
              artworkBytes: artworkBytes,
            );
            await playlistService.updateSongMetadataByPath(
              metadata,
              artworkBytes: artworkBytes,
            );
          }

          final count = items.length;
          final String message;
          if (count > 1) {
            message = result.savedToSourceFile
                ? l10n.batchSongTagsSavedToSourceFileAndApp(count)
                : l10n.batchSongTagsSavedToApp(count);
          } else {
            message = result.savedToSourceFile
                ? l10n.songTagsSavedToSourceFileAndApp
                : l10n.songTagsSavedToApp;
          }
          showToast(message);
        }
      }
      break;
    case 'add_to_playlist':
      if (onAddToPlaylist != null) {
        await onAddToPlaylist();
      }
      break;
    case 'transcode':
      if (effectiveSongs.isNotEmpty) {
        await showTranscodeDialog(context, songs: effectiveSongs);
      } else if (song != null) {
        await showTranscodeDialog(context, songs: [song]);
      }
      break;
  }
}

Future<void> showAddSongsToPlaylistDialog(
  BuildContext context,
  PlaylistService playlistService,
  List<MusicFile> songs, {
  VoidCallback? onPlaylistCreatedOrUpdated,
}) async {
  await AddToPlaylistDialog.show(
    context,
    playlistService: playlistService,
    songs: songs,
    onPlaylistCreatedOrUpdated: onPlaylistCreatedOrUpdated,
  );
}

Future<void> showFolderContextMenu(
  BuildContext context,
  Offset globalPosition, {
  required String folderPath,
}) async {
  final l10n = AppLocalizations.of(context)!;

  final canOpenLocation =
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
      folderPath.trim().isNotEmpty;

  final selected = await AppContextMenu.show<String>(
    context: context,
    position: globalPosition,
    items: [
      buildContextMenuItem<String>(
        value: 'open_folder_location',
        enabled: canOpenLocation,
        label: l10n.openFolderLocation,
        icon: Icons.folder_open_rounded,
        context: context,
      ),
    ],
  );

  if (!context.mounted || selected == null) return;

  if (selected == 'open_folder_location' && canOpenLocation) {
    await openFolderLocation(folderPath);
  }
}

