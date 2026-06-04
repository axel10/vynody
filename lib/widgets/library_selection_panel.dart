import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/player/library/playlist_service.dart';
import 'package:vibe_flow/dialogs/transcode_dialog.dart';
import 'package:vibe_flow/utils/song_context_menu_utils.dart';
import 'package:vibe_flow/l10n/app_localizations.dart';

class LibrarySelectionActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

final librarySelectionActiveProvider =
    NotifierProvider<LibrarySelectionActiveNotifier, bool>(
  LibrarySelectionActiveNotifier.new,
);

class LibrarySelectionPanel extends ConsumerWidget {
  const LibrarySelectionPanel({
    super.key,
    required this.selectedSongs,
    required this.allSongs,
    required this.onToggleSelectAll,
    required this.onCancel,
  });

  final List<MusicFile> selectedSongs;
  final List<MusicFile> allSongs;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final audio = ref.read(audioServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);

    final isAllSelected = selectedSongs.length == allSongs.length && allSongs.isNotEmpty;
    final isSingleSelected = selectedSongs.length == 1;
    final isEmpty = selectedSongs.isEmpty;

    final hasFilePath = isSingleSelected && selectedSongs.first.path.trim().isNotEmpty;
    final canOpenLocation =
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
        hasFilePath;

    final selectAllText = isAllSelected
        ? (Localizations.localeOf(context).languageCode == 'zh' ? '取消全选' : 'Deselect All')
        : l10n.selectAll;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Material(
              elevation: 16,
              color: theme.colorScheme.surface,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header row
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        Text(
                          l10n.selectedSongs(selectedSongs.length),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: onCancel,
                          tooltip: l10n.cancel,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Row 1 of actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildSelectionActionButton(
                          context: context,
                          icon: isAllSelected ? Icons.deselect : Icons.select_all,
                          label: selectAllText,
                          onPressed: allSongs.isEmpty ? null : onToggleSelectAll,
                        ),
                        _buildSelectionActionButton(
                          context: context,
                          icon: Icons.queue_play_next_rounded,
                          label: l10n.playNext,
                          onPressed: isEmpty
                              ? null
                              : () async {
                                  await audio.enqueueNext(selectedSongs);
                                  onCancel();
                                },
                        ),
                        _buildSelectionActionButton(
                          context: context,
                          icon: Icons.queue_music_rounded,
                          label: l10n.addToQueue,
                          onPressed: isEmpty
                              ? null
                              : () async {
                                  await audio.appendToQueue(selectedSongs);
                                  onCancel();
                                },
                        ),
                        _buildSelectionActionButton(
                          context: context,
                          icon: Icons.playlist_add_rounded,
                          label: l10n.addToPlaylist,
                          onPressed: isEmpty
                              ? null
                              : () async {
                                  await showAddSongsToPlaylistDialog(
                                    context,
                                    playlistService,
                                    selectedSongs,
                                  );
                                  onCancel();
                                },
                        ),
                        _buildSelectionActionButton(
                          context: context,
                          icon: Icons.favorite_rounded,
                          label: l10n.addToFavorites,
                          onPressed: isEmpty
                              ? null
                              : () async {
                                  await playlistService.addSongsToPlaylist(
                                    PlaylistService.favoritePlaylistId,
                                    selectedSongs,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          l10n.addedToPlaylist(selectedSongs.length, '收藏'),
                                        ),
                                      ),
                                    );
                                  }
                                  onCancel();
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Row 2 of actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildSelectionActionButton(
                          context: context,
                          icon: Icons.sync_rounded,
                          label: l10n.transcodeAction,
                          onPressed: isEmpty
                              ? null
                              : () async {
                                  await showTranscodeDialog(context, songs: selectedSongs);
                                  onCancel();
                                },
                        ),
                        _buildSelectionActionButton(
                          context: context,
                          icon: Icons.title_rounded,
                          label: l10n.copyTitle,
                          onPressed: isSingleSelected
                              ? () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: selectedSongs.first.displayName),
                                  );
                                  onCancel();
                                }
                              : null,
                        ),
                        _buildSelectionActionButton(
                          context: context,
                          icon: Icons.person_rounded,
                          label: l10n.copyArtistName,
                          onPressed: isSingleSelected && selectedSongs.first.artist != null
                              ? () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: selectedSongs.first.artist!),
                                  );
                                  onCancel();
                                }
                              : null,
                        ),
                        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
                          _buildSelectionActionButton(
                            context: context,
                            icon: Icons.folder_open_rounded,
                            label: l10n.openFileLocation,
                            onPressed: canOpenLocation
                                ? () async {
                                    await openSongFileLocation(selectedSongs.first.path);
                                    onCancel();
                                  }
                                : null,
                          )
                        else
                          const SizedBox(width: 80),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context);
    final isEnabled = onPressed != null;
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.38,
      child: SizedBox(
        width: 80,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
            padding: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
