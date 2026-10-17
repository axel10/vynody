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
| 洞察页视图状态 | `LibraryInsightFilterNotifier`（单曲/专辑 + 时间跨度），生命周期对齐二级宿主页 | 复位点唯一：`_LibrarySubHostPageState.dispose`（微任务里调 `reset()`）；离开媒体库主页面由 `LibraryPageState.dismissSubPages()` 退栈触发（监听 `mainTabIndexProvider`）。禁在仪表盘/各入口各写一份 reset |

## 硬性禁止

- **IndexedStack 常驻子页禁挂 PopScope**：PopScope 注册在路由上，与可见性无关。一个 `canPop:false` 让整条路由 `doNotPop`，且 `onPopInvoked` 派发给该路由全部 PopEntry（别的 tab 按返回也触发）。共用 tab 一律写进 `_handleBackPressed()`；只有独占路由的页面才挂（`remote_control_page.dart:249`）。艺术家/流派/年份三页已改为：内容层不挂，页面层套 `widgets/library_selection_back_guard.dart`。
- **多选状态禁止条件切换 widget 根节点**：runtimeType 一变子树重建，dispose 微任务清掉刚建的多选状态（一进多选就退出）。唯一状态 `librarySelectionStateProvider`，`SelectionStateMixin`/`SongSelectionMixin` 接入。回归 `test/pages/library_multiselect_test.dart`。
- **禁裸 `ref.watch(scannerServiceProvider)`**：`updateSongThumbnailPath` 每张缩略图都 `notifyListeners()`。取实例用 `ref.read`，响应树变化用 `.select((s) => s.structureRevision)`（指纹不含缩略图量；推进点：重写的 `notifyListeners()`、`_handleNavigationChanged()`、`updateMetadataForPath(syncTree:true)`）。`rootFolders` 返回缓存视图 `_rootFoldersView`，别现写 `List.unmodifiable`（新实例让 `select` 永不判等）。`ScanProgressInfo` 无 `==`，其 notifier 的 `build()` 只能 select `isScanning`，不能换 `ref.read`。
- **MainLayout 是 rebuild 放大器**：`_buildCurrentPage()` 每次 build 新建非 const 的 `FoldersPage`/`LibraryPage`，任何 `setState` 都 rebuild 全部已访问页（含不可见）。别随手加 `ref.watch`。
- **Riverpod 3 禁在 `initState`/`dispose`/`build` 里改 provider 状态**：抛 “Tried to modify a provider while the widget tree was building”。需要「页面销毁即复位」时，在 `initState` 里先 `ref.read(x.notifier)` 存字段，再在 `dispose` 里 `Future.microtask(() => notifier.reset())`（`LibrarySubHostPageState` 是范本）。Notifier 内 `reset()` 先判 `ref.mounted` 与 `isDefault`，避免容器已销毁时抛 unmounted ref。
- **Android 转场**：必须 `ZoomPageTransitionsBuilder(allowSnapshotting: false)`，否则返回时下层被快照，ink 高亮残留。
- **写 `songs` 表只能基于 DB 记录 `copyWith`**：`insertOrUpdateSong` → `_songCompanion` 是整行写入，`Value(null)` 照写。任何链路里 `new SongMetadata(...)` 再整行写，都会把未列出的列（`year`、`genres`、`bitrate/sampleRate/format/codec`、`albumArtist`、`sourceFlags`、`fileRating`、`hasArtwork`）清成 null。曾因此让「播放一次后歌曲从年份页消失」（`saveCurrentSongThemeColors`，已修）。

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
