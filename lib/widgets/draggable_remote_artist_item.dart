import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/draggable_preview_card.dart';

/// Wraps a remote artist item widget (Navidrome / Jellyfin) to provide system-level native drag source support.
/// Enables dragging a remote artist into queue drawer, standalone queue window, or custom playlists.
class DraggableRemoteArtistItem extends StatelessWidget {
  final RemoteServer server;
  final Map<String, dynamic> artist;
  final Widget child;
  final bool enabled;
  final bool isSelectionMode;
  final bool isSelected;
  final Set<String>? selectedArtistIds;
  final List<Map<String, dynamic>>? allArtists;

  const DraggableRemoteArtistItem({
    super.key,
    required this.server,
    required this.artist,
    required this.child,
    this.enabled = true,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedArtistIds,
    this.allArtists,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || !DesktopDraggableWrapper.isPlatformSupported) {
      return child;
    }

    final artistId = artist['id'] as String? ?? '';
    final artistName = artist['name'] as String? ?? '未知艺术家';
    final albumCount = artist['albumCount'] as int? ?? 0;
    final isJellyfin = server.type == RemoteServerType.jellyfin;
    final scheme = isJellyfin ? 'jellyfin-artist' : 'subsonic-artist';

    final isBatch = isSelectionMode &&
        isSelected &&
        selectedArtistIds != null &&
        selectedArtistIds!.length > 1;

    return DesktopDraggableWrapper(
      enabled: enabled,
      dragItemProvider: (request) async {
        debugPrint(
            '[DRAG] DraggableRemoteArtistItem.dragItemProvider called for: $artistName (id: $artistId, isBatch: $isBatch)');
        final List<String> uris;
        if (isBatch) {
          uris = selectedArtistIds!
              .map((id) => '$scheme://${server.id}/$id')
              .toList();
        } else {
          uris = ['$scheme://${server.id}/$artistId'];
        }

        final item = DragItem(
          localData: <String, dynamic>{
            'type': 'remote_artist',
            'serverId': server.id,
            'artistId': artistId,
            'name': artistName,
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
              '[DRAG] DraggableRemoteArtistItem drag completed for "$artistName". Result operation: $op');
        });
        return item;
      },
      dragBuilder: (context, child) {
        debugPrint(
            '[DRAG] DraggableRemoteArtistItem.dragBuilder called for: $artistName');
        if (isBatch) {
          return AppDraggablePreviewCard(
            title: artistName,
            subtitle: '已选择 ${selectedArtistIds!.length} 位艺术家',
            defaultIcon: Icons.person_rounded,
            badgeText: '${selectedArtistIds!.length}位',
            count: selectedArtistIds!.length,
            isBatch: true,
          );
        }
        final serverLabel = isJellyfin ? 'Jellyfin 艺术家' : 'Navidrome 艺术家';
        final subtitle = albumCount > 0 ? '$albumCount 张专辑' : serverLabel;
        return AppDraggablePreviewCard(
          title: artistName,
          subtitle: subtitle,
          defaultIcon: Icons.person_rounded,
          badgeText: albumCount > 0 ? '$albumCount专' : null,
          count: 1,
        );
      },
      child: child,
    );
  }
}
