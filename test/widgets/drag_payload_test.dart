import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';

/// Regression tests for the drag payload vocabulary.
///
/// The virtual path format defined by [RemoteCollectionRef] is the *only*
/// channel that survives a drag into the standalone queue window (a separate
/// isolate) or another application. If encode and decode ever drift apart,
/// dropping a remote album/artist/playlist silently stops working, so the
/// round trip is pinned down here.
void main() {
  group('RemoteCollectionRef round trip', () {
    test('encodes a subsonic album as a subsonic-album virtual path', () {
      const ref = RemoteCollectionRef(
        serverType: RemoteServerType.subsonic,
        serverId: 'server-1',
        kind: RemoteCollectionKind.album,
        id: 'album-42',
      );

      expect(ref.toVirtualPath(), 'subsonic-album://server-1/album-42');
      expect(ref.scheme, 'subsonic-album');
    });

    test('encodes a jellyfin playlist as a jellyfin-playlist virtual path', () {
      const ref = RemoteCollectionRef(
        serverType: RemoteServerType.jellyfin,
        serverId: 'abc',
        kind: RemoteCollectionKind.playlist,
        id: 'pl-7',
      );

      expect(ref.toVirtualPath(), 'jellyfin-playlist://abc/pl-7');
    });

    test('decodes every kind and server type back to the original reference',
        () {
      for (final serverType in RemoteServerType.values) {
        // Only subsonic and jellyfin libraries expose albums/artists/playlists.
        if (serverType != RemoteServerType.subsonic &&
            serverType != RemoteServerType.jellyfin) {
          continue;
        }
        for (final kind in RemoteCollectionKind.values) {
          final original = RemoteCollectionRef(
            serverType: serverType,
            serverId: 'srv_1699999999999_${kind.index}',
            kind: kind,
            id: 'id-${kind.slug}',
          );

          final decoded = RemoteCollectionRef.tryParse(original.toVirtualPath());

          expect(decoded, isNotNull, reason: '$original did not decode');
          expect(decoded!.serverType, serverType);
          expect(decoded.kind, kind);
          expect(decoded.serverId, original.serverId);
          expect(decoded.id, original.id);
        }
      }
    });

    test('lowercases the server id, because Uri normalises the authority', () {
      // Server ids are generated as `srv_<millis>_<random>` (all lowercase), and
      // the per-track `subsonic://`/`webdav://`/`smb://` URIs already put the id
      // in the authority position, so the same constraint applies here. Pinned
      // so that changing the id format is a conscious decision.
      const ref = RemoteCollectionRef(
        serverType: RemoteServerType.subsonic,
        serverId: 'srv_1699999999999_1',
        kind: RemoteCollectionKind.album,
        id: 'album-42',
      );

      expect(ref.serverId, ref.serverId.toLowerCase());
      expect(
        RemoteCollectionRef.tryParse('subsonic-album://srv_1/album-42')?.serverId,
        'srv_1',
      );
    });

    test('preserves ids that contain slashes', () {
      const ref = RemoteCollectionRef(
        serverType: RemoteServerType.subsonic,
        serverId: 'server-1',
        kind: RemoteCollectionKind.album,
        id: 'library/album-42',
      );

      expect(RemoteCollectionRef.tryParse(ref.toVirtualPath())?.id,
          'library/album-42');
    });

    test('rejects ordinary local file paths', () {
      expect(RemoteCollectionRef.tryParse('/music/artist/track.flac'), isNull);
      expect(RemoteCollectionRef.tryParse('C:\\Music\\track.mp3'), isNull);
      expect(RemoteCollectionRef.tryParse(''), isNull);
    });

    test('rejects per-track remote URIs so they keep their own resolver', () {
      expect(RemoteCollectionRef.tryParse('subsonic://server-1/track-9'), isNull);
      expect(RemoteCollectionRef.tryParse('jellyfin://server-1/track-9'), isNull);
      expect(
        RemoteCollectionRef.tryParse('webdav://server-1/dir/track.flac'),
        isNull,
      );
    });

    test('rejects unknown collection kinds and server prefixes', () {
      expect(
        RemoteCollectionRef.tryParse('subsonic-mounted://server-1/x'),
        isNull,
      );
      expect(RemoteCollectionRef.tryParse('smb-album://server-1/x'), isNull);
      expect(RemoteCollectionRef.tryParse('subsonic-album://server-1'), isNull);
      expect(RemoteCollectionRef.tryParse('subsonic-album:///album-1'), isNull);
    });
  });

  group('DragPayload.localData', () {
    test('single song exposes both path and paths', () {
      const payload = SongPathsPayload(paths: ['/music/a.flac']);

      expect(payload.localData['path'], '/music/a.flac');
      expect(payload.localData['paths'], ['/music/a.flac']);
    });

    test('batch song exposes only paths', () {
      const payload = SongPathsPayload(paths: ['/music/a.flac', '/music/b.flac']);

      expect(payload.localData.containsKey('path'), isFalse);
      expect(payload.localData['paths'], ['/music/a.flac', '/music/b.flac']);
    });

    test('flattened keeps selection order and collapses shared songs', () {
      final payload = SongPathsPayload.flattened([
        [
          const MusicFile(path: '/music/a.flac', name: 'a.flac'),
          const MusicFile(path: '/music/b.flac', name: 'b.flac'),
        ],
        [
          // b.flac appears under two artists / genres / years.
          const MusicFile(path: '/music/b.flac', name: 'b.flac'),
          const MusicFile(path: '/music/c.flac', name: 'c.flac'),
        ],
      ]);

      expect(payload.paths, ['/music/a.flac', '/music/b.flac', '/music/c.flac']);
    });

    test('folder prefers resolved songs over the raw folder path', () {
      const payload = FolderDragPayload(
        folderPath: '/music/album',
        songPaths: ['/music/album/a.flac'],
      );

      expect(payload.localData['path'], '/music/album');
      expect(payload.localData['paths'], ['/music/album/a.flac']);
    });

    test('folder without resolved songs falls back to the folder path', () {
      const payload = FolderDragPayload(
        folderPath: '/music/album',
        songPaths: [],
      );

      expect(payload.localData['path'], '/music/album');
      expect(payload.localData.containsKey('paths'), isFalse);
    });

    test('remote collection publishes one virtual path per selected item', () {
      const payload = RemoteCollectionPayload([
        RemoteCollectionRef(
          serverType: RemoteServerType.subsonic,
          serverId: 'server-1',
          kind: RemoteCollectionKind.artist,
          id: 'a-1',
        ),
        RemoteCollectionRef(
          serverType: RemoteServerType.subsonic,
          serverId: 'server-1',
          kind: RemoteCollectionKind.artist,
          id: 'a-2',
        ),
      ]);

      expect(payload.count, 2);
      expect(payload.localData['paths'], [
        'subsonic-artist://server-1/a-1',
        'subsonic-artist://server-1/a-2',
      ]);
    });
  });
}
