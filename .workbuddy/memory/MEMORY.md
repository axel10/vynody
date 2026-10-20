# 长期项目笔记

> 只留「会反复咬人的不变量」，过程见同日 `YYYY-MM-DD.md`；旧版全量见 `MEMORY-archive-2026-10-17.md`。

## 单一数据源

| 主题 | 唯一来源 / 规则 | 连带检查 |
|---|---|---|
| Rail 宽度 | `layout_constants.dart` 的 `sidebarRailWidthFor()`，禁 `80.0` | `main_layout.dart` 的 `railWidth`/`leftPadding`；`library_page.dart` |
| FFmpeg 版本 | `audio_core/ffmpeg_version.env`，禁脚本硬编码 | flatpak 清单与 `build-ffmpeg.yml` 的 tag 无硬校验，靠手同步 |
| 远程下载落盘 | `remote_download_service.dart` 的 `buildLocalTrackPath()`：专辑=专辑名一层；艺术家=`collectionFolder`+专辑；歌单=`collectionFolder`+`groupByAlbum:false`；WebDAV/SMB 照抄远端层级 | 新入口必须显式传 `collectionFolder`/`groupByAlbum`，不传即专辑模式。禁再用单曲 `artist` 分层（合辑会被拆散） |
| 曲库数据 | `libraryCatalogProvider` 是唯一订阅 `db.watchAllSongMetadata()` 处 | 新视图用 `catalogDerived(ref, (c) => ...)`，禁自己 `await for`；派生 provider 保持 `StreamProvider` 与原名（测试 override）。`songs` 排除 external/deletedAt，`visibleSongs` 再加根目录/来源 |
| 返回键 | `MainLayout._handleBackPressed()` | Modal → 播放抽屉 → index 2 → index 0 回上级 → index 4 传输中拦 → `SystemNavigator.pop()` |
| 队列整体替换 | `PlaylistController.replaceActiveTracksAndSelect` | 禁拆成 `updatePlaylistTracks`+`playByIndex`：中间 `currentMusic` 瞬时 null，Dock 重播收起动画；启动恢复 `_restorePlaybackSession` 同理禁拆 `addTracksToPlaylist`+`setActivePlaylist`（冷启动 `_currentIndex=null` 时前者会置 0 并 notify → 播放页背景先闪队列第一首） |
| 浮动 Dock 收起 | `floatingDockCollapsed(Progress)Provider` | 开关 `enableFloatingDockScrollCollapse`；`mini_player_wrapper` 与 `main_layout` 各一个 helper。收起态由滚动派生，切主页面/切子分类**禁** `setCollapsed`，只 `helper.reset(ref)`（清累计+进度+`_lastPixels`）。顶部缓冲区展开必须边沿触发，且**边沿只对同一 Scrollable 成立**（用 `notification.context` 判同源；换列表/进子目录后 prev 视为 null，否则旧列表 px 跳变会被误判成「滚回顶部」→ 先展开再收起）；底部无条件展开。诊断日志受 `FloatingDockScrollHelper.traceEnabled` 控制 |
| l10n | 9 个 `lib/l10n/app_*.arb` 同步，模板 `app_zh.arb` | 缺 key 静默回退中文只记 stdout；改完 `flutter gen-l10n` |
| 设置项 | `settings_service.dart` 三段（key/property/访问器） | 6 处：key 常量、`SettingProperty`、getter+setter、`resetXxx()`、`settings_search_registry.dart`、`sections/<组>_section.dart` |
| 流派聚合键 | `normalizeGenreKey()`（`_genreKeyEquivalents` 收敛连写 `JPop`→`j pop`） | 同源派生 `queryKey` 与 `matchGenreAssetKey()`；`_acronymDisplays` 吃 `raw.toLowerCase()` 不能跟着改；`_substringAssetRules` 连写 needle 必须留 |
| 艺术家/流派/年份详情 | `album_sections.dart`（`AlbumSection`/`AlbumSectionsCache`/`AlbumSectionSliver`/`AlbumSongTile`）、`collection_detail_content.dart`、`collection_detail_header.dart`、`detail_page_shell.dart` | 禁再各写一份分组排序/曲目行；三页布局一致：分组宽 ≥600 走「左封面右列表」，否则小封面 + 下方列表 |
| 洞察页视图状态 | `LibraryInsightFilterNotifier`（单曲/专辑 + 时间跨度） | 复位点唯一：`_LibrarySubHostPageState.dispose`（微任务 `reset()`）。切子分类/切主页面都不销毁宿主 → 保留；回仪表盘（`libraryActiveTabIndexProvider` 置 null，宿主出栈）才复位 |
| 子分类导航域 | `library_tab_navigator.dart`（每分类一条 `Navigator` + 自己的 `HeroController`），挂在宿主 `IndexedStack`；9 个 key 由 `LibraryPageState` 持有 | 切分类只改 provider/索引，**禁任何 popUntil**（丢详情 + Hero 飞向不可见分类）；返回键顺序：多选 → 3D → 当前分类栈 → 宿主栈；tab 根内边距必须在路由 builder 里重算，否则旋转后停在旧值 |
| 洞察页列表 | `library_insight_list.dart`（单曲/专辑同一 widget，只换 body sliver）、`library_insight_tab.dart`、`insight_metric_text.dart` | 禁再写 `LibraryRankedSongList`/`AlbumList`；切视图保持根节点 runtimeType 不变（否则滚动/搜索/多选全丢）；行内边距唯一来源 `_insightRowPadding` + `kInsightListHorizontalInset` |

## 硬性禁止

- **宿主顶栏必须给三级页让位**：详情页在子分类 Navigator 里（宿主 body），宿主 `AppTopNavBar` 是 Stack 后画的那个，会盖住详情顶栏 —— 标题变分类名，返回按钮弹掉整个二级宿主。链路：`LibraryTabNavigator.onHasChildRouteChanged` → `_tabsWithChildRoutes` → `hideTopNavBar`（duration 用 `Duration.zero`）。测试取 `library_subhost_top_bar` 外层 `AnimatedOpacity`：`find.ancestor` 最近那个是 `AutoHideHeader` 内部的，要 `.at(1)`。
- **嵌套 `AutoHideHeaderScope` 各管自己的滚动**：`_ownsNotification()` 用「通知来源往上数的最近一个 scope 是不是自己」判定，外层不再收内层的 ScrollNotification（否则详情页下滑 → 返回后根页面顶栏也是塌的，点标题回顶还会滚到详情页）。回归 `test/widgets/auto_hide_header_test.dart` 的 Nested scope 用例。
- **禁持二进制、禁按字节做 key**：①`themeColorsBlob`/`waveformBlob`/`artworkBytes` 不许进 `MusicFolder.files` 与 `representativeSongCache`，树是会话级常驻，播一次就留一份且 GC 收不回 —— 执行点 `scanner_tree_builder` 三个工厂、`ScannerMetadataStore._updateMusicFileInFolder`（copyWith 三项写死 null，`artworkBytes` 只当清空哨兵），数据源永远 SQLite（读侧 DB 优先、生成后写回），播放态自己持一份。②`_prepareCurrentPlaybackArtwork()` 每次播放都写全新 `Uint8List`，`bytes.hashCode` 组成的 key 会让 State 重建、首帧无 `_imageInfo` → 封面全白；`SongThumbnail.gaplessPlayback` 默认 false，靠内部 `_keepLastFrame`（`oldWidget.path == widget.path` 才保留，初值 true）。`_needsPlaybackMetadataRefresh()` 为真时仍会 `structureRevision++` 并写 `thumbnailPath`。
- **IndexedStack 常驻子页禁挂 PopScope**：PopScope 注册在路由上、与可见性无关；`canPop:false` 让整条路由 `doNotPop` 且派发给该路由全部 PopEntry。共用 tab 一律写进 `_handleBackPressed()`；艺术家/流派/年份在页面层套 `library_selection_back_guard.dart`。
- **多选状态禁止条件切换 widget 根节点**：runtimeType 一变子树重建，dispose 微任务清掉刚建的多选状态（一进多选就退出）。唯一状态 `librarySelectionStateProvider`。
- **禁裸 `ref.watch(scannerServiceProvider)`**：`updateSongThumbnailPath` 每张缩略图都 `notifyListeners()`。取实例用 `ref.read`，响应树变化用 `.select((s) => s.structureRevision)`；`rootFolders` 返回缓存视图 `_rootFoldersView`，别现写 `List.unmodifiable`（新实例让 `select` 永不判等）。`ScanProgressInfo` 无 `==`，notifier 的 `build()` 只能 select `isScanning`。
- **MainLayout 是 rebuild 放大器**：`_buildCurrentPage()` 每次 build 新建非 const 的 `FoldersPage`/`LibraryPage`，任何 `setState` 都 rebuild 全部已访问页。别随手加 `ref.watch`。
- **Riverpod 3 禁在 `initState`/`dispose`/`build` 改 provider**：抛 “Tried to modify a provider while the widget tree was building”。销毁即复位 → `initState` 里 `ref.read(x.notifier)` 存字段，`dispose` 里 `Future.microtask(() => notifier.reset())`；`reset()` 先判 `ref.mounted` 与 `isDefault`。
- **Android 转场**：必须 `ZoomPageTransitionsBuilder(allowSnapshotting: false)`，否则返回时下层被快照、ink 高亮残留。
- **逐字歌词时钟禁直接对齐 `audioPositionProvider`**：它是 250ms 一跳的阶梯值，且本地墙钟插值天然领先引擎约 100ms，硬对齐 = 每句/每秒肉眼回跳。`WordWordLyricsWidget` 的 `_syncBaseline` 只取锚点 + `_correction`（240ms 线性摊入，>900ms 才硬对齐），并靠静态 `_resumeLineKeyMs/_resumePositionMs` 让同一行 State 被重建时续接上一刻渲染位置。配套：`audio_core` 的 `_advanceLocalPosition` 对齐引擎位置时，回退 >400ms 才算 seek 直接对齐，小幅回退每轮最多回拉 6ms（`_maxBackstepSlewMs`）。
- **曲库派生页禁把 reload 当首次加载**：播放写 `songs` 表 → catalog 重出快照 → 派生 provider 是「带旧值的 reload」，`AsyncValue.when` 默认 `skipLoadingOnReload: false` 会整页变加载圈。判 loading 只认「没有旧值」。手动组合多上游同理：`if (a.isLoading || b.isLoading) return const AsyncValue.loading()` 会丢旧值，统一用 `library_overview_providers.dart` 的 `_needsFullPageLoad()`/`_isFatalError()`（判 `isLoading && !hasValue`）。
- **长列表禁 `SliverToBoxAdapter > ListView(shrinkWrap: true)`**：shrinkWrap 要测量全部 child，洞察页最多 500 行会在切 tab 那一帧全建，叠加每行 `SongThumbnail.initState` 的同步 `File.existsSync()`，整页掉帧。一律 `SliverList.builder`/`SliverFixedExtentList.builder`，逐行 `Align + ConstrainedBox(maxWidth: kSingleColumnContentMaxWidth)`。
- **播放页背景模糊是预光栅化静态位图，缓存 key 必须含封面内容指纹**：`blurred_artwork_rasterizer.dart` 离屏 `ImageFilter.blur` → 160px `ui.Image`，LRU 6 首，`RawImage` 只贴图。key = `songKey + sigma + 内容指纹`（`fingerprintOf()` 采样 FNV-1a）；**禁只用 `songKey`**（换封面不刷新），**禁 `bytes.hashCode`/identity**（`_prepareCurrentPlaybackArtwork()` 每次播放新建 Uint8List → 每首重光栅化）。小窗 `small_*`、小窗面板 `BackdropFilter`、自定义图片背景仍是实时模糊，不走这套。
- **视图切换禁换根 Widget 类型**：`if (isAlbums) return AlbumList(...) else SongList(...)` 让 Element 无法复用，滚动/搜索/多选全部重建（切 tab 整页闪）。两视图共用同一 StatefulWidget，只换 body sliver。
- **写 `songs` 表只能基于 DB 记录 `copyWith`**：`_songCompanion` 整行写入（全 `Value(...)`，无 `Value.absent()`），`Value(null)` 照写。任何链路 `SongMetadata(...)` 再整行写都会把未列出的列（year/genres/bitrate/sampleRate/format/codec/albumArtist/sourceFlags/fileRating/hasArtwork/waveformBlob/deletedAt/createdAt）清成 null，已因此让歌从年份页/流派页消失过。新记录入库才用最小兜底构造；`id/mediaId/isAppModified/waveformBlob/deletedAt` 属「读文件得不到的列」，永不出现在读标签路径的 copyWith 里。封面四列用 `artworkProbed = generateThumbnail && (!tagReadFailed || 有产出)` 控制，标签解析抛异常不得清空旧封面。
- **`TagLibMetadata` 是标签字段清单，新增标签列必须三处同步**：字段 → 四个 reader（`readMetadataIsolate`/`readMetadataWithImageIsolate`/两个 `_readMetadata*IsolateEntryPoint`）赋值 → `processMetadata` 里 `值 ?? base.值` 回落。`genres`/`hasArtwork` 就是这么漏的。
- **诊断钩子 `_debugWarnColumnWipe`**：写库时「库里某列非空 → 本次写成空」会打 `[ColumnWipe]` + 调用栈（13 列）。看到它 = 有调用方还在拼整行。
- **排序写入必须显式推进结构版本**：文件夹是就地 `sort`，`_computeStructureFingerprint` 只看对象 identity 与歌曲总数，感知不到顺序变化 → 改排序走 `_markSortOrderChanged()`（`_structureRevision++` + `_rootFoldersView = null`），否则列表停在旧顺序、顶栏「仅此目录」高亮不刷新。目录默认排序 = 音轨号升序（`_defaultSortCriteria`，仅 prefs 无该 key 时生效）；`SortCriteriaX.fromStorageValue` 兜底仍是 `filename`（WebDAV 共用同一枚举，不可改）。UI 侧唯一写入口是 `applySortSettings()`（浮层点「确定」才调用，只重排一次），选项本身只改本地状态。

- **`Slider` 是受控组件，`onChanged` 必须回流到 `value`**：Flutter 内部 `_currentDragValue` 只用于计算增量，绘制永远取 `widget.value` → 只把拖动值转给外部 notifier 而不回写，拖动期间拇指就停在按下位置、只随引擎进度抖跳（播放页标准进度条踩过）。要跟手只能本地持有拖动值再看现有三处实现：`_StandardProgressSlider`、`WaveformProgressBar`、`MiniPlayerProgressInfo`。

## 新增实体 / 条目

右键菜单三件套：`lib/widgets/<entity>_context_menu.dart`（`show<Entity>ContextMenu` + `show<Entity>BottomSheet` + 共用 `_handle...`）；条目根挂 `GestureDetector(behavior: opaque, onSecondaryTapDown, onLongPress)`；l10n 加 `view<Entity>Details`/`copy<Entity>Name`。首页卡片不传 `onMultiSelect`。

## 流派 / 年份封面

统一用 `GenreSummary.representativeArtworkPath/ThumbnailPath` + `SongThumbnail`（列表 44 方形、详情 96/116），无封面兜底 `surfaceContainerHighest` + `Icons.music_note_rounded`；流派插画/图标资源与 `genre_naming.dart` 的资源键体系已全删，只剩 `normalizeGenreKey()` 与 `pickGenreDisplayName()`（聚合键只用于分组与相等判断，展示名保留原始排版）。**两套「代表曲」规则不可混用**：集合摘要按 DB 原始顺序取「第一首带封面的歌」，与详情页 `buildAlbumSections`（专辑名排序首组 + 音轨号）必然不同 → 流派/年份列表页与详情页页头都不显示集合级封面，封面只在专辑分组里；集合级 `representativeArtworkPath` 仅剩首页卡片、右键菜单/底部弹窗、拖拽预览在用。

## 环境

- 搜索用 `rg`/`fd`：PATH 里的 grep/find 是 toybox shim，会漏匹配。
- `flutter` 不在 PATH：`export PATH="$HOME/flutter/bin:$PATH"`；`~/.pub-cache` 被沙箱拦写 → `flutter analyze --no-pub`。
- 跑 `flutter test` 前必须 unset `HTTP_PROXY/HTTPS_PROXY/http_proxy/https_proxy/all_proxy` 并 `export NO_PROXY=127.0.0.1,localhost`，否则全部加载失败。
- 无 `groovy`/`pwsh`；验证 Groovy 片段用 Gradle 自带 jar。
