import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/file_selector_helper.dart';

import '../l10n/app_localizations.dart';
import '../widgets/app_bottom_sheet.dart';
import 'package:oktoast/oktoast.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import 'package:audio_core/audio_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';

const String keepTagPlaceholder = '<keep>';

class SongTagEditResult {
  const SongTagEditResult({
    required this.metadata,
    required this.savedToSourceFile,
    this.artworkBytes,
    this.allUpdatedMetadata = const [],
  });

  final SongMetadata metadata;
  final bool savedToSourceFile;
  final Uint8List? artworkBytes;
  final List<(SongMetadata, Uint8List?)> allUpdatedMetadata;
}

Future<SongTagEditResult?> showSongTagEditSheet(
  BuildContext context, {
  MusicFile? song,
  List<MusicFile>? songs,
}) {
  final targetSongs = songs ?? (song != null ? [song] : <MusicFile>[]);
  if (targetSongs.isEmpty) return Future.value(null);

  return showAppAdaptiveModal<SongTagEditResult>(
    context: context,
    useRootNavigator: true,
    builder: (context) => SongTagEditSheet(songs: targetSongs),
  );
}

/// Helper method to apply tag edit result across AudioService, ScannerService, and PlaylistService
Future<void> applySongTagEditResult(
  BuildContext context,
  WidgetRef ref,
  SongTagEditResult result,
) async {
  final scanner = ref.read(scannerServiceProvider);
  final audio = ref.read(audioServiceProvider);
  final playlistService = ref.read(playlistServiceProvider);
  final l10n = AppLocalizations.of(context)!;

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
  if (!context.mounted) return;
  AppSnackBar.show(context, ref, SnackBar(content: Text(message)));
}

class SongTagEditSheet extends StatefulWidget {
  const SongTagEditSheet({
    super.key,
    this.song,
    this.songs = const [],
  });

  final MusicFile? song;
  final List<MusicFile> songs;

  List<MusicFile> get effectiveSongs =>
      songs.isNotEmpty ? songs : (song != null ? [song!] : const []);

  @override
  State<SongTagEditSheet> createState() => _SongTagEditSheetState();
}

class _SongTagEditSheetState extends State<SongTagEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumArtistController;
  late final TextEditingController _albumController;
  late final TextEditingController _trackNumberController;

  bool _isSaving = false;
  String? _errorMessage;
  Uint8List? _artworkBytes;
  String? _artworkPath;
  bool _isArtworkModified = false;
  bool _isArtworkMixed = false;
  bool _isLoadingArtwork = false;

  bool get isBatch => widget.effectiveSongs.length > 1;

  @override
  void initState() {
    super.initState();
    final songs = widget.effectiveSongs;
    if (songs.length <= 1) {
      final song = songs.isNotEmpty ? songs.first : null;
      _titleController = TextEditingController(
        text: song?.title?.trim().isNotEmpty == true
            ? song!.title!.trim()
            : (song?.displayName ?? ''),
      );
      _artistController = TextEditingController(
        text: song?.artist?.trim() ?? '',
      );
      _albumArtistController = TextEditingController(
        text: song?.albumArtist?.trim() ?? '',
      );
      _albumController = TextEditingController(
        text: song?.album?.trim() ?? '',
      );
      _trackNumberController = TextEditingController(
        text: song?.trackNumber?.toString() ?? '',
      );
    } else {
      final firstTitle = songs.first.title?.trim();
      final allSameTitle = firstTitle != null &&
          firstTitle.isNotEmpty &&
          songs.every((s) => s.title?.trim() == firstTitle);
      _titleController = TextEditingController(
        text: allSameTitle ? firstTitle : keepTagPlaceholder,
      );

      final firstArtist = songs.first.artist?.trim() ?? '';
      final allSameArtist =
          songs.every((s) => (s.artist?.trim() ?? '') == firstArtist);
      _artistController = TextEditingController(
        text: allSameArtist ? firstArtist : keepTagPlaceholder,
      );

      final firstAlbumArtist = songs.first.albumArtist?.trim() ?? '';
      final allSameAlbumArtist =
          songs.every((s) => (s.albumArtist?.trim() ?? '') == firstAlbumArtist);
      _albumArtistController = TextEditingController(
        text: allSameAlbumArtist ? firstAlbumArtist : keepTagPlaceholder,
      );

      final firstAlbum = songs.first.album?.trim() ?? '';
      final allSameAlbum =
          songs.every((s) => (s.album?.trim() ?? '') == firstAlbum);
      _albumController = TextEditingController(
        text: allSameAlbum ? firstAlbum : keepTagPlaceholder,
      );

      final firstTrack = songs.first.trackNumber;
      final allSameTrack = songs.every((s) => s.trackNumber == firstTrack);
      _trackNumberController = TextEditingController(
        text: allSameTrack
            ? (firstTrack?.toString() ?? '')
            : keepTagPlaceholder,
      );
    }

    _loadArtwork();
  }

  Future<void> _loadArtwork() async {
    if (widget.effectiveSongs.isEmpty) return;
    setState(() {
      _isLoadingArtwork = true;
    });

    if (widget.effectiveSongs.length <= 1) {
      final song = widget.effectiveSongs.first;
      String? path = song.artworkPath ?? song.thumbnailPath;
      Uint8List? bytes;
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          try {
            bytes = await file.readAsBytes();
          } catch (_) {}
        }
      }
      if (bytes == null) {
        bytes = await MetadataHelper.decodeEmbeddedArtwork(song.path);
        if (bytes != null && bytes.isNotEmpty) {
          final md5Hex = await calculateMd5(bytes: bytes);
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/$md5Hex.jpg');
          if (!tempFile.existsSync()) {
            await tempFile.writeAsBytes(bytes);
          }
          path = tempFile.path;
        }
      }
      if (mounted) {
        setState(() {
          _artworkPath = path;
          _artworkBytes = bytes;
          _isLoadingArtwork = false;
        });
      }
    } else {
      final firstPath = widget.effectiveSongs.first.artworkPath ?? widget.effectiveSongs.first.thumbnailPath;
      final allSameArtwork = firstPath != null &&
          firstPath.isNotEmpty &&
          widget.effectiveSongs.every((s) => (s.artworkPath ?? s.thumbnailPath) == firstPath);

      if (allSameArtwork) {
        final file = File(firstPath);
        Uint8List? bytes;
        if (await file.exists()) {
          try {
            bytes = await file.readAsBytes();
          } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _artworkPath = firstPath;
            _artworkBytes = bytes;
            _isArtworkMixed = false;
            _isLoadingArtwork = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isArtworkMixed = true;
            _artworkPath = null;
            _artworkBytes = null;
            _isLoadingArtwork = false;
          });
        }
      }
    }
  }

  Future<void> _pickArtwork({bool fromGallery = false}) async {
    try {
      final path = await FileSelectorHelper.pickFile(
        label: 'Images',
        extensions: const ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
        fileType: fromGallery ? FileType.image : FileType.custom,
      );

      if (path != null) {
        final file = File(path);
        final bytes = await file.readAsBytes();
        setState(() {
          _artworkPath = path;
          _artworkBytes = bytes;
          _isArtworkModified = true;
          _isArtworkMixed = false;
        });
      }
    } catch (e) {
      debugPrint('Error picking artwork: $e');
    }
  }

  bool get _hasArtwork =>
      !_isArtworkMixed &&
      ((_artworkBytes != null && _artworkBytes!.isNotEmpty) ||
          (_artworkPath != null && _artworkPath!.isNotEmpty));

  Future<void> _exportArtwork() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      Uint8List? bytes = _artworkBytes;
      if ((bytes == null || bytes.isEmpty) &&
          _artworkPath != null &&
          _artworkPath!.isNotEmpty) {
        final file = File(_artworkPath!);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        }
      }

      if (bytes == null || bytes.isEmpty) {
        showToast(l10n.exportArtworkFailed);
        return;
      }

      String ext = 'jpg';
      if (bytes.length >= 8) {
        if (bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47) {
          ext = 'png';
        } else if (bytes[0] == 0x52 &&
            bytes[1] == 0x49 &&
            bytes[2] == 0x46 &&
            bytes[3] == 0x46) {
          ext = 'webp';
        } else if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
          ext = 'jpg';
        }
      }

      String defaultBaseName = 'cover';
      if (widget.effectiveSongs.isNotEmpty) {
        final song = widget.effectiveSongs.first;
        final title = _titleController.text.trim().isNotEmpty &&
                _titleController.text.trim() != keepTagPlaceholder
            ? _titleController.text.trim()
            : (song.title?.trim().isNotEmpty == true
                ? song.title!.trim()
                : song.displayName);
        final artist = _artistController.text.trim().isNotEmpty &&
                _artistController.text.trim() != keepTagPlaceholder
            ? _artistController.text.trim()
            : (song.artist?.trim() ?? '');
        if (artist.isNotEmpty && title.isNotEmpty) {
          defaultBaseName = '$artist - $title - Cover';
        } else if (title.isNotEmpty) {
          defaultBaseName = '$title - Cover';
        }
      }
      defaultBaseName =
          defaultBaseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      final savedPath = await FileSelectorHelper.saveFile(
        suggestedName: '$defaultBaseName.$ext',
        label: 'Images',
        extensions: [ext],
        bytes: bytes,
      );

      if (savedPath != null && mounted) {
        showToast(l10n.exportArtworkSuccess);
      }
    } catch (e) {
      debugPrint('Error exporting artwork: $e');
      if (mounted) {
        showToast(l10n.exportArtworkFailed);
      }
    }
  }

  Future<void> _showArtworkOptions() async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isMobile = Platform.isIOS || Platform.isAndroid;

    if (!isMobile &&
        !_isArtworkMixed &&
        (_artworkBytes == null || (_isArtworkModified && _artworkBytes!.isEmpty))) {
      await _pickArtwork();
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final hasArtwork = _hasArtwork;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.88)
                  : theme.colorScheme.surface.withValues(alpha: 0.95),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isMobile) ...[
                    ListTile(
                      leading: Icon(Icons.photo_library_rounded,
                          color: theme.colorScheme.primary),
                      title: Text(l10n.chooseFromPhotos),
                      onTap: () => Navigator.of(context).pop('pick_gallery'),
                    ),
                    ListTile(
                      leading: Icon(Icons.folder_open_rounded,
                          color: theme.colorScheme.primary),
                      title: Text(l10n.chooseFromFiles),
                      onTap: () => Navigator.of(context).pop('pick_file'),
                    ),
                  ] else ...[
                    ListTile(
                      leading: Icon(Icons.photo_library_rounded,
                          color: theme.colorScheme.primary),
                      title: Text(l10n.changeArtwork),
                      onTap: () => Navigator.of(context).pop('change'),
                    ),
                  ],
                  if (hasArtwork)
                    ListTile(
                      leading: Icon(Icons.file_download_outlined,
                          color: theme.colorScheme.primary),
                      title: Text(l10n.exportArtwork),
                      onTap: () => Navigator.of(context).pop('export'),
                    ),
                  if (hasArtwork)
                    ListTile(
                      leading:
                          const Icon(Icons.delete_rounded, color: Colors.redAccent),
                      title: Text(l10n.clearArtwork,
                          style: const TextStyle(color: Colors.redAccent)),
                      onTap: () => Navigator.of(context).pop('clear'),
                    ),
                  ListTile(
                    leading: const Icon(Icons.close_rounded),
                    title: Text(l10n.cancel),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (action == 'pick_gallery') {
      await _pickArtwork(fromGallery: true);
    } else if (action == 'pick_file' || action == 'change') {
      await _pickArtwork(fromGallery: false);
    } else if (action == 'export') {
      await _exportArtwork();
    } else if (action == 'clear') {
      setState(() {
        _artworkBytes = Uint8List(0);
        _artworkPath = null;
        _isArtworkModified = true;
        _isArtworkMixed = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumArtistController.dispose();
    _albumController.dispose();
    _trackNumberController.dispose();
    super.dispose();
  }

  Future<void> _save({required bool writeToFile}) async {
    if (_isSaving || widget.effectiveSongs.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;

    final trackNumberText = _trackNumberController.text.trim();
    final isTrackKeep = trackNumberText == keepTagPlaceholder;
    final trackNumber = (trackNumberText.isEmpty || isTrackKeep)
        ? null
        : int.tryParse(trackNumberText);
    if (!isTrackKeep && trackNumberText.isNotEmpty && trackNumber == null) {
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.trackNumberMustBeInteger;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final titleText = _titleController.text.trim();
    final isTitleKeep = titleText == keepTagPlaceholder;

    final artistText = _artistController.text.trim();
    final isArtistKeep = artistText == keepTagPlaceholder;

    final albumArtistText = _albumArtistController.text.trim();
    final isAlbumArtistKeep = albumArtistText == keepTagPlaceholder;

    final albumText = _albumController.text.trim();
    final isAlbumKeep = albumText == keepTagPlaceholder;

    final updatedResults = <(SongMetadata, Uint8List?)>[];
    String? firstFailureReason;
    bool hasOccupiedError = false;

    for (final song in widget.effectiveSongs) {
      final songIsRemote = RemoteMediaResolver.isRemoteUri(song.path);
      if (songIsRemote) continue;

      final songTrackNumber =
          isTrackKeep ? song.trackNumber : trackNumber;
      final songClearTrackNumber = !isTrackKeep && trackNumberText.isEmpty;

      final resolvedTitle = isTitleKeep
          ? (song.title?.trim().isNotEmpty == true
              ? song.title!.trim()
              : song.displayName)
          : titleText;
      final resolvedArtist =
          isArtistKeep ? (song.artist?.trim() ?? '') : artistText;
      final resolvedAlbumArtist =
          isAlbumArtistKeep ? song.albumArtist : albumArtistText;
      final resolvedAlbum =
          isAlbumKeep ? (song.album?.trim() ?? '') : albumText;

      final canWriteThisFile = writeToFile && isMetadataWritable(song.path);

      final result = await MetadataHelper.saveSelectedSongMetadata(
        filePath: song.path,
        title: resolvedTitle,
        artist: resolvedArtist,
        albumArtist: resolvedAlbumArtist,
        album: resolvedAlbum,
        trackNumber: songTrackNumber,
        clearTrackNumber: songClearTrackNumber,
        artworkBytes: _isArtworkModified ? _artworkBytes : null,
        existingMetadata: null,
        writeToFile: canWriteThisFile,
        fallbackMediaUri: song.mediaUri,
      );

      if (result != null) {
        updatedResults.add((
          result.$1,
          result.$2 ??
              (_isArtworkModified ? _artworkBytes : song.artworkBytes),
        ));
      } else {
        final reason = MetadataHelper.lastWriteError;
        if (reason == 'file_occupied') {
          hasOccupiedError = true;
        }
        firstFailureReason ??= reason;
      }
    }

    if (updatedResults.isEmpty && widget.effectiveSongs.isNotEmpty) {
      if (hasOccupiedError && mounted) {
        showToast(l10n.fileOccupiedByOtherApp);
      }
      setState(() {
        _isSaving = false;
        _errorMessage = writeToFile
            ? (hasOccupiedError
                ? l10n.fileOccupiedByOtherApp
                : (firstFailureReason != null
                    ? '${l10n.saveToSourceFileFailed}\n($firstFailureReason)'
                    : l10n.saveToSourceFileFailed))
            : (firstFailureReason != null
                ? '${l10n.saveFailed}\n($firstFailureReason)'
                : l10n.saveFailed);
      });
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      SongTagEditResult(
        metadata: updatedResults.first.$1,
        artworkBytes: updatedResults.first.$2,
        savedToSourceFile: writeToFile,
        allUpdatedMetadata: updatedResults,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasRemote =
        widget.effectiveSongs.any((s) => RemoteMediaResolver.isRemoteUri(s.path));
    final canWriteToSourceFile = !hasRemote &&
        widget.effectiveSongs.any((s) => isMetadataWritable(s.path));
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final headerTitle = isBatch
        ? '${l10n.batchEditSongTagsTitle} (${widget.effectiveSongs.length})'
        : l10n.editSongTagsTitle;

    final headerDescription = isBatch
        ? l10n.batchEditSongTagsDescription
        : l10n.editSongTagsDescription;

    return AppAdaptiveSheet(
      title: headerTitle,
      subtitle: headerDescription,
      sheetMaxWidth: 760,
      dialogMaxWidth: 720,
      landscapeMaxWidth: 980,
      expandHeight: true,
      dialogHeight: 700,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                Center(
                          child: GestureDetector(
                            onTap: _isSaving ? null : _showArtworkOptions,
                            child: Stack(
                              children: [
                                Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : Colors.black.withValues(alpha: 0.08),
                                      width: 1,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: _isLoadingArtwork
                                        ? const Center(
                                            child: SizedBox(
                                              width: 24,
                                              height: 24,
                                              child:
                                                  CircularProgressIndicator(
                                                      strokeWidth: 2),
                                            ),
                                          )
                                        : _isArtworkModified &&
                                                _artworkBytes != null &&
                                                _artworkBytes!.isEmpty
                                            ? Center(
                                                child: Icon(
                                                  Icons
                                                      .image_not_supported_outlined,
                                                  size: 40,
                                                  color: isDark
                                                      ? Colors.white.withValues(
                                                          alpha: 0.3)
                                                      : Colors.black.withValues(
                                                          alpha: 0.3),
                                                ),
                                              )
                                            : _artworkPath != null &&
                                                    _artworkPath!.isNotEmpty
                                                ? Image.file(
                                                    File(_artworkPath!),
                                                    fit: BoxFit.cover,
                                                  )
                                                : _artworkBytes != null &&
                                                        _artworkBytes!
                                                            .isNotEmpty
                                                    ? Image.memory(
                                                        _artworkBytes!,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : _isArtworkMixed
                                                        ? Center(
                                                            child: Column(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .collections_rounded,
                                                                  size: 34,
                                                                  color: isDark
                                                                      ? Colors
                                                                          .white
                                                                          .withValues(
                                                                              alpha:
                                                                                  0.4)
                                                                      : Colors
                                                                          .black
                                                                          .withValues(
                                                                              alpha:
                                                                                  0.4),
                                                                ),
                                                                const SizedBox(
                                                                    height: 4),
                                                                Padding(
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          8.0),
                                                                  child: Text(
                                                                    l10n.multipleArtworkKeep,
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      color: isDark
                                                                          ? Colors.white.withValues(alpha: 0.5)
                                                                          : Colors.black.withValues(alpha: 0.5),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          )
                                                        : Icon(
                                                            Icons
                                                                .music_note_rounded,
                                                            size: 48,
                                                            color: isDark
                                                                ? Colors.white
                                                                    .withValues(
                                                                        alpha:
                                                                            0.3)
                                                                : Colors.black
                                                                    .withValues(
                                                                        alpha:
                                                                            0.3),
                                                          ),
                                  ),
                                ),
                                if (!_isSaving && _hasArtwork)
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: _exportArtwork,
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.black.withValues(alpha: 0.65)
                                                : Colors.white.withValues(alpha: 0.85),
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.2),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              )
                                            ],
                                          ),
                                          child: Tooltip(
                                            message: l10n.exportArtwork,
                                            child: Icon(
                                              Icons.file_download_outlined,
                                              size: 14,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (!_isSaving)
                                  Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.25),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          )
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.edit_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildField(
                          context: context,
                          controller: _titleController,
                          label: l10n.title,
                          icon: Icons.title_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          context: context,
                          controller: _artistController,
                          label: l10n.artistLabel,
                          icon: Icons.person_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          context: context,
                          controller: _albumArtistController,
                          label: l10n.albumArtistLabel,
                          icon: Icons.groups_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          context: context,
                          controller: _albumController,
                          label: l10n.albumLabel,
                          icon: Icons.album_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          context: context,
                          controller: _trackNumberController,
                          label: l10n.trackNumberLabel,
                          icon: Icons.numbers_rounded,
                          keyboardType: TextInputType.number,
                          helperText: l10n.leaveBlankKeepsCurrentValue,
                        ),
                        const SizedBox(height: 16),
                        _buildReadonlyInfo(
                          context: context,
                          label: l10n.file,
                          value: isBatch
                              ? '${widget.effectiveSongs.length} files selected'
                              : (widget.effectiveSongs.isNotEmpty
                                  ? widget.effectiveSongs.first.path
                                  : ''),
                          icon: Icons.folder_open_rounded,
                        ),
                        const SizedBox(height: 10),
                        if (!canWriteToSourceFile)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              l10n.currentFileFormatCannotWriteBack,
                              style: TextStyle(
                                color: Colors.orangeAccent.withValues(
                                  alpha: 0.9,
                                ),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        if (_errorMessage != null) ...[
                          Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          isBatch
                              ? l10n.keepFieldHint
                              : l10n.leaveBlankDoesNotClearOriginalValue,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.45)
                                : theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.tonal(
                          onPressed: _isSaving || hasRemote
                              ? null
                              : () => _save(writeToFile: false),
                          child: Text(l10n.saveToApp),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: _isSaving ||
                                  !canWriteToSourceFile ||
                                  hasRemote
                              ? null
                              : () => _save(writeToFile: true),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.saveToSourceFileAndApp),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
  }

  Widget _buildField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? helperText,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TextField(
      controller: controller,
      enabled: !_isSaving,
      keyboardType: keyboardType,
      style: TextStyle(
          color: isDark ? Colors.white : theme.colorScheme.onSurface),
      cursorColor: theme.colorScheme.primary,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: Icon(icon,
            color: isDark
                ? Colors.white70
                : theme.colorScheme.onSurfaceVariant),
        labelStyle: TextStyle(
            color: isDark
                ? Colors.white.withValues(alpha: 0.75)
                : theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.75)),
        helperStyle: TextStyle(
            color: isDark
                ? Colors.white.withValues(alpha: 0.4)
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: theme.colorScheme.primary, width: 1.1),
        ),
      ),
    );
  }

  Widget _buildReadonlyInfo({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.7)
                  : theme.colorScheme.onSurfaceVariant,
              size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.55)
                        : theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.86)
                        : theme.colorScheme.onSurface,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
