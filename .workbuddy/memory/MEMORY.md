# 长期项目笔记

> 注入上限约 8KB。只留「会反复咬人的不变量」，过程与复盘见同日 `YYYY-MM-DD.md`。
> 2026-10-17 完整旧版：`MEMORY-archive-2026-10-17.md`。

## 单一数据源

| 主题 | 唯一来源 | 连带检查 |
|---|---|---|
| Rail 宽度 | `lib/utils/layout_constants.dart` 的 `sidebarRailWidthFor()`，禁 `80.0` | `main_layout.dart` 的 `railWidth`/`leftPadding`；`library_page.dart` |
| FFmpeg 版本/URL | `audio_core/ffmpeg_version.env`，禁脚本硬编码 | 离线包 `packaging/flatpak/*.yml`、`build-ffmpeg.yml` 的 release tag（无硬校验，靠手同步） |
| 曲库数据 | `libraryCatalogProvider` 是唯一订阅 `db.watchAllSongMetadata()` 处 | 新视图用 `catalogDerived(ref, (c) => ...)`，禁自己 `await for`；派生 provider 保持 `StreamProvider` 与原名（测试 override）。`songs`（排除 external/deletedAt）vs `visibleSongs`（再加根目录/来源） |
| 返回键 | `MainLayout._handleBackPressed()` | 顺序：Modal → 播放抽屉 → index 2 → index 0 回上级 → index 4 传输中拦 → `SystemNavigator.pop()` |
| 队列整体替换 | `PlaylistController.replaceActiveTracksAndSelect` | 禁拆成 `updatePlaylistTracks` + `playByIndex`：中间 `currentMusic` 瞬时为 null，Dock 重播收起动画 |
| 浮动 Dock 收起 | `floatingDockCollapsed(Progress)Provider` | 开关 `enableFloatingDockScrollCollapse`；`mini_player_wrapper` 与 `main_layout` 各一个 `FloatingDockScrollHelper` |
| l10n | 9 个 `lib/l10n/app_*.arb` 同步，模板 `app_zh.arb` | 缺 key 静默回退中文且只记 stdout；改完 `flutter gen-l10n` |
| 设置项 | `settings_service.dart` 三段（key/property/访问器） | 6 处：key 常量、`SettingProperty`、getter+setter、`resetXxx()`、`settings_search_registry.dart`、`sections/<组>_section.dart` |
| 流派聚合键 | `normalizeGenreKey()`（`_genreKeyEquivalents` 收敛连写：`JPop`→`j pop`） | 同源派生 `queryKey` 与 `matchGenreAssetKey()`；`_acronymDisplays` 吃 `raw.toLowerCase()` 不能跟着改；`_substringAssetRules` 连写 needle 必须留 |
| 艺术家/流派/年份详情页 | `widgets/album_sections.dart`（`AlbumSection` + `AlbumSectionsCache` + `AlbumSectionSliver` + `AlbumSongTile`）、`collection_detail_content.dart`（流派/年份共用内容）、`collection_detail_header.dart`、`detail_page_shell.dart` | 禁再各写一份 `_AlbumSection` / 分组排序 / 曲目行；三页布局规则必须一致：分组宽度 ≥600 走「左封面右列表」，否则小封面 + 下方列表 |
| 洞察页视图状态 | `LibraryInsightFilterNotifier`（单曲/专辑 + 时间跨度），生命周期对齐二级宿主页 | 复位点唯一：`_LibrarySubHostPageState.dispose`（微任务里调 `reset()`）。2026-10-18 起「切子分类 / 切主页面」都不销毁宿主 → 状态保留；只有回到仪表盘（`libraryActiveTabIndexProvider` 置 null，宿主出栈）才 dispose 并复位。禁在仪表盘/各入口各写一份 reset |
| 子分类导航域 | `widgets/library_tab_navigator.dart`（每个子分类一条 `Navigator` + 自己的 `HeroController`），挂在 `_LibrarySubHostPageState` 的 `IndexedStack` 里；9 个 `GlobalKey<NavigatorState>` 由 `LibraryPageState` 持有 | 切子分类 = 只改 provider / IndexedStack 索引，**禁任何 popUntil**（会丢详情并让封面 Hero 飞向不可见分类）；返回键顺序：多选 → 3D → 当前分类栈 → 宿主栈（`LibraryPageState.handleBackPressed`）；tab 根页面内边距必须在路由 builder 里重算（`_buildSubTabRoot` 的 `Builder`），不能捕获宿主 build 时的值，否则旋转后不更新 |
| 洞察页列表 | `widgets/library_insight_list.dart`（单曲/专辑同一个 widget，按 `SectionItemType` 换 body sliver）、`pages/library_insight_tab.dart`（最近播放/最多播放/最近添加共用）、`widgets/insight_metric_text.dart`（`InsightMetricText` + `formatInsightDate`） | 禁再写 `LibraryRankedSongList` / `LibraryRankedAlbumList`（2026-10-18 已合并删除）；切单曲/专辑必须保持根节点 runtimeType 不变，否则滚动位置、搜索词、多选状态随 State 一起销毁（表现为整页闪一下）；`rated_songs_tab` 也走同一列表。回归 `test/pages/recently_view_tabs_test.dart`（含「切视图搜索词保留」用例）；行内水平边距唯一来源 `_insightRowPadding(context)` + `kInsightListHorizontalInset`，单曲/专辑两条 sliver 必须共用（禁各自写死 10/16，会让切视图时卡片宽度与封面左边缘跳动） |

## 硬性禁止

- **封面组件禁按「字节对象」加 key**：`AudioService._prepareCurrentPlaybackArtwork()` 每次播放都会写一个全新 `Uint8List`（`readAsBytes()`），任何以 `bytes.hashCode` 组成的 key 都会让 State 整体重建，新 State 首帧无旧 `_imageInfo` → 封面临时全白。`MiniArtwork` 已删该 key（`SongThumbnail.didUpdateWidget` 自己处理 path/artwork 变化）并传 `gaplessPlayback: true`（文件源 ↔ 内存源切换时保留上一帧）。`SongThumbnail.gaplessPlayback` 默认 false：列表行回收复用会换成另一首歌，开了会短暂显示上一首封面；改为内部 `_keepLastFrame` 判定（`oldWidget.path == widget.path` 才保留上一帧，初值 true），所以**歌曲行首次播放时树里被塞进 `artworkBytes` 也不会闪白**。回归 `test/widgets/mini_artwork_test.dart`、`test/widgets/song_thumbnail_gapless_test.dart`。
- **首次播放会改树里的 MusicFile**：`_needsPlaybackMetadataRefresh()` 为真（无标签/无时长）时 `updateMetadataForPath(..., artworkBytes:)` 会 `structureRevision++` 并把 `artworkBytes`/`thumbnailPath`/`artworkWidth` 写回 `folder.files`；无标签歌曲「播一次后列表/详情封面换成另一套解码路径」即源于此。
- **IndexedStack 常驻子页禁挂 PopScope**：PopScope 注册在路由上，与可见性无关。一个 `canPop:false` 让整条路由 `doNotPop`，且 `onPopInvoked` 派发给该路由全部 PopEntry（别的 tab 按返回也触发）。共用 tab 一律写进 `_handleBackPressed()`；只有独占路由的页面才挂（`remote_control_page.dart:249`）。艺术家/流派/年份三页已改为：内容层不挂，页面层套 `widgets/library_selection_back_guard.dart`。
- **多选状态禁止条件切换 widget 根节点**：runtimeType 一变子树重建，dispose 微任务清掉刚建的多选状态（一进多选就退出）。唯一状态 `librarySelectionStateProvider`，`SelectionStateMixin`/`SongSelectionMixin` 接入。回归 `test/pages/library_multiselect_test.dart`。
- **禁裸 `ref.watch(scannerServiceProvider)`**：`updateSongThumbnailPath` 每张缩略图都 `notifyListeners()`。取实例用 `ref.read`，响应树变化用 `.select((s) => s.structureRevision)`（指纹不含缩略图量；推进点：重写的 `notifyListeners()`、`_handleNavigationChanged()`、`updateMetadataForPath(syncTree:true)`）。`rootFolders` 返回缓存视图 `_rootFoldersView`，别现写 `List.unmodifiable`（新实例让 `select` 永不判等）。`ScanProgressInfo` 无 `==`，其 notifier 的 `build()` 只能 select `isScanning`，不能换 `ref.read`。
- **MainLayout 是 rebuild 放大器**：`_buildCurrentPage()` 每次 build 新建非 const 的 `FoldersPage`/`LibraryPage`，任何 `setState` 都 rebuild 全部已访问页（含不可见）。别随手加 `ref.watch`。
- **Riverpod 3 禁在 `initState`/`dispose`/`build` 里改 provider 状态**：抛 “Tried to modify a provider while the widget tree was building”。需要「页面销毁即复位」时，在 `initState` 里先 `ref.read(x.notifier)` 存字段，再在 `dispose` 里 `Future.microtask(() => notifier.reset())`（`LibrarySubHostPageState` 是范本）。Notifier 内 `reset()` 先判 `ref.mounted` 与 `isDefault`，避免容器已销毁时抛 unmounted ref。
- **Android 转场**：必须 `ZoomPageTransitionsBuilder(allowSnapshotting: false)`，否则返回时下层被快照，ink 高亮残留。
- **曲库派生页禁把 reload 当首次加载**：播放写 `songs` 表 → catalog 重出快照 → 派生 provider 是「有旧值的 reload」。`AsyncValue.when` 默认 `skipLoadingOnReload: false`，会把整页换成加载圈（播放后一直闪的元凶）。判 loading 只认「没有旧值」，用 `skipLoadingOnReload: true` 或 `value ?? 上次缓存`。**手动组合多个上游的 provider 同样适用**：`if (a.isLoading || b.isLoading) return const AsyncValue.loading()` 会把旧值丢掉（返回的是全新 loading 而非带旧值的 reload，`skipLoadingOnReload` 拦不住）。统一用 `library_overview_providers.dart` 的 `_needsFullPageLoad()` / `_isFatalError()`（判 `isLoading && !hasValue`）。2026-10-18 已修 `mostPlayedAlbumsProvider` / `recentlyAddedAlbumsProvider` / `topRatedAlbumsProvider` / `_combineInsightAlbums`，回归 `test/player/library_insight_album_reload_test.dart`。
- **长列表禁 `SliverToBoxAdapter > ListView(shrinkWrap: true)`**：shrinkWrap 必须测量全部 child，洞察页最多 500 行（`watchRecently*` 默认 `limit=500`）会在切 tab 那一帧全建，叠加每行 `SongThumbnail.initState` 的 `File.existsSync()` 同步 IO 与 `toAlbumSummary()`，整页掉帧。一律用 `SliverList.builder` / `SliverFixedExtentList.builder` 懒构建，逐行 `Align + ConstrainedBox(maxWidth: kSingleColumnContentMaxWidth)` 保持居中约束。2026-10-18 已修 `library_ranked_album_list.dart`（现合并进 `library_insight_list.dart`）。
- **视图切换禁换根 Widget 类型**：`if (isAlbums) return AlbumList(...) else return SongList(...)` 会让 Element 无法复用，`ScrollController`、搜索词、多选状态全部销毁重建（切 tab 时整页闪一下的直接原因）。两种视图共用同一个 StatefulWidget，只切换 body 的 sliver（`library_insight_list.dart` 是范本）。
- **写 `songs` 表只能基于 DB 记录 `copyWith`**：`insertOrUpdateSong` → `_songCompanion` 是整行写入（全 `Value(...)`，无 `Value.absent()`），`Value(null)` 照写。任何链路里 `new SongMetadata(...)` 再整行写，都会把未列出的列（`year`、`genres`、`bitrate/sampleRate/format/codec`、`albumArtist`、`sourceFlags`、`fileRating`、`hasArtwork`、`waveformBlob`、`deletedAt`、`createdAt`）清成 null。曾因此让「播放一次后歌曲从年份页消失」（`saveCurrentSongThemeColors`）、「同专辑其它歌从流派页消失」（`MetadataHelper.processMetadata`），均已修。
- **改 `SongMetadata` 一律 `existing.copyWith(...)` 当基底，禁止 `SongMetadata(...)` 重新拼整行**：`MetadataHelper.processMetadata` / `processRemoteCachedMetadata` 已按此重构（2026-10-17）。没写的列自动保持旧值，将来新增字段忘处理最坏只是「沿用旧值」。唯一例外是新记录入库（`existing == null`），此时用最小兜底构造（path/title/album/artist）。`id / mediaId / isAppModified / waveformBlob / deletedAt` 属于「读文件得不到的列」，永远不要出现在读标签路径的 copyWith 里。封面四列用 `artworkProbed = generateThumbnail && (!tagReadFailed || 有产出)` 控制，标签解析抛异常时不得清空旧封面。
- **`TagLibMetadata` 是「标签字段清单」，新增标签列必须三处同步**：`TagLibMetadata` 字段 → 四个 reader（`readMetadataIsolate` / `readMetadataWithImageIsolate` / 两个 `_readMetadata*IsolateEntryPoint`）赋值 → `processMetadata` 里 `值 ?? base.值` 回落。`genres` / `hasArtwork` 就是这么漏的。
- **诊断钩子 `_debugWarnColumnWipe`**：`insertOrUpdateSong` / `insertOrUpdateSongsMerged` 在「库里某列非空 → 本次写成空」时打 `[ColumnWipe]` + 调用栈（genres/year/albumArtist/duration/trackNumber/bitrate/sampleRate/channels/bitDepth/format/codec/fileRating/createdAt 十三列）。看到它 = 有调用方还在用 `SongMetadata(...)` 拼整行。artworkPath/thumbnailPath/waveformBlob/hasArtwork 不检查（有合法清空场景）。

## 新增实体 / 条目

- 右键菜单三件套：`lib/widgets/<entity>_context_menu.dart`（`show<Entity>ContextMenu` + `show<Entity>BottomSheet` + 共用 `_handle...`）；条目根挂 `GestureDetector(behavior: opaque, onSecondaryTapDown, onLongPress)`；l10n 加 `view<Entity>Details`/`copy<Entity>Name`。首页卡片不传 `onMultiSelect`。回归 `test/widgets/views_layout_smoke_test.dart`。

## 流派封面（2026-10-17 起全用专辑封面，插画/图标资源已删）

首页流派行、流派列表页、详情页统一用 `GenreSummary.representativeArtworkPath/ThumbnailPath` + `SongThumbnail`（列表 44 方形、详情 96/116）。无封面兜底：列表页 `surfaceContainerHighest` + `Icons.music_note_rounded`，详情页渐变 + 图标。

`assets/images/genre/`、`assets/icons/genre/`、pubspec 声明、`genre_naming.dart` 的资源键体系（`matchGenreAssetKey` / `genreImageAssetKey` / `genreIconAssetKey` / `kGenreAssetKeys` / `_iconKeyByImageKey` / 别名表 / 子串规则）与 `GenreSummary.imageAssetPath|iconAssetPath|usesFallbackCover` 已全部删除。`genre_naming.dart` 只剩 `normalizeGenreKey()` 与 `pickGenreDisplayName()`：聚合键只用于分组与相等判断，展示名保留原始排版，两者不可混用。新增流派 UI 一律取代表曲专辑封面，不要再引入任何流派素材。

**两套「代表曲」规则不可混用**：集合摘要（`library_catalog.dart` 的 `_buildGenreSummaries`/`_buildYearSummaries`）按数据库原始顺序取「第一首带封面路径的歌」，与详情页 `buildAlbumSections` 的「专辑名排序首组 + 音轨号」结果必然不一致。因此**流派/年份列表页与详情页页头都不显示集合级封面**（2026-10-17 起；`_GenreListItem`/`_YearListItem` 只剩标题 + 歌曲数·专辑数，`CollectionCover` 类已删），封面只在专辑分组里出现。集合级 `representativeArtworkPath` 仅剩首页卡片（`library_dashboard_view.dart`）、右键菜单/底部弹窗（`genre_context_menu.dart`/`year_context_menu.dart`）、拖拽预览（`draggable_*_item.dart`）在使用。要真正统一集合封面，只能抽公共 helper 让 catalog 复用分组排序规则。

## 播放页音频规格

`PlaybackAudioInfoLabel`（`playback_progress_section.dart:304`），数据源唯一 `currentAudioDetailsProvider`。坑：①provider 重建先跑 `onDispose` 会取消精解析定时器（已修）；②`setCachedAudioDetails` 无条件写，`sampleRate==0` 的缓存让整行空白；③远程曲目 path 无扩展名，未读 trackJson 的 `samplingRate`/`bitRate`。

## 环境

- 搜索用 `rg`/`fd`：PATH 里的 grep/find 是 toybox shim，会漏匹配。
- `flutter` 不在 PATH：`export PATH="$HOME/flutter/bin:$PATH"`。
- `~/.pub-cache` 被沙箱拦写：`flutter analyze --no-pub`。
- 跑 `flutter test` 前必须 unset `HTTP_PROXY/HTTPS_PROXY/http_proxy/https_proxy/all_proxy` 并 `export NO_PROXY=127.0.0.1,localhost`，否则全部加载失败。
- 无 `groovy`/`pwsh`；验证 Groovy 片段用 Gradle 自带 jar。
