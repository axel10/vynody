import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/remote/widgets/remote_library_search_tab.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/remote_artwork_widget.dart';

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
              isArtistSelectionMode: false,
              isAlbumSelectionMode: false,
              isSongSelectionMode: false,
              selectedArtistIds: const {},
              selectedAlbumIds: const {},
              selectedSongPaths: const {},
              lastSongAnchorIndex: null,
              onSetSongSelection: (_) {},
              onToggleSongSelection: (_) {},
              onUpdateSongAnchor: (_) {},
              onToggleArtistSelection: (_) {},
              onToggleAlbumSelection: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  SliverChildBuilderDelegate delegateOf(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView).first).childrenDelegate
          as SliverChildBuilderDelegate;

  testWidgets('500 条歌曲结果只建可见行，不再一次性展开全部 item',
      (tester) async {
    await tester.pumpWidget(wrap(searchedSongs: songs(500)));
    await tester.pump();

    // header + 500 行，交给 builder 按需构建。
    expect(delegateOf(tester).childCount, 501);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
    expect(find.byType(RemoteArtworkWidget), findsNothing);
  });

  testWidgets('三段都有结果时 section 偏移映射正确', (tester) async {
    await tester.pumpWidget(wrap(
      searchedSongs: songs(3),
      searchedAlbums: [
        {'id': 'al-1', 'name': 'A1', 'coverArt': null},
        {'id': 'al-2', 'name': 'A2', 'coverArt': null},
      ],
      searchedArtists: [
        {'id': 'ar-1', 'name': 'R1', 'coverArt': null},
        {'id': 'ar-2', 'name': 'R2', 'coverArt': null},
      ],
    ));
    await tester.pump();

    // artists 4（header + 2 行 + spacer）+ albums 3 + songs 4（header + 3 行）。
    expect(delegateOf(tester).childCount, 11);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
    // 横向专辑条仍是独立懒加载列表。
    expect(find.byType(ListView), findsNWidgets(2));
  });
}
