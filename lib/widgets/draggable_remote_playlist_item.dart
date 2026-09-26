import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/draggable_preview_card.dart';

/// Wraps a remote playlist item widget (Navidrome / Jellyfin) to provide system-level native drag source support.
/// Enables dragging a remote playlist into queue drawer, standalone queue window, or custom playlists.
class DraggableRemotePlaylistItem extends StatelessWidget {
  final RemoteServer server;
  final Map<String, dynamic> playlist;
  final Widget child;
  final bool enabled;
  final bool isSelectionMode;
  final bool isSelected;
  final Set<String>? selectedPlaylistIds;
  final List<Map<String, dynamic>>? allPlaylists;
  final int? songCount;

  const DraggableRemotePlaylistItem({
    super.key,
    required this.server,
    required this.playlist,
    required this.child,
    this.enabled = true,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedPlaylistIds,
    this.allPlaylists,
    this.songCount,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || !DesktopDraggableWrapper.isPlatformSupported) {
      return child;
    }

    final playlistId = playlist['id'] as String? ?? '';
    final playlistName = playlist['name'] as String? ?? '未知歌单';
    final count = songCount ?? playlist['songCount'] as int? ?? 0;
    final isJellyfin = server.type == RemoteServerType.jellyfin;
    final scheme = isJellyfin ? 'jellyfin-playlist' : 'subsonic-playlist';

    final isBatch = isSelectionMode &&
        isSelected &&
        selectedPlaylistIds != null &&
        selectedPlaylistIds!.length > 1;

    return DesktopDraggableWrapper(
      enabled: enabled,
      dragItemProvider: (request) async {
        debugPrint(
            '[DRAG] DraggableRemotePlaylistItem.dragItemProvider called for: $playlistName (id: $playlistId, isBatch: $isBatch)');
        final List<String> uris;
        if (isBatch) {
          uris = selectedPlaylistIds!
              .map((id) => '$scheme://${server.id}/$id')
              .toList();
        } else {
          uris = ['$scheme://${server.id}/$playlistId'];
        }

        final item = DragItem(
          localData: <String, dynamic>{
            'type': 'remote_playlist',
            'serverId': server.id,
            'playlistId': playlistId,
            'name': playlistName,
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
              '[DRAG] DraggableRemotePlaylistItem drag completed for "$playlistName". Result operation: $op');
        });
        return item;
      },
      dragBuilder: (context, child) {
        debugPrint(
            '[DRAG] DraggableRemotePlaylistItem.dragBuilder called for: $playlistName');
        if (isBatch) {
          return AppDraggablePreviewCard(
            title: playlistName,
            subtitle: '已选择 ${selectedPlaylistIds!.length} 个歌单',
            defaultIcon: Icons.queue_music_rounded,
            badgeText: '${selectedPlaylistIds!.length}个',
            count: selectedPlaylistIds!.length,
            isBatch: true,
          );
        }
        final serverLabel = isJellyfin ? 'Jellyfin 歌单' : 'Navidrome 歌单';
        final subtitle = count > 0 ? '$count 首歌曲' : serverLabel;
        return AppDraggablePreviewCard(
          title: playlistName,
          subtitle: subtitle,
          defaultIcon: Icons.queue_music_rounded,
          badgeText: count > 0 ? '$count首' : null,
          count: count > 0 ? count : 1,
        );
      },
      child: child,
    );
  }
}
