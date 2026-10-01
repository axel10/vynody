import 'package:audio_core/audio_core.dart';
import 'package:audio_core/src/audio_engine/audio_engine_interface.dart';
import 'package:audio_core/src/player_models.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: invalid_use_of_internal_member
class MockCorruptedAudioParent implements AudioVisualizerParent {
  final Set<String> corruptedUris = <String>{};
  AudioTrack? lastLoadedTrack;
  bool cleared = false;

  @override
  AudioEngine get engine => throw UnimplementedError();

  @override
  Future<void> clearPlayback() async {
    cleared = true;
    lastLoadedTrack = null;
  }

  @override
  Future<void> loadTrack({
    required bool autoPlay,
    Duration? position,
    PlaybackReason reason = PlaybackReason.playlistChanged,
    FadeSettings? fadeSetting,
  }) async {
    // Determine the current track being loaded from playlist
    if (_currentPlaylist != null) {
      final track = _currentPlaylist!.currentTrack;
      if (track != null && corruptedUris.contains(track.uri)) {
        throw Exception('decode failed: The format of the data has not been recognized.');
      }
      lastLoadedTrack = track;
    }
  }

  PlaylistController? _currentPlaylist;

  void attachPlaylist(PlaylistController playlist) {
    _currentPlaylist = playlist;
  }

  @override
  Future<bool> handlePlayRequested() async => false;

  @override
  Future<bool> canPlayTrack(AudioTrack track) async => true;

  @override
  Future<String> resolvePlayableUri(String rawUri) async => rawUri;

  @override
  void notifyListeners() {}
}

void main() {
  late MockCorruptedAudioParent parent;
  late PlaylistController playlist;

  setUp(() {
    parent = MockCorruptedAudioParent();
    playlist = PlaylistController(parent: parent);
    parent.attachPlaylist(playlist);
  });

  test('auto skips corrupted song to the next valid song during playNext', () async {
    const track1 = AudioTrack(id: '1', uri: '/music/track1.mp3', title: 'Track 1');
    const track2 = AudioTrack(id: '2', uri: '/music/corrupted.mp3', title: 'Corrupted Track');
    const track3 = AudioTrack(id: '3', uri: '/music/track3.mp3', title: 'Track 3');

    parent.corruptedUris.add('/music/corrupted.mp3');

    await playlist.addTracks([track1, track2, track3]);
    expect(playlist.currentIndex, 0);
    expect(parent.lastLoadedTrack?.id, '1');

    // Attempt to play next (track 2 is corrupted, should automatically advance to track 3)
    final success = await playlist.playNext();

    expect(success, isTrue);
    expect(playlist.currentIndex, 2);
    expect(playlist.currentTrack?.id, '3');
    expect(parent.lastLoadedTrack?.id, '3');
  });

  test('auto skips multiple consecutive corrupted songs until valid song is found', () async {
    const track1 = AudioTrack(id: '1', uri: '/music/track1.mp3', title: 'Track 1');
    const track2 = AudioTrack(id: '2', uri: '/music/corrupted1.mp3', title: 'Corrupted 1');
    const track3 = AudioTrack(id: '3', uri: '/music/corrupted2.mp3', title: 'Corrupted 2');
    const track4 = AudioTrack(id: '4', uri: '/music/track4.mp3', title: 'Track 4');

    parent.corruptedUris.addAll(['/music/corrupted1.mp3', '/music/corrupted2.mp3']);

    await playlist.addTracks([track1, track2, track3, track4]);
    expect(playlist.currentIndex, 0);

    final success = await playlist.playNext();

    expect(success, isTrue);
    expect(playlist.currentIndex, 3);
    expect(playlist.currentTrack?.id, '4');
    expect(parent.lastLoadedTrack?.id, '4');
  });

  test('stops playback and clears when there is no next playable song', () async {
    const track1 = AudioTrack(id: '1', uri: '/music/track1.mp3', title: 'Track 1');
    const track2 = AudioTrack(id: '2', uri: '/music/corrupted.mp3', title: 'Corrupted Track');

    parent.corruptedUris.add('/music/corrupted.mp3');

    await playlist.addTracks([track1, track2]);
    expect(playlist.currentIndex, 0);

    final success = await playlist.playNext();

    expect(success, isFalse);
    expect(playlist.currentTrack, isNull);
    expect(parent.cleared, isTrue);
  });

  test('stops playback when all songs in the playlist are corrupted', () async {
    const track1 = AudioTrack(id: '1', uri: '/music/corrupted1.mp3', title: 'Corrupted 1');
    const track2 = AudioTrack(id: '2', uri: '/music/corrupted2.mp3', title: 'Corrupted 2');

    parent.corruptedUris.addAll(['/music/corrupted1.mp3', '/music/corrupted2.mp3']);

    await playlist.addTracks([track1, track2]);

    expect(playlist.currentTrack, isNull);
    expect(parent.cleared, isTrue);
  });
}
