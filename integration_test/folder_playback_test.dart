import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/pages/folder_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_service.dart';

final currentSongNotifierProvider =
    ChangeNotifierProvider<ValueNotifier<MusicFile?>>((ref) {
      throw UnimplementedError();
    });

final isPlayingNotifierProvider = ChangeNotifierProvider<ValueNotifier<bool>>((
  ref,
) {
  throw UnimplementedError();
});

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tap a song in the folder page starts playback', (tester) async {
    final currentSongNotifier = ValueNotifier<MusicFile?>(null);
    final isPlayingNotifier = ValueNotifier<bool>(false);
    final playbackOpenCompleter = Completer<void>();

    final songA = _makeSong(
      path: '/music/alpha.mp3',
      name: 'alpha.mp3',
      title: 'Alpha',
    );
    final songB = _makeSong(
      path: '/music/beta.mp3',
      name: 'beta.mp3',
      title: 'Beta',
    );
    final folder = MusicFolder(
      path: '/music',
      name: 'Music',
      files: [songA, songB],
    );

    final scanner = _FakeScannerService(
      rootFolders: [folder],
      currentFolder: folder,
    );
    final audio = _FakeAudioService(
      currentSongNotifier: currentSongNotifier,
      isPlayingNotifier: isPlayingNotifier,
    );

    await tester.pumpWidget(
      _buildTestApp(
        scanner: scanner,
        audio: audio,
        currentSongNotifier: currentSongNotifier,
        isPlayingNotifier: isPlayingNotifier,
        onOpenPlayback: () {
          if (!playbackOpenCompleter.isCompleted) {
            playbackOpenCompleter.complete();
          }
          return Future.value();
        },
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey(songB.path)));
    await tester.pumpAndSettle();

    expect(audio.playPlaylistCallCount, 1);
    expect(audio.lastPlayList, hasLength(2));
    expect(audio.lastInitialIndex, 1);
    expect(currentSongNotifier.value?.path, songB.path);
    expect(isPlayingNotifier.value, isFalse);
    expect(playbackOpenCompleter.isCompleted, isTrue);
  });
}

Widget _buildTestApp({
  required _FakeScannerService scanner,
  required _FakeAudioService audio,
  required ValueNotifier<MusicFile?> currentSongNotifier,
  required ValueNotifier<bool> isPlayingNotifier,
  required Future<void> Function() onOpenPlayback,
}) {
  return ProviderScope(
    overrides: [
      scannerServiceProvider.overrideWith((ref) => scanner),
      audioServiceProvider.overrideWith((ref) => audio),
      currentSongNotifierProvider.overrideWith((ref) => currentSongNotifier),
      isPlayingNotifierProvider.overrideWith((ref) => isPlayingNotifier),
      audioCurrentMusicProvider.overrideWith(
        (ref) => ref.watch(currentSongNotifierProvider).value,
      ),
      audioIsPlayingProvider.overrideWith(
        (ref) => ref.watch(isPlayingNotifierProvider).value,
      ),
    ],
    child: OKToast(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FoldersPage(onOpenPlayback: onOpenPlayback),
      ),
    ),
  );
}

MusicFile _makeSong({
  required String path,
  required String name,
  String? title,
}) {
  return MusicFile(
    path: path,
    name: name,
    title: title,
    durationMillis: 180000,
  );
}

class _FakeAudioService extends AudioService {
  _FakeAudioService({
    required this.currentSongNotifier,
    required this.isPlayingNotifier,
  });

  final ValueNotifier<MusicFile?> currentSongNotifier;
  final ValueNotifier<bool> isPlayingNotifier;

  int playPlaylistCallCount = 0;
  List<MusicFile> lastPlayList = const [];
  int? lastInitialIndex;

  @override
  Future<void> playPlaylist(
    List<MusicFile> songs, {
    int initialIndex = 0,
    PlaybackSource? source,
  }) async {
    playPlaylistCallCount++;
    lastPlayList = List<MusicFile>.unmodifiable(songs);
    lastInitialIndex = initialIndex;

    if (songs.isEmpty) {
      currentSongNotifier.value = null;
      isPlayingNotifier.value = false;
      return;
    }

    final safeIndex = initialIndex.clamp(0, songs.length - 1).toInt();
    currentSongNotifier.value = songs[safeIndex];
    isPlayingNotifier.value = false;
  }
}

class _FakeScannerService extends ScannerService {
  _FakeScannerService({
    required List<MusicFolder> rootFolders,
    required MusicFolder currentFolder,
  }) : _rootFolders = List<MusicFolder>.from(rootFolders),
       _currentFolder = currentFolder,
       super(autoInitialize: false);

  final StreamController<ScanProgress> _progressController =
      StreamController<ScanProgress>.broadcast();
  List<MusicFolder> _rootFolders;
  MusicFolder? _currentFolder;
  List<MusicFolder> _history = <MusicFolder>[];

  @override
  List<MusicFolder> get rootFolders =>
      List<MusicFolder>.unmodifiable(_rootFolders);

  @override
  MusicFolder? get navigationCurrentFolder => _currentFolder;

  @override
  List<MusicFolder> get navigationHistory =>
      List<MusicFolder>.unmodifiable(_history);

  @override
  Map<String, SongMetadata> get metadataMap => const <String, SongMetadata>{};

  @override
  bool get hasPermission => true;

  @override
  bool get isScanning => false;

  @override
  Stream<ScanProgress> get scanProgressStream => _progressController.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  Future<void> checkAndRequestPermissions() async {}

  @override
  Future<void> loadThumbnailForPath(String path) async {}

  @override
  void setNavigationState(MusicFolder? current, List<MusicFolder> history) {
    _currentFolder = current;
    _history = List<MusicFolder>.from(history);
    notifyListeners();
  }

  @override
  double getFolderScrollOffset(String? path) => 0;

  @override
  void setFolderScrollOffset(String? path, double offset) {}

  @override
  void dispose() {
    _progressController.close();
    super.dispose();
  }
}
