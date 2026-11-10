import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/remote_library_dashboard_view.dart';
import 'package:vynody/player/remote/remote_server_models.dart';

/// 远程库概览页的版式约束。
///
/// 这里只覆盖「不依赖网络」的部分：板块取舍、入口回调、空数据不渲染空板块。
/// 封面卡片走 `RemoteArtworkWidget` 会发请求，所以所有用例都不带专辑数据。
void main() {
  final server = RemoteServer(
    id: 's1',
    name: 'My Navidrome',
    type: RemoteServerType.subsonic,
    url: 'http://127.0.0.1:4533',
    username: 'u',
    createdAt: DateTime(2026, 1, 1),
  );

  Widget wrap({
    List<Map<String, dynamic>> recentAlbums = const [],
    List<Map<String, dynamic>> releasedAlbums = const [],
    List<Map<String, dynamic>> recentPlayedAlbums = const [],
    List<Map<String, dynamic>> mostPlayedAlbums = const [],
    List<Map<String, dynamic>> playlists = const [],
    List<Map<String, dynamic>> favoriteAlbums = const [],
    ValueChanged<int>? onNavigateToTab,
    int playlistCount = 0,
    ThemeData? theme,
  }) {
    return MaterialApp(
      locale: const Locale('zh'),
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RemoteLibraryDashboardView(
        server: server,
        password: 'p',
        albumCount: 12,
        artistCount: 3,
        songCount: 48,
        playlistCount: playlistCount,
        recentAlbums: recentAlbums,
        releasedAlbums: releasedAlbums,
        recentPlayedAlbums: recentPlayedAlbums,
        mostPlayedAlbums: mostPlayedAlbums,
        playlists: playlists,
        favoriteAlbums: favoriteAlbums,
        onNavigateToTab: onNavigateToTab ?? (_) {},
        onOpenAlbum: (_, _) {},
        onOpenPlaylist: (_) {},
        onRefresh: () {},
        onShuffleAll: () {},
        onDisconnect: () {},
      ),
    );
  }

  testWidgets('顶部展示服务器名、类型与三组统计', (tester) async {
    await tester.pumpWidget(wrap());

    expect(find.text('My Navidrome'), findsOneWidget);
    expect(find.text('Navidrome / Subsonic'), findsOneWidget);
    // 统计行把三个计数拼在一行里，逐项断言避免本地化文案变化时误判。
    expect(find.textContaining('12'), findsWidgets);
    expect(find.textContaining('48'), findsWidgets);
  });

  testWidgets('六个快捷入口都在，点击回传对应分类索引', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(wrap(onNavigateToTab: tapped.add));

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    for (final label in [
      l10n.albums,
      l10n.artists,
      l10n.genres,
      l10n.songs,
      l10n.playlists,
      l10n.search,
    ]) {
      expect(find.text(label), findsOneWidget, reason: '缺少入口：$label');
    }

    await tester.tap(find.text(l10n.albums));
    await tester.pump();
    expect(tapped, [RemoteLibraryDashboardView.tabAlbums]);

    await tester.tap(find.text(l10n.search));
    await tester.pump();
    expect(tapped.last, RemoteLibraryDashboardView.tabSearch);
  });

  testWidgets('没有数据时不出现对应板块', (tester) async {
    await tester.pumpWidget(wrap());
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(find.text(l10n.recentlyAdded), findsNothing);
    expect(find.text(l10n.recentlyReleased), findsNothing);
    expect(find.text(l10n.recentlyPlayed), findsNothing);
    expect(find.text(l10n.mostPlayed), findsNothing);
    expect(find.text(l10n.playlist), findsNothing);
    expect(find.text(l10n.starredAlbums), findsNothing);
  });

  testWidgets('存在数据时展示对应板块与内容', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tappedTab = <int>[];
    String? openedAlbumId;
    Map<String, dynamic>? openedPlaylist;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RemoteLibraryDashboardView(
          server: server,
          password: 'p',
          albumCount: 1,
          artistCount: 1,
          songCount: 1,
          playlistCount: 1,
          recentAlbums: const [
            {'id': 'a1', 'name': '最近添加专辑', 'artist': '艺人A'}
          ],
          releasedAlbums: const [
            {'id': 'a2', 'name': '最新发布专辑', 'artist': '艺人B', 'year': 2026}
          ],
          recentPlayedAlbums: const [
            {'id': 'a3', 'name': '最近播放专辑', 'artist': '艺人C'}
          ],
          mostPlayedAlbums: const [
            {'id': 'a4', 'name': '最多播放专辑', 'artist': '艺人D'}
          ],
          playlists: const [
            {'id': 'p1', 'name': '我的精选歌单', 'songCount': 25}
          ],
          onNavigateToTab: tappedTab.add,
          onOpenAlbum: (id, _) => openedAlbumId = id,
          onOpenPlaylist: (p) => openedPlaylist = p,
          onRefresh: () {},
          onShuffleAll: () {},
          onDisconnect: () {},
        ),
      ),
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l10n.recentlyAdded), findsOneWidget);
    expect(find.text(l10n.recentlyReleased), findsOneWidget);
    expect(find.text(l10n.recentlyPlayed), findsOneWidget);
    expect(find.text(l10n.mostPlayed), findsOneWidget);
    expect(find.text(l10n.playlist), findsOneWidget);

    expect(find.text('最近添加专辑'), findsOneWidget);
    expect(find.text('最新发布专辑'), findsOneWidget);
    expect(find.text('最近播放专辑'), findsOneWidget);
    expect(find.text('最多播放专辑'), findsOneWidget);
    expect(find.text('我的精选歌单'), findsOneWidget);
    expect(find.textContaining('25'), findsWidgets);

    // 点击专辑卡片
    await tester.tap(find.text('最近添加专辑'));
    await tester.pump();
    expect(openedAlbumId, 'a1');

    // 点击歌单卡片
    await tester.tap(find.text('我的精选歌单'));
    await tester.pump();
    expect(openedPlaylist?['id'], 'p1');
  });

  testWidgets('页面外层包裹 Scaffold 并继承主题 scaffoldBackgroundColor', (tester) async {
    const customBg = Color(0xFFABCDEF);
    final theme = ThemeData(scaffoldBackgroundColor: customBg);
    await tester.pumpWidget(wrap(theme: theme));

    final scaffoldFinder = find.byType(Scaffold);
    expect(scaffoldFinder, findsOneWidget);
    final scaffold = tester.widget<Scaffold>(scaffoldFinder);
    expect(scaffold.backgroundColor, customBg);
  });
}
