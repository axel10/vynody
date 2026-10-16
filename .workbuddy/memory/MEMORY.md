# 长期项目笔记

> 本文件自动注入，有约 8K 字符上限（超出会被截断），只沉淀「会反复咬人的不变量」。
> 排查过程、历史 bug 复盘见同日 `YYYY-MM-DD.md`。

## 单一数据源 / 唯一入口 —— 改这些功能前先看这张表

| 主题 | 唯一来源 | 连带必须一起检查 |
|---|---|---|
| Rail 宽度 | `lib/utils/layout_constants.dart`（`kSidebarRailWidthCollapsed=80` / `Extended=216` / `sidebarRailWidthFor()`），禁止硬编码 `80.0` | `main_layout.dart` 的 `railWidth`、`SizedBox(width:)`、`_buildCurrentPage` 的 `leftPadding`；`library_page.dart` 的 `railWidth` 入参 |
| FFmpeg 产物版本/URL | `audio_core/ffmpeg_version.env`（`FFMPEG_VERSION`+`FFMPEG_BASE_URL`，可用 `FFMPEG_URL_<平台>` 整条覆盖），禁止在脚本/构建文件硬编码 | apple/linux shell 直接 `source`；windows ps1 手写 KV 解析；`android/build.gradle` Groovy 解析 + `inputs.file(env)`。**离线场景要手工同步**：`packaging/flatpak/*.yml`（URL+sha256）、`.github/workflows/build-ffmpeg.yml`（release tag 须等于 `FFMPEG_VERSION`，无硬校验） |
| 曲库数据 | `lib/player/library/library_catalog.dart` 的 `libraryCatalogProvider` 是**全应用唯一**允许订阅 `db.watchAllSongMetadata()` 的地方 | 新曲库视图一律 `catalogDerived(ref, (c) => ...)` 从快照派生，禁止自己 `await for` 那个流。派生 provider 保持 `StreamProvider` 类型与名字（测试用 `overrideWith`）。`LibraryCatalog` 聚合字段全是 `late final`，**必须保持惰性**。过滤两层：`catalog.songs`（仅排除 external/deletedAt）vs `catalog.visibleSongs`（再加活动根目录+来源过滤），历史上 `allRatedSongsProvider`/`timeMachineAlbumsProvider` 用前者，其余用后者，未统一 |
| 返回键 | `MainLayout` 的 `PopScope(canPop:false)` → `_handleBackPressed()`（`main_layout.dart` 约 `:1315`），全应用唯一裁决点 | 顺序：最上层 Modal → 播放抽屉 → index 2（媒体库）→ index 0（目录回上级）→ index 4（共享页有传输则 toast 拦住）→ `SystemNavigator.pop()`；非 Android 直接 return |
| 艺术家聚合 | `ArtistLibraryRepository.buildSummariesFor()` | `watchArtistSummaries()` 只是流式包装，仍被 `audio_service.dart` 的「下一首/上一首艺术家」使用（每次全表扫，低频未优化） |

`library_catalog.dart` ↔ `album_library.dart` / `artist_library.dart` 是**循环 import**（Dart 允许，顶层 provider 惰性构造，无初始化顺序风险），别被绕晕。

## 禁止在 IndexedStack 常驻子页挂 PopScope

PopScope 注册在**路由**上，与 widget 可见性无关（`IndexedStack` 用 `Visibility(maintainState/maintainAnimation: true)` 包 child，连 TickerMode 都没套，判可见性只能靠 `mainTabIndexProvider`）。后果两条：

1. `ModalRoute.popDisposition` 是聚合判断 —— 一个 PopEntry 说 `canPop == false`，整条路由就 `doNotPop`；
2. `onPopInvokedWithResult` 会把回调派发给该路由上**全部** PopEntry（`routes.dart:2045`），别的 tab 按返回也触发。

历史 bug：共享页传输中切走再按返回会弹「正在传输文件，请勿离开共享页」，且拦不住末尾的 `SystemNavigator.pop()`。已改为删掉 `sharing_page.dart` 的 PopScope，在 `_handleBackPressed()` 里加 index 4 分支。

**只适用于独占一条路由的页面**的写法：PopScope 常驻，只切 `canPop: !isSelectionMode`（见 `remote_control_page.dart:249`、`remote_folder_browser_page.dart:1844`）。

## 媒体库多选（LibrarySelection）

- 单一数据源 `lib/widgets/library_selection_scope.dart` 的 `librarySelectionStateProvider`（全局一份，靠 `scope` 区分 library/artist/album/playlist/queue/folder/genre/year…）。页面经 `SelectionStateMixin` / `SongSelectionMixin` 接入，二者 `dispose` 用 `Future.microtask(clearIfScope(scope))` 收尾。
- **禁止**按多选状态在「包一层 PopScope」与「返回原 widget」间条件切换：根节点 runtimeType 一变，子树销毁重建，持有选中项的 widget 的 dispose 微任务会清掉刚建立的多选状态（表现为一进多选就退出），搜索词/排序/滚动位置全丢。
- 回归测试 `test/pages/library_multiselect_test.dart`（真实页面级），上述错误写法下会有 4 条失败。

## 媒体库条目右键菜单（全站统一三件套）

新增一类实体照抄（已有 album/artist/genre/year）：

1. `lib/widgets/<entity>_context_menu.dart`：`show<Entity>ContextMenu`（`AppContextMenu.show` + `buildContextMenuItem`，后者在 `lib/utils/song_context_menu_utils.dart`）+ `show<Entity>BottomSheet` + 共用 `_handle<Entity>MenuAction`。
2. 卡片/列表项根节点挂 `GestureDetector(behavior: HitTestBehavior.opaque, onSecondaryTapDown, onLongPress)`：右键 → ContextMenu，长按 → BottomSheet。已用 `InkWell` 的（艺术家条目）直接用其回调。
3. l10n 需要 `view<Entity>Details` / `copy<Entity>Name`，改完 9 个 arb 必须跑 `flutter gen-l10n`。

覆盖：媒体库二级页（专辑/艺术家/流派/年份 tab）+ `library_dashboard_view.dart` 首页五类卡片。仪表盘卡片**不传** `onMultiSelect`（首页没有多选 UI）。回归测试 `test/widgets/views_layout_smoke_test.dart` 的「五类条目均支持右键菜单」（`tester.tap(..., buttons: kSecondaryMouseButton)`，需 `import 'package:flutter/gestures.dart'`）。

## MainLayout 是全应用 rebuild 的放大器

`main_layout.dart` 的 `build()` watch 了 `audioCurrentMusicProvider` / `settingsServiceProvider` / `librarySelectionScopeProvider` / `rightQueueDrawerProvider` / `isCoverFlowImmersiveActiveProvider` / `isEffectiveWaveformEnabledProvider`；且 `_buildCurrentPage()`（约 `:846`）**每次 build 都新建非 const 的 `FoldersPage` / `LibraryPage`**（`QueuePage` / `SharingPage` 是 const，靠 `==` 短路不受影响）。

后果：**任何 `setState`（典型是 `_expandPlayback()` 置 `_isPlaybackDrawerOpen`）会把当前页 + 所有已访问页整棵子树 rebuild 一遍**，含 `IndexedStack` 里不可见的页。实测打开播放页前 3 帧因此付出 19/59/37ms CPU 忙时（帧预算 16.7ms）。

改法：拆页面 State、把页面实例缓存到字段、对 IndexedStack 子页加 `RepaintBoundary`+const 化。不要在这里随手加 `ref.watch`。

## ScannerService 订阅粒度

**禁止**裸写 `ref.watch(scannerServiceProvider)`（无 select）：它的 `notifyListeners()` 在非扫描期是**立即全量**通知，而底层 `updateSongThumbnailPath` 每生成一张缩略图就触发一次 —— 一屏歌曲滚进来就是几十次整页重建。

- 页面取实例一律 `ref.read(scannerServiceProvider)`；需响应树变化则 `scannerServiceProvider.select((s) => s.structureRevision)`（int，轻量可判等）。`structureRevision` 由 `_refreshStructureRevision()` 靠 `_computeStructureFingerprint()` 自动检测推进，不必在几十处写点手写标记。指纹 = `_rootFolders`/`_scannedRootFolders` 的长度与元素 `identityHashCode` + `_navigationState.currentFolder?.path` + `historyLength` + `metadataStore.metadataMap.length`。**指纹里不能放缩略图相关的量**，否则退化成每张缩略图触发一次重建。推进点只有三处：重写的 `notifyListeners()`（必须在扫描节流判断**之前**）、`_handleNavigationChanged()`（走 `super.notifyListeners()` 绕过重写，要单独调）、`updateMetadataForPath(syncTree: true)`（显式 `++`）。
- `MusicFolder` 是**可变对象**，内容变不改变 identity：`folder.files` 内部变动靠 `metadataMap.length` 进指纹；标签编辑（就地替换 folder.files 里的 MusicFile）指纹看不到，靠上面第三条显式 `++` 兜底。
- **`rootFolders` getter 返回缓存视图 `_rootFoldersView`**，不要现写 `List.unmodifiable(_rootFolders)` —— 那样每次都是新实例，`select` 永不判等（历史坑：`folder_root_view` / `onboarding_page` / `music_folders_dialog`）。结构变化时在 `_refreshStructureRevision()` 里置空；视图存元素**引用**，folder.files 变动无需重建视图即可见。
- `ScanProgressInfo` **没有覆写 `==`**，故 `ScanProgressInfoNotifier` 每次 build 都刷新全部下游，且会把 stream 的实时进度覆盖回 `_lastLocalProgressInfo`。它的 `build()` 只能 select 极小粒度（现只订阅 `isScanning`），**不能**换成 `ref.read` —— 那样本地扫描结束时没有路径把 state 复位成 `isScanning: false`。

## 页面转场与 ink 反馈（Android）

`lib/main.dart` 的 `pageTransitionsTheme` 里 **android 必须用 `ZoomPageTransitionsBuilder(allowSnapshotting: false)`**：默认 Zoom 转场的 `_ZoomExitTransition` 会给下层页面套 `SnapshotWidget`，返回时把下层**当前画面截成静态图**播完整个转场，恢复绘制第一帧下层 ink 水波纹还没 tick 归零（覆盖期间 `TickerMode(false)` 冻结），表现为「返回时上一页被点击的入口残留高亮」。前提：ink 动画（InkSparkle 617ms / InkRipple 600ms）远长于路由过渡 300ms，push 完成时水波纹必然停在中途。iOS/macOS 走 Cupertino 无此问题，windows/linux 仍是默认 Zoom（未处理）。`FadeUpwardsPageTransitionsBuilder` 或全局去涟漪也能规避，但视觉不符 / 丢点击反馈，不采纳。

## 播放页音频规格信息（PlaybackAudioInfoLabel）

渲染在 `lib/widgets/playback/playback_progress_section.dart:304`，由 `playback_controls.dart` 三处调用（竖屏 overlay / 横屏 / 普通竖屏），位于进度条+按钮行下方；受设置项 `showPlaybackAudioInfo` 控制，文本 `formatAudioSpec()` 拼成 `FORMAT · 24BIT · 96 kHz · 1411 kbps`（缺项自动跳过）。

数据源只有 `currentAudioDetailsProvider`（`lib/player/audio/audio_riverpod.dart`，`CurrentAudioDetailsNotifier`），四级优先级：内存缓存(`sampleRate>0`) → `currentMusic.sampleRate>0` → `scanner.metadataMap[path].sampleRate>0` → `buildFastAudioDetails()` 兜底（**只按扩展名推 format，其余全 0**）+ 350ms 后 `_loadRefinedDetails()` 走内核 TagLib 精解析。

**坑 1（2026-10-17 定位并已修）：rebuild 会吞掉精解析定时器。** riverpod 在 provider 重建时**先**跑 `ref.onDispose`（`ProviderElement._performRebuild()` → `runOnDispose()`；`Ref.onDispose` 文档明确包含 rebuild）。而 `MusicFile.==` 覆盖了 `thumbnailPath`/`artworkPath`/`durationMillis`，`themeColorsBlob`/`waveformBlob`/`artworkBytes` 用 `identical` 比较 —— 切歌后封面/主题色/波形回写都会让 `audioCurrentMusicProvider` 发新值 → 本 notifier 重建 → 定时器被取消。只要该 350ms 窗口内发生过一次重建，精解析**永不执行**，只剩格式名（「有时有有时没有」的真因）。修法：`_armRefine()` 幂等、早退分支补挂；截止时刻锚在「切歌」而非「最后一次 build」，窗口被反复打断时直接执行避免饿死；`_refineTriedPath` 防重复 FFI。

**坑 2：`setCachedAudioDetails` 是无条件写入**（`audio_service.dart:3151/3166`、`audio_riverpod.dart`）。`sampleRate == 0` 的空结果一旦进缓存，同曲目后续会跳过第 1 级、落到 `fastDetails = 缓存里的原始 details` → 整行空白，只能靠重启或超出 `_maxAudioDetailsCacheSize = 100` 淘汰恢复。

**坑 3：远程曲目（subsonic/jellyfin/webdav/smb）** `buildMusicFileFromSubsonic`（`remote_media_resolver.dart:370`）不填 sampleRate/format，path 是 `subsonic://serverId/trackId` 无扩展名，只能靠 `name = '$title.$suffix'` 兜底格式名；`getAudioDetails` 仅当 `streamCacheManager.isTrackCached == true` 才用缓存文件解析 → 「同曲目缓存前没有、缓存后有」。可优化：Subsonic/Jellyfin 的 trackJson 自带 `samplingRate`/`bitRate`/`channelCount`，当前没读。

## 性能排查的两个坑

- **`stackDepth: 128` 会截断深层栈的根侧帧**（DevTools 导出 profile）。按「栈内是否含 `drawFrame`/`flushSemantics`」做阶段归属时，深层 rebuild 栈会系统性少算这些帧。结论以 **leaf 自耗时**为准。
- **设备侧无障碍服务开启时 semantics 全程开启**，播放页整页 `Transform.translate` 滑动会让语义树几何每帧失效、全量重传（实测 `__updateSemantics` FFI 可占自耗 9%）。项目自身没有 `ensureSemantics`/`SemanticsHandle`，遇到异常占比先确认是不是设备无障碍或 DevTools 造成的。

## 环境注意事项（本机）

- **shell 里搜索一律用 `rg` / `fd`，不要用 `grep` / `find`**：PATH 里的这两个是 WorkBuddy 的 toybox shim（自报 `toybox 0.8.13 (is not GNU grep 9.0)`），精简实现会漏匹配。原生版在 `/opt/homebrew/bin`（`rg 15.x` / `fd 10.x`）。结构化搜索优先用宿主 Grep / Glob 工具。
- `flutter` 不在 PATH：用前 `export PATH="$HOME/flutter/bin:$PATH"`。
- 沙箱拦截 `~/.pub-cache` 写入，`flutter analyze` 必须带 `--no-pub`（项目已有 `.dart_tool/package_config.json`）。
- 沙箱注入的 `HTTP_PROXY/HTTPS_PROXY` 会让 `flutter test` 全部加载失败（`WebSocketException: Invalid WebSocket upgrade request`），跑测试前必须：
  `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy all_proxy ALL_PROXY && export NO_PROXY=127.0.0.1,localhost`（`flutter analyze` 不受影响）。
- 本机没有 `groovy`/`pwsh`。Groovy 片段可用 Gradle 自带 jar 验证（Gradle 8.14 → Groovy 3.0.24）：
  `java -cp "$HOME/.gradle/wrapper/dists/gradle-8.14-all/*/gradle-8.14/lib/*" groovy.ui.GroovyMain xxx.groovy`；PowerShell 脚本无法本地验证。
