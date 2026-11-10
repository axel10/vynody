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
        favoriteAlbums: favoriteAlbums,
        onNavigateToTab: onNavigateToTab ?? (_) {},
        onOpenAlbum: (_, _) {},
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

  testWidgets('没有最近添加 / 收藏数据时不出现对应板块', (tester) async {
    await tester.pumpWidget(wrap());
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(find.text(l10n.recentlyAdded), findsNothing);
    expect(find.text(l10n.starredAlbums), findsNothing);
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
