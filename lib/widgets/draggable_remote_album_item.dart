import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/draggable_preview_card.dart';

/// Wraps a remote album item widget (Navidrome / Jellyfin) to provide system-level native drag source support.
/// Enables dragging a remote album into queue drawer, standalone queue window, or custom playlists.
class DraggableRemoteAlbumItem extends StatelessWidget {
  final RemoteServer server;
  final Map<String, dynamic> album;
  final String albumId;
  final String title;
  final String artist;
  final String? coverId;
  final int? songCount;
  final Widget child;
  final bool enabled;
  final bool isSelectionMode;
  final bool isSelected;
  final Set<String>? selectedAlbumIds;
  final List<Map<String, dynamic>>? allAlbums;

  const DraggableRemoteAlbumItem({
    super.key,
    required this.server,
    required this.album,
    required this.albumId,
    required this.title,
    required this.artist,
    this.coverId,
    this.songCount,
    required this.child,
    this.enabled = true,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedAlbumIds,
    this.allAlbums,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || !DesktopDraggableWrapper.isPlatformSupported) {
      return child;
    }

    final isJellyfin = server.type == RemoteServerType.jellyfin;
    final scheme = isJellyfin ? 'jellyfin-album' : 'subsonic-album';

    final isBatch = isSelectionMode &&
        isSelected &&
        selectedAlbumIds != null &&
        selectedAlbumIds!.length > 1;

    return DesktopDraggableWrapper(
      enabled: enabled,
      dragItemProvider: (request) async {
        debugPrint(
            '[DRAG] DraggableRemoteAlbumItem.dragItemProvider called for: $title (id: $albumId, isBatch: $isBatch)');
        final List<String> uris;
        if (isBatch) {
          uris = selectedAlbumIds!
              .map((id) => '$scheme://${server.id}/$id')
              .toList();
        } else {
          uris = ['$scheme://${server.id}/$albumId'];
        }

        final item = DragItem(
          localData: <String, dynamic>{
            'type': 'remote_album',
            'serverId': server.id,
            'albumId': albumId,
            'title': title,
            'artist': artist,
            'paths': uris,
            'count': uris.length,
          },
        );

        if (uris.isNotEmpty) {
          final firstUri = Uri.tryParse(uris.first);
          if (firstUri != null) {
            item.add(Formats.uri(NamedUri(firstUri)));
          }
          item.add(Formats.plainText(uris.join('\n')));
        }

        request.session.dragCompleted.addListener(() {
          final op = request.session.dragCompleted.value;
          debugPrint(
              '[DRAG] DraggableRemoteAlbumItem drag completed for "$title". Result operation: $op');
        });
        return item;
      },
      dragBuilder: (context, child) {
        debugPrint(
            '[DRAG] DraggableRemoteAlbumItem.dragBuilder called for: $title');
        final l10n = AppLocalizations.of(context)!;
        if (isBatch) {
          return AppDraggablePreviewCard(
            title: title,
            subtitle: l10n.selectedAlbumsCount(selectedAlbumIds!.length),
            defaultIcon: Icons.album_rounded,
            badgeText: '${selectedAlbumIds!.length}',
            count: selectedAlbumIds!.length,
            isBatch: true,
          );
        }
        return AppDraggablePreviewCard(
          title: title,
          subtitle: artist.isNotEmpty
              ? artist
              : (isJellyfin ? l10n.jellyfinAlbum : l10n.navidromeAlbum),
          defaultIcon: Icons.album_rounded,
          badgeText: songCount != null && songCount! > 0
              ? l10n.songsCountFormat(songCount!)
              : null,
          count: songCount ?? 1,
        );
      },
      child: child,
    );
  }
}
