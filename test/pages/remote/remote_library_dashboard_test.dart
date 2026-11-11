import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/remote_library_dashboard_view.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/carousel_scroll_wrapper.dart';

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
    RefreshCallback? onRefresh,
    VoidCallback? onPlayAll,
    VoidCallback? onShufflePlay,
    VoidCallback? onDisconnect,
    int playlistCount = 0,
    int? genreCount,
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
        genreCount: genreCount,
        recentAlbums: recentAlbums,
        releasedAlbums: releasedAlbums,
        recentPlayedAlbums: recentPlayedAlbums,
        mostPlayedAlbums: mostPlayedAlbums,
        playlists: playlists,
        favoriteAlbums: favoriteAlbums,
        onNavigateToTab: onNavigateToTab ?? (_) {},
        onOpenAlbum: (_, _) {},
        onOpenPlaylist: (_) {},
        onRefresh: onRefresh ?? () async {},
        onPlayAll: onPlayAll,
        onShufflePlay: onShufflePlay,
        onDisconnect: onDisconnect ?? () {},
      ),
    );
  }

  testWidgets('顶部展示服务器名与类型，删去统计行', (tester) async {
    await tester.pumpWidget(wrap());

    expect(find.text('My Navidrome'), findsOneWidget);
    expect(find.text('Navidrome / Subsonic'), findsOneWidget);
    // 确认顶部不再展示「专辑 12 · 艺术家 3 · 歌曲 48」的统计行
    expect(find.textContaining('· 艺术家'), findsNothing);
  });

  testWidgets('宽屏下右上角平铺展示播放全部、随机播放、刷新、断开连接', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var playAllCalled = false;
    var shufflePlayCalled = false;
    var refreshCalled = false;
    var disconnectCalled = false;

    await tester.pumpWidget(wrap(
      onPlayAll: () => playAllCalled = true,
      onShufflePlay: () => shufflePlayCalled = true,
      onRefresh: () async => refreshCalled = true,
      onDisconnect: () => disconnectCalled = true,
    ));

    // 随机播放按钮样式使用 Icons.shuffle_rounded，而非原先的 Icons.casino_outlined
    expect(find.byIcon(Icons.casino_outlined), findsNothing);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.link_off_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(playAllCalled, isTrue);

    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    expect(shufflePlayCalled, isTrue);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    expect(refreshCalled, isTrue);

    await tester.tap(find.byIcon(Icons.link_off_rounded));
    expect(disconnectCalled, isTrue);
  });

  testWidgets('竖屏窄屏宽度不足时刷新按钮隐藏，断开连接直接展示且无更多按钮', (tester) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var disconnectCalled = false;

    await tester.pumpWidget(wrap(
      onPlayAll: () {},
      onShufflePlay: () {},
      onDisconnect: () => disconnectCalled = true,
    ));

    // 播放全部与随机播放依然常驻
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);

    // 宽度不足时刷新按钮隐藏，断开连接直接展示，不使用更多按钮
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(find.byIcon(Icons.link_off_rounded), findsOneWidget);

    // 点击断开连接直接触发
    await tester.tap(find.byIcon(Icons.link_off_rounded));
    expect(disconnectCalled, isTrue);
  });

  testWidgets('概览页支持下拉刷新触发 onRefresh', (tester) async {
    var refreshCalled = false;
    await tester.pumpWidget(wrap(
      onRefresh: () async {
        refreshCalled = true;
      },
    ));

    expect(find.byType(RefreshIndicator), findsOneWidget);
    await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(refreshCalled, isTrue);
  });

  testWidgets('六个快捷入口都在，点击回传对应分类索引', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
          onRefresh: () async {},
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

  testWidgets('横屏与竖屏下封面尺寸与 CarouselScrollWrapper 正确配置，contentLeftPadding 正确传递', (tester) async {
    // 宽屏横屏测试
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const double testLeftPadding = 72.0;

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
          playlistCount: 0,
          contentLeftPadding: testLeftPadding,
          recentAlbums: const [
            {'id': 'a1', 'name': '测试专辑', 'artist': '测试艺人'}
          ],
          onNavigateToTab: (_) {},
          onOpenAlbum: (_, _) {},
          onRefresh: () async {},
          onShuffleAll: () {},
          onDisconnect: () {},
        ),
      ),
    );

    // 检查 CarouselScrollWrapper 存在且 leftButtonOffset 匹配 contentLeftPadding
    // （宽屏下包含顶部快捷入口流与专辑板块共 2 个 CarouselScrollWrapper）
    final carouselFinders = find.byType(CarouselScrollWrapper);
    expect(carouselFinders, findsNWidgets(2));
    for (final carousel in tester.widgetList<CarouselScrollWrapper>(carouselFinders)) {
      expect(carousel.leftButtonOffset, testLeftPadding);
    }
    final albumCarousel = tester.widgetList<CarouselScrollWrapper>(carouselFinders).firstWhere(
      (w) => w.centerHeight == (126.0 * 1.9).roundToDouble(),
    );
    expect(albumCarousel.centerHeight, (126.0 * 1.9).roundToDouble()); // 239.0

    // 检查横向 ListView 的 content padding 左侧包含 testLeftPadding + horizontalPadding (32.0)
    final listViewFinder = find.byType(ListView);
    expect(listViewFinder, findsOneWidget);
    final listView = tester.widget<ListView>(listViewFinder);
    final padding = listView.padding as EdgeInsets;
    expect(padding.left, testLeftPadding + 32.0);
  });

  testWidgets('竖屏与横屏下二级页面入口均在条目右侧以徽章展示统计数字且样式与本地媒体库对齐', (tester) async {
    // 1. 竖屏测试 (宽 400 < 780)
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(playlistCount: 99, genreCount: 5));

    // 竖屏下采用列表菜单项，包含右箭头
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(6));

    // 二级页面入口条目右侧展示对应统计数字徽章
    expect(find.text('12'), findsOneWidget); // 专辑数
    expect(find.text('3'), findsOneWidget);  // 艺术家数
    expect(find.text('5'), findsOneWidget);  // 流派数
    expect(find.text('48'), findsOneWidget); // 歌曲数
    expect(find.text('99'), findsOneWidget); // 歌单数

    // 2. 宽屏测试 (宽 1000 >= 780)
    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpWidget(wrap(playlistCount: 99, genreCount: 5));

    // 宽屏下横向快速入口采用 CarouselScrollWrapper
    expect(find.byType(CarouselScrollWrapper), findsOneWidget);
    // 宽屏下卡片右侧同样展示对应统计数字徽章
    expect(find.text('12'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('99'), findsOneWidget);
  });
}
