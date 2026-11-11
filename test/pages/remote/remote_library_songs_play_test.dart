import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/remote/widgets/remote_library_songs_tab.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/settings/settings_service.dart';

class _MockAudioService extends Fake implements AudioService {
  List<MusicFile>? playedPlaylist;
  PlaybackSource? playedSource;

  @override
  Future<void> playPlaylist(
    List<MusicFile> songs, {
    int initialIndex = 0,
    PlaybackSource? source,
  }) async {
    playedPlaylist = songs;
    playedSource = source;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final server = RemoteServer(
    id: 'test_server',
    name: 'Test Server',
    type: RemoteServerType.subsonic,
    url: 'http://127.0.0.1:4533',
    username: 'testuser',
    createdAt: DateTime(2026, 1, 1),
  );

  final songs = List<MusicFile>.generate(
    5,
    (i) => MusicFile(
      path: 'subsonic://test_server/$i',
      name: 'Song $i',
      title: 'Song $i',
      artist: 'Artist $i',
    ),
  );

  Future<_MockAudioService> pumpView(
    WidgetTester tester, {
    bool starredOnly = false,
    String searchQuery = '',
    bool hasMore = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 800) * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    final mockAudio = _MockAudioService();

    final searchController = TextEditingController(text: searchQuery);
    final searchFocusNode = FocusNode();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
          audioServiceProvider.overrideWith((ref) => mockAudio),
          audioCurrentMusicProvider.overrideWith((ref) => null),
          audioIsPlayingProvider.overrideWith((ref) => false),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RemoteLibrarySongsView(
              server: server,
              password: 'pwd',
              songs: songs,
              totalServerSongsCount: songs.length,
              starredSongIds: const {'0', '1'},
              starredOnly: starredOnly,
              isLoading: false,
              isLoadingMore: false,
              hasMore: hasMore,
              error: null,
              onRefresh: () async {},
              onLoadMore: () {},
              searchQuery: searchQuery,
              bottomOffset: 0,
              isSelectionMode: false,
              selectedSongPaths: const <String>{},
              lastSongAnchorIndex: null,
              onSetSelection: (_) {},
              onToggleSelection: (_) {},
              onUpdateAnchor: (_) {},
              onToggleStar: (_) {},
              toolbar: RemoteLibrarySongsToolbar(
                searchController: searchController,
                searchFocusNode: searchFocusNode,
                searchQuery: searchQuery,
                onSearchChanged: (_) {},
                onClearSearch: () {},
                starredOnly: starredOnly,
                onToggleStarredOnly: (_) {},
                onSortPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return mockAudio;
  }

  testWidgets('开收藏筛选时点击随机播放：直接针对当前已获取的歌曲随机播放，不走全库', (tester) async {
    final mockAudio = await pumpView(tester, starredOnly: true);

    final shuffleButton = find.byIcon(Icons.shuffle_rounded);
    expect(shuffleButton, findsOneWidget);
    await tester.tap(shuffleButton);
    await tester.pumpAndSettle();

    expect(mockAudio.playedPlaylist, isNotNull);
    expect(mockAudio.playedPlaylist!.length, songs.length);
    expect(mockAudio.playedSource?.id, 'remote-test_server-songs-starred');
    expect(mockAudio.playedSource?.name, '我喜欢的音乐');
  });

  testWidgets('开收藏筛选时点击播放全部：直接播放当前列表，不触发全库续拉', (tester) async {
    final mockAudio = await pumpView(tester, starredOnly: true, hasMore: true);

    final playAllButton = find.byIcon(Icons.play_arrow_rounded);
    expect(playAllButton, findsOneWidget);
    await tester.tap(playAllButton);
    await tester.pumpAndSettle();

    expect(mockAudio.playedPlaylist, isNotNull);
    expect(mockAudio.playedPlaylist!.length, songs.length);
    expect(mockAudio.playedSource?.id, 'remote-test_server-songs-starred');
  });

  testWidgets('有搜索筛选时点击随机播放：直接针对搜索结果随机播放', (tester) async {
    final mockAudio = await pumpView(tester, searchQuery: 'Song');

    final shuffleButton = find.byIcon(Icons.shuffle_rounded);
    expect(shuffleButton, findsOneWidget);
    await tester.tap(shuffleButton);
    await tester.pumpAndSettle();

    expect(mockAudio.playedPlaylist, isNotNull);
    expect(mockAudio.playedPlaylist!.length, songs.length);
    expect(mockAudio.playedSource?.id, 'remote-test_server-songs');
    expect(mockAudio.playedSource?.name, '歌曲');
  });

  testWidgets('无任何筛选且无更多数据时：直接播放全部歌曲', (tester) async {
    final mockAudio = await pumpView(tester, starredOnly: false, searchQuery: '', hasMore: false);

    final playAllButton = find.byIcon(Icons.play_arrow_rounded);
    expect(playAllButton, findsOneWidget);
    await tester.tap(playAllButton);
    await tester.pumpAndSettle();

    expect(mockAudio.playedPlaylist, isNotNull);
    expect(mockAudio.playedPlaylist!.length, songs.length);
    expect(mockAudio.playedSource?.id, 'remote-test_server-songs');
  });
}
