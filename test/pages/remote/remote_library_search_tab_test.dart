import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/remote/widgets/remote_library_search_tab.dart';
import 'package:vynody/player/remote/remote_server_models.dart';

void main() {
  final server = RemoteServer(
    id: 'server-1',
    name: 'Test',
    type: RemoteServerType.subsonic,
    url: 'http://127.0.0.1:4533',
    username: 'tester',
    createdAt: DateTime(2026),
  );

  List<MusicFile> songs(int count) => List.generate(
        count,
        (i) => MusicFile(
          path: 'remote://song-$i',
          name: 'Song $i',
          artist: 'Artist $i',
          album: 'Album $i',
        ),
      );

  Widget wrap({
    List<MusicFile>? searchedSongs,
    List<Map<String, dynamic>>? searchedAlbums,
    List<Map<String, dynamic>>? searchedArtists,
    Set<String> selectedKeys = const {},
    void Function(String key)? onToggleSelection,
    void Function(Set<String> keys)? onSetSelection,
  }) {
    return ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: RemoteLibrarySearchView(
              server: server,
              password: 'pw',
              searchController: TextEditingController(text: 'query'),
              searchedSongs: searchedSongs ?? const [],
              searchedAlbums: searchedAlbums ?? const [],
              searchedArtists: searchedArtists ?? const [],
              bottomOffset: 0,
              isSelectionMode: selectedKeys.isNotEmpty,
              selectedKeys: selectedKeys,
              lastAnchorIndex: null,
              onSetSelection: onSetSelection ?? (_) {},
              onToggleSelection: onToggleSelection ?? (_) {},
              onUpdateAnchor: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('500 条歌曲结果只建可见行，不再一次性展开全部 item',
      (tester) async {
    await tester.pumpWidget(wrap(searchedSongs: songs(500)));
    await tester.pump();

    expect(find.byType(ListTile).evaluate().length, lessThan(30));
  });

  test('三段键序列按视觉顺序拼接：艺术家 → 专辑 → 歌曲', () {
    final keys = RemoteLibrarySearchView.entryKeysFor(
      artists: [
        {'id': 'ar-1'},
        {'id': 'ar-2'},
      ],
      albums: [
        {'id': 'al-1'},
      ],
      songs: songs(2),
    );

    expect(keys, [
      'artist:ar-1',
      'artist:ar-2',
      'album:al-1',
      'song:remote://song-0',
      'song:remote://song-1',
    ]);
  });

  test('残缺条目照样占位，避免后面条目的下标整体偏移', () {
    final keys = RemoteLibrarySearchView.entryKeysFor(
      artists: [
        {'name': '无 id'},
      ],
      albums: const [],
      songs: songs(1),
    );

    expect(keys.length, 2);
    expect(keys.last, 'song:remote://song-0');
  });

  testWidgets('长按专辑卡片进入多选，键带类型前缀', (tester) async {
    final toggled = <String>[];
    await tester.pumpWidget(wrap(
      searchedAlbums: [
        {'id': 'al-1', 'name': 'A1', 'coverArt': null},
      ],
      searchedSongs: songs(1),
      onToggleSelection: toggled.add,
    ));
    await tester.pump();

    await tester.longPress(find.text('A1'));
    await tester.pump();

    expect(toggled, ['album:al-1']);
  });

  testWidgets('长按歌曲行进入多选，键带类型前缀', (tester) async {
    final toggled = <String>[];
    await tester.pumpWidget(wrap(
      searchedSongs: songs(2),
      onToggleSelection: toggled.add,
    ));
    await tester.pump();

    await tester.longPress(find.text('Song 1'));
    await tester.pump();

    expect(toggled, ['song:remote://song-1']);
  });

  testWidgets('混选态下三段都显示勾选，多选态点击切换该条', (tester) async {
    final toggled = <String>[];
    await tester.pumpWidget(wrap(
      searchedArtists: [
        {'id': 'ar-1', 'name': 'R1', 'coverArt': null},
      ],
      searchedAlbums: [
        {'id': 'al-1', 'name': 'A1', 'coverArt': null},
      ],
      searchedSongs: songs(1),
      // 艺术家 + 专辑 + 歌曲同时选中：这正是搜索页跨栏目多选的目标状态。
      selectedKeys: const {
        'artist:ar-1',
        'album:al-1',
        'song:remote://song-0',
      },
      onToggleSelection: toggled.add,
    ));
    await tester.pump();

    // 艺术家行与歌曲行的勾选圈（专辑卡用的是 Checkbox）。
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);

    // 多选态下点歌曲行 = 切换该条，不触发播放。
    await tester.tap(find.text('Song 0'));
    await tester.pump();
    expect(toggled, ['song:remote://song-0']);
  });
}
