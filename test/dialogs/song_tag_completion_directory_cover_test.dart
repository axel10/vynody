import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/dialogs/directory_cover_scope.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

void main() {
  group('evaluateDirectoryCoverScope', () {
    test('unlocks when 2+ library tracks in same dir share non-empty album', () {
      const s1 = SongMetadata(
        path: '/music/albumA/01.flac',
        title: 'Track 1',
        album: '  Fantasy ',
        artist: 'Jay',
        sourceFlags: SongSourceFlags.rootScan,
      );
      const s2 = SongMetadata(
        path: '/music/albumA/02.flac',
        title: 'Track 2',
        album: 'Fantasy',
        artist: 'Jay',
        sourceFlags: SongSourceFlags.rootScan,
      );
      const subDirTrack = SongMetadata(
        path: '/music/albumA/bonus/03.flac',
        title: 'Bonus',
        album: 'Other Album',
        artist: 'Jay',
        sourceFlags: SongSourceFlags.rootScan,
      );

      final scope = evaluateDirectoryCoverScope(
        songPath: s1.path,
        metadataMap: {
          s1.path: s1,
          s2.path: s2,
          subDirTrack.path: subDirTrack,
        },
        isWindowsOverride: false,
      );

      expect(scope.isEligible, isTrue);
      expect(scope.reason, DirectoryCoverEligibilityReason.eligible);
      expect(scope.albumName, 'Fantasy');
      expect(scope.siblingSongs.map((s) => s.path), [s2.path]);
    });

    test('disables for externally opened or remote or content:// tracks', () {
      const externalSong = SongMetadata(
        path: '/storage/emulated/0/Download/01.mp3',
        title: 'Track 1',
        album: 'Fantasy',
        artist: 'Jay',
        sourceFlags: SongSourceFlags.external,
      );
      const sibling = SongMetadata(
        path: '/storage/emulated/0/Download/02.mp3',
        title: 'Track 2',
        album: 'Fantasy',
        artist: 'Jay',
        sourceFlags: SongSourceFlags.external,
      );

      final extScope = evaluateDirectoryCoverScope(
        songPath: externalSong.path,
        metadataMap: {
          externalSong.path: externalSong,
          sibling.path: sibling,
        },
      );
      expect(extScope.isEligible, isFalse);
      expect(extScope.reason, DirectoryCoverEligibilityReason.externalOrRemote);

      final remoteScope = evaluateDirectoryCoverScope(
        songPath: 'webdav://server/album/01.mp3',
        metadataMap: const {},
      );
      expect(remoteScope.isEligible, isFalse);
      expect(
        remoteScope.reason,
        DirectoryCoverEligibilityReason.externalOrRemote,
      );

      final contentScope = evaluateDirectoryCoverScope(
        songPath: 'content://media/external/audio/media/42',
        metadataMap: const {},
      );
      expect(contentScope.isEligible, isFalse);
      expect(
        contentScope.reason,
        DirectoryCoverEligibilityReason.externalOrRemote,
      );
    });

    test('disables when directory only has one track', () {
      const s1 = SongMetadata(
        path: '/music/single/01.mp3',
        title: 'Only One',
        album: 'Single',
        artist: 'Artist',
        sourceFlags: SongSourceFlags.rootScan,
      );

      final scope = evaluateDirectoryCoverScope(
        songPath: s1.path,
        metadataMap: {s1.path: s1},
        isWindowsOverride: false,
      );

      expect(scope.isEligible, isFalse);
      expect(scope.reason, DirectoryCoverEligibilityReason.singleTrack);
    });

    test('disables when albums differ or are empty/unknown', () {
      const s1 = SongMetadata(
        path: '/music/mixed/01.mp3',
        title: 'T1',
        album: 'Album A',
        artist: 'Artist',
        sourceFlags: SongSourceFlags.rootScan,
      );
      const s2 = SongMetadata(
        path: '/music/mixed/02.mp3',
        title: 'T2',
        album: 'Album B',
        artist: 'Artist',
        sourceFlags: SongSourceFlags.rootScan,
      );

      final diffScope = evaluateDirectoryCoverScope(
        songPath: s1.path,
        metadataMap: {s1.path: s1, s2.path: s2},
        isWindowsOverride: false,
      );
      expect(diffScope.isEligible, isFalse);
      expect(
        diffScope.reason,
        DirectoryCoverEligibilityReason.inconsistentOrEmptyAlbum,
      );

      const empty1 = SongMetadata(
        path: '/music/empty/01.mp3',
        title: 'T1',
        album: '',
        artist: 'Artist',
        sourceFlags: SongSourceFlags.rootScan,
      );
      const empty2 = SongMetadata(
        path: '/music/empty/02.mp3',
        title: 'T2',
        album: '   ',
        artist: 'Artist',
        sourceFlags: SongSourceFlags.rootScan,
      );

      final emptyScope = evaluateDirectoryCoverScope(
        songPath: empty1.path,
        metadataMap: {empty1.path: empty1, empty2.path: empty2},
        isWindowsOverride: false,
      );
      expect(emptyScope.isEligible, isFalse);
      expect(
        emptyScope.reason,
        DirectoryCoverEligibilityReason.inconsistentOrEmptyAlbum,
      );

      const unknown1 = SongMetadata(
        path: '/music/unk/01.mp3',
        title: 'T1',
        album: '未知专辑',
        artist: 'Artist',
        sourceFlags: SongSourceFlags.rootScan,
      );
      const unknown2 = SongMetadata(
        path: '/music/unk/02.mp3',
        title: 'T2',
        album: '未知专辑',
        artist: 'Artist',
        sourceFlags: SongSourceFlags.rootScan,
      );

      final unknownScope = evaluateDirectoryCoverScope(
        songPath: unknown1.path,
        metadataMap: {unknown1.path: unknown1, unknown2.path: unknown2},
        unknownAlbumLabel: '未知专辑',
        isWindowsOverride: false,
      );
      expect(unknownScope.isEligible, isFalse);
      expect(
        unknownScope.reason,
        DirectoryCoverEligibilityReason.inconsistentOrEmptyAlbum,
      );
    });

    test('handles Windows backslash paths case-insensitively', () {
      const s1 = SongMetadata(
        path: r'D:\Music\Jay\01.flac',
        title: 'T1',
        album: 'Ye Hui Mei',
        artist: 'Jay',
        sourceFlags: SongSourceFlags.rootScan,
      );
      const s2 = SongMetadata(
        path: r'd:\music\jay\02.flac',
        title: 'T2',
        album: 'Ye Hui Mei',
        artist: 'Jay',
        sourceFlags: SongSourceFlags.rootScan,
      );

      final scope = evaluateDirectoryCoverScope(
        songPath: s1.path,
        metadataMap: {s1.path: s1, s2.path: s2},
        isWindowsOverride: true,
      );
      expect(scope.isEligible, isTrue);
      expect(scope.siblingSongs.length, 1);
    });
  });
}
