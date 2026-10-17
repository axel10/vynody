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

## 硬性禁止

- **IndexedStack 常驻子页禁挂 PopScope**：PopScope 注册在路由上，与可见性无关。一个 `canPop:false` 让整条路由 `doNotPop`，且 `onPopInvoked` 派发给该路由全部 PopEntry（别的 tab 按返回也触发）。共用 tab 一律写进 `_handleBackPressed()`；只有独占路由的页面才挂（`remote_control_page.dart:249`）。
- **多选状态禁止条件切换 widget 根节点**：runtimeType 一变子树重建，dispose 微任务清掉刚建的多选状态（一进多选就退出）。唯一状态 `librarySelectionStateProvider`，`SelectionStateMixin`/`SongSelectionMixin` 接入。回归 `test/pages/library_multiselect_test.dart`。
- **禁裸 `ref.watch(scannerServiceProvider)`**：`updateSongThumbnailPath` 每张缩略图都 `notifyListeners()`。取实例用 `ref.read`，响应树变化用 `.select((s) => s.structureRevision)`（指纹不含缩略图量；推进点：重写的 `notifyListeners()`、`_handleNavigationChanged()`、`updateMetadataForPath(syncTree:true)`）。`rootFolders` 返回缓存视图 `_rootFoldersView`，别现写 `List.unmodifiable`（新实例让 `select` 永不判等）。`ScanProgressInfo` 无 `==`，其 notifier 的 `build()` 只能 select `isScanning`，不能换 `ref.read`。
- **MainLayout 是 rebuild 放大器**：`_buildCurrentPage()` 每次 build 新建非 const 的 `FoldersPage`/`LibraryPage`，任何 `setState` 都 rebuild 全部已访问页（含不可见）。别随手加 `ref.watch`。
- **Android 转场**：必须 `ZoomPageTransitionsBuilder(allowSnapshotting: false)`，否则返回时下层被快照，ink 高亮残留。

## 新增实体 / 条目

- 右键菜单三件套：`lib/widgets/<entity>_context_menu.dart`（`show<Entity>ContextMenu` + `show<Entity>BottomSheet` + 共用 `_handle...`）；条目根挂 `GestureDetector(behavior: opaque, onSecondaryTapDown, onLongPress)`；l10n 加 `view<Entity>Details`/`copy<Entity>Name`。首页卡片不传 `onMultiSelect`。回归 `test/widgets/views_layout_smoke_test.dart`。

## 流派封面（2026-10-17 起全用专辑封面）

首页流派行、流派列表页、详情页统一用 `GenreSummary.representativeArtworkPath/ThumbnailPath` + `SongThumbnail`（列表 44 方形、详情 96/116）。无封面时兜底图标：列表页用 `iconAssetPath` 的 SVG（`colorFilter: srcIn` 着色 primary），详情页渐变 + 图标。

`assets/images/genre/webp` 插画**已无任何 UI 引用**：只留在 `genre_naming.dart` 的资源键体系里给图标键映射（`_iconKeyByImageKey`）和目录/清单双向比对测试用。`GenreSummary.imageAssetPath` 仅为兼容保留，新界面不要渲染。

- 封面键用连字符（`hip-hop.webp`），图标键用下划线（`hip_hop.svg`）；`kGenreAssetKeys` 与 webp 文件名逐字一致。
- 图标 24 个 SVG，全部 `srcIn` 着色（保持白色填充）。新增统一 `viewBox="0 0 100 100"`、内容留 10 单位边距、线宽≈7。改完用 `encodeSvg()`（vector_graphics_compiler）编译验证；flutter_test 里要关 `enableMasking/Clipping/OverdrawOptimizer`，否则 `PathOps library was not initialized`。

## 播放页音频规格

`PlaybackAudioInfoLabel`（`playback_progress_section.dart:304`），数据源唯一 `currentAudioDetailsProvider`。坑：①provider 重建先跑 `onDispose` 会取消精解析定时器（已修）；②`setCachedAudioDetails` 无条件写，`sampleRate==0` 的缓存让整行空白；③远程曲目 path 无扩展名，未读 trackJson 的 `samplingRate`/`bitRate`。

## 环境

- 搜索用 `rg`/`fd`：PATH 里的 grep/find 是 toybox shim，会漏匹配。
- `flutter` 不在 PATH：`export PATH="$HOME/flutter/bin:$PATH"`。
- `~/.pub-cache` 被沙箱拦写：`flutter analyze --no-pub`。
- 跑 `flutter test` 前必须 unset `HTTP_PROXY/HTTPS_PROXY/http_proxy/https_proxy/all_proxy` 并 `export NO_PROXY=127.0.0.1,localhost`，否则全部加载失败。
- 无 `groovy`/`pwsh`；验证 Groovy 片段用 Gradle 自带 jar。
