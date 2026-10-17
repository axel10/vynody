# 长期项目笔记

> 自动注入，约 8K 字符上限，只沉淀「会反复咬人的不变量」。排查过程与历史 bug 复盘见同日 `YYYY-MM-DD.md`。

## 单一数据源 / 唯一入口

| 主题 | 唯一来源 | 连带必须一起检查 |
|---|---|---|
| Rail 宽度 | `lib/utils/layout_constants.dart`（`kSidebarRailWidthCollapsed=80`/`Extended=216`/`sidebarRailWidthFor()`），禁止硬编码 `80.0` | `main_layout.dart` 的 `railWidth`、`SizedBox(width:)`、`_buildCurrentPage` 的 `leftPadding`；`library_page.dart` 的 `railWidth` 入参 |
| FFmpeg 产物版本/URL | `audio_core/ffmpeg_version.env`（`FFMPEG_VERSION`+`FFMPEG_BASE_URL`，可用 `FFMPEG_URL_<平台>` 整条覆盖），禁止脚本/构建文件硬编码 | apple/linux shell 直接 `source`；windows ps1 手写 KV 解析；`android/build.gradle` Groovy 解析 + `inputs.file(env)`。**离线场景需手工同步**：`packaging/flatpak/*.yml`（URL+sha256）、`.github/workflows/build-ffmpeg.yml`（release tag 须等于 `FFMPEG_VERSION`，无硬校验） |
| 曲库数据 | `lib/player/library/library_catalog.dart` 的 `libraryCatalogProvider` 是全应用唯一允许订阅 `db.watchAllSongMetadata()` 的地方 | 新视图一律 `catalogDerived(ref, (c) => ...)` 派生，禁止自己 `await for` 那个流。派生 provider 保持 `StreamProvider` 类型与名字（测试靠 `overrideWith`）。`LibraryCatalog` 聚合字段全 `late final`，必须保持惰性。过滤两层：`catalog.songs`（仅排除 external/deletedAt）vs `visibleSongs`（再加活动根目录+来源过滤），历史上有混用未统一 |
| 返回键 | `MainLayout` 的 `PopScope(canPop:false)` → `_handleBackPressed()`（`main_layout.dart` 约 `:1315`），全应用唯一裁决点 | 顺序：最上层 Modal → 播放抽屉 → index 2（媒体库）→ index 0（目录回上级）→ index 4（共享页有传输则 toast 拦）→ `SystemNavigator.pop()`；非 Android 直接 return |
| 播放队列整体替换 | `PlaylistController.replaceActiveTracksAndSelect(id, tracks, startIndex:)`（audio_core），`_playQueueTracks` 是唯一调用者 | 禁止拆成 `updatePlaylistTracks(reconcile:false)` + `playByIndex` 两步：中间会发一次 `_currentIndex = null` 通知，`currentMusic` 瞬时为 null（~100ms），收起态浮动 Dock 会据此重播一次收起动画。回归测试 `audio_core/test/playlist_replace_active_tracks_test.dart` |
| 浮动 Dock 收起态 | `floatingDockCollapsedProvider` / `floatingDockCollapseProgressProvider`（`lib/pages/main_layout_riverpod.dart`），滚动判定在 `FloatingDockScrollHelper` | 受设置项 `enableFloatingDockScrollCollapse` 控制：helper 顶部早退 + notifier `build()` 里 select 该开关（关闭即复位为展开）；视觉展开态是 `floating_dock_bottom_bar.dart` 的 `isCollapsed`。`mini_player_wrapper.dart` 与 `main_layout.dart` 各挂一个 helper 实例 |
| l10n 文案 | 9 个 `lib/l10n/app_*.arb` 同步维护（`git log -- lib/l10n/app_ja.arb` 可验证）。`l10n.yaml: template-arb-file: app_zh.arb` | 非模板 locale 缺 key 会回退到**模板语言（中文）**并记入 `untranslated message(s)`（`gen_l10n.dart:1033-1045`），日志只打 stdout。改完跑 `flutter gen-l10n` |
| 新增设置项 | `lib/player/settings/settings_service.dart`（key 段 `:443-660` / property 段 `:1076+` / 访问器段 `:2324+`） | 6 处：①`_keyXxx` 常量 ②`SettingProperty<T>` ③getter+setter ④若有重置按钮还要进对应 `resetXxx()` ⑤`settings_search_registry.dart` 手写条目（curated 列表，不能从设置派生）⑥`lib/pages/settings/sections/<组>_section.dart` UI。构造期断言拦截漏写 `customRead/customWrite` 的静默失败。`settings.<属性>` 调用点约 676 处 / 164 个属性名 |

`library_catalog.dart` ↔ `album_library.dart`/`artist_library.dart` 循环 import（Dart 允许，顶层 provider 惰性构造，无初始化顺序风险）。

## 禁止在 IndexedStack 常驻子页挂 PopScope

PopScope 注册在**路由**上，与 widget 可见性无关（`IndexedStack` 用 `Visibility(maintainState/maintainAnimation: true)` 包 child，没套 TickerMode，判可见性只能靠 `mainTabIndexProvider`）。后果两条：①`ModalRoute.popDisposition` 是聚合判断——一个 PopEntry `canPop == false` 整条路由就 `doNotPop`；②`onPopInvokedWithResult` 会派发给该路由上**全部** PopEntry（`routes.dart:2045`），别的 tab 按返回也触发。

历史 bug：共享页传输中切走再按返回会弹「正在传输文件，请勿离开共享页」，且拦不住 `SystemNavigator.pop()`。改法：删掉 `sharing_page.dart` 的 PopScope，在 `_handleBackPressed()` 加 index 4 分支。只适用于**独占一条路由**的页面：PopScope 常驻，只切 `canPop: !isSelectionMode`（`remote_control_page.dart:249`、`remote_folder_browser_page.dart:1844`）。

## 媒体库多选（LibrarySelection）

- 单一数据源 `lib/widgets/library_selection_scope.dart` 的 `librarySelectionStateProvider`（全局一份，靠 `scope` 区分实体类型）。页面经 `SelectionStateMixin`/`SongSelectionMixin` 接入，dispose 用 `Future.microtask(clearIfScope(scope))` 收尾。
- **禁止**按多选状态在「包一层 PopScope」与「返回原 widget」间条件切换：根节点 runtimeType 一变子树就销毁重建，持有选中项的 widget 的 dispose 微任务会清掉刚建立的多选状态（一进多选就退出），搜索词/排序/滚动位置全丢。回归测试 `test/pages/library_multiselect_test.dart`（错误写法下 4 条失败）。

## 媒体库条目右键菜单（全站统一三件套）

新增实体照抄（已有 album/artist/genre/year）：①`lib/widgets/<entity>_context_menu.dart`：`show<Entity>ContextMenu`（`AppContextMenu.show` + `buildContextMenuItem`，后者在 `lib/utils/song_context_menu_utils.dart`）+ `show<Entity>BottomSheet` + 共用 `_handle<Entity>MenuAction`；②条目根节点挂 `GestureDetector(behavior: opaque, onSecondaryTapDown, onLongPress)`；③l10n 需 `view<Entity>Details`/`copy<Entity>Name`。覆盖媒体库二级页 + `library_dashboard_view.dart` 首页五类卡片（**不传** `onMultiSelect`）。回归测试 `test/widgets/views_layout_smoke_test.dart`（`buttons: kSecondaryMouseButton`）。

## MainLayout 是全应用 rebuild 的放大器

`build()` watch 了 `audioCurrentMusicProvider`/`settingsServiceProvider`/`librarySelectionScopeProvider`/`rightQueueDrawerProvider`/`isCoverFlowImmersiveActiveProvider`/`isEffectiveWaveformEnabledProvider`；且 `_buildCurrentPage()`（约 `:846`）每次 build 都新建非 const 的 `FoldersPage`/`LibraryPage`（`QueuePage`/`SharingPage` 是 const，靠 `==` 短路）。

后果：任何 `setState`（典型是 `_expandPlayback()` 置 `_isPlaybackDrawerOpen`）会 rebuild 当前页 + 所有已访问页整棵子树，含 `IndexedStack` 里不可见的页（实测打开播放页前 3 帧 CPU 忙时 19/59/37ms，预算 16.7ms）。改法：拆页面 State、实例缓存到字段、子页加 `RepaintBoundary`+const 化。不要在这里随手加 `ref.watch`。

## ScannerService 订阅粒度

**禁止**裸写 `ref.watch(scannerServiceProvider)`（无 select）：非扫描期 `notifyListeners()` 是立即全量通知，而 `updateSongThumbnailPath` 每生成一张缩略图就触发一次 —— 一屏歌曲滚进来就是几十次整页重建。

- 取实例一律 `ref.read`；需响应树变化用 `.select((s) => s.structureRevision)`（int）。`_refreshStructureRevision()` 靠 `_computeStructureFingerprint()` 自动推进。指纹 = `_rootFolders`/`_scannedRootFolders` 长度与元素 `identityHashCode` + `currentFolder?.path` + `historyLength` + `metadataMap.length`，**不能放缩略图相关的量**。推进点三处：重写的 `notifyListeners()`（须在节流判断**之前**）、`_handleNavigationChanged()`（走 `super.notifyListeners()` 绕过重写，要单独调）、`updateMetadataForPath(syncTree: true)`（显式 `++`）。
- `MusicFolder` 是**可变对象**，内容变不改变 identity：`folder.files` 内部变动靠 `metadataMap.length` 进指纹；标签编辑（就地替换 MusicFile）指纹看不到，靠上面第三条兜底。
- **`rootFolders` getter 返回缓存视图 `_rootFoldersView`**，不要现写 `List.unmodifiable(...)`（每次新实例，`select` 永不判等；历史坑 `folder_root_view`/`onboarding_page`/`music_folders_dialog`）。结构变化时在 `_refreshStructureRevision()` 置空；视图存元素引用。
- `ScanProgressInfo` **没有覆写 `==`**，故 `ScanProgressInfoNotifier` 每次 build 刷新全部下游。它的 `build()` 只能 select 极小粒度（现只订阅 `isScanning`），**不能**换成 `ref.read` —— 那样本地扫描结束就没有路径把 state 复位成 `isScanning: false`。

## 页面转场（Android）

`lib/main.dart` 的 `pageTransitionsTheme` 里 android 必须用 `ZoomPageTransitionsBuilder(allowSnapshotting: false)`：默认 Zoom 的 `_ZoomExitTransition` 给下层套 `SnapshotWidget`，返回时把下层画面截成静态图播完整个转场，恢复绘制第一帧时 ink 水波纹还没 tick 归零（覆盖期 `TickerMode(false)` 冻结）→「返回时上一页被点击的入口残留高亮」。前提是 ink 动画（600ms+）远长于路由过渡 300ms。iOS/macOS 走 Cupertino 无此问题，windows/linux 未处理。

## 播放页音频规格信息（PlaybackAudioInfoLabel）

渲染在 `lib/widgets/playback/playback_progress_section.dart:304`（`playback_controls.dart` 三处调用），受设置项 `showPlaybackAudioInfo` 控制，`formatAudioSpec()` 拼成 `FORMAT · 24BIT · 96 kHz · 1411 kbps`。数据源唯一：`currentAudioDetailsProvider`（`lib/player/audio/audio_riverpod.dart`），四级缓存链 + 350ms 后 TagLib 精解析。

三条坑（详见 2026-10-17 日志）：①provider 重建会**先**跑 `ref.onDispose`，而切歌后封面/主题色/波形回写都会触发重建 → 精解析定时器被取消，是「有时有有时没有」的真因（已修）。②`setCachedAudioDetails` 无条件写入，`sampleRate == 0` 的缓存会让该曲目整行空白。③远程曲目 path 无扩展名、`getAudioDetails` 仅在已缓存时解析，trackJson 的 `samplingRate`/`bitRate` 未读。

## 流派封面（assets/images/genre/webp）与图标（assets/icons/genre）

**封面键 ≠ 图标键，已解耦**（2026-10-17）。封面按素材原名用连字符（`hip-hop.webp`/`r-b.webp`/`lo-fi.webp`/`j-pop.webp`/`k-pop.webp`/`anime.webp`/`music.webp` 兜底），图标沿用下划线（`hip_hop.svg`/`rnb.svg`/`lofi.svg`），日系三张图共用 `anime_jpop.svg`。对应关系在 `genre_naming.dart` 的 `_iconKeyByImageKey`；`genreImageAssetKey()` 走 `matchGenreAssetKey() ?? kFallbackGenreAssetKey`，`genreIconAssetKey()` 再查那张表。两者曾靠「同名」隐式耦合，改名即静默 404。

**封面统一 500×750（2:3）**，卡片与缩略图都按 `kGenreCoverHeightFactor = 3/2` 推导（`library_dashboard_view.dart`）。`kGenreAssetKeys` 必须与 webp 文件名逐字一致 —— 有测试双向比对目录与清单，改名漏同步会直接失败。子串规则的 needle 是归一化后的空格形式，只有资源键用连字符。

**首页流派横向行按封面去重**：`dedupeGenresByCoverArt()`（`genre_summary.dart`）。封面键多对一（Rap/Trap/Drill → hip-hop），多个流派会排出多张相同图；兜底 `music.webp` 同理。每组取 `songCount` 最大者作代表、沿用首次出现位置，**兜底封面（`GenreSummary.usesFallbackCover`）固定排最后**。**流派列表页 `genres_tab` 不去重**（那里有文字标签，且要能进每一个流派）。

**首页流派卡文字层**：卡片是纯图 + 左下角「流派名 / N 首」，**不加暗色渐变层**（用户明确要求，会把封面压灰），可读性靠 `kGenreLabelShadows`（三层半径递减的黑阴影）。字号由卡宽等比推导 `(width * 0.082).clamp(14, 23)`，因为 `kDashboardGenreCardScale` 用户常年调到 1.5；写死字号会显小。曲目数 alpha 0.9。封面素材本身已不带字样，不要再加 `Semantics(label:)` 重复朗读。

**条目大小调 `kDashboardGenreCardScale`**（`library_dashboard_view.dart`，宽度与间距同步缩放，高度按 2:3 跟随；基准是 `kDashboardGenreCardWidthWide = 180` / `Narrow = 132`，别直接改基准）。系数是设计侧常用旋钮，会被反复调，别当成固定值假设。

图标渲染点只剩 `genres_tab.dart`（12px）；首页流派卡左上角的图标徽章已于 2026-10-17 移除。

24 个 `*.svg` 由 `genre_naming.dart` 的 `genreIconAssetKey()` 映射（都是 `colorFilter: srcIn` 着色，所以 SVG 里只要保持白色填充/描边即可）。

**两套来源混用**：15 个是位图描摹（`viewBox 0 0 100 100`、纯 `L` 折线），9 个是字体字形（`viewBox 0 0 512 512` + `scale(...,-...)`）。2026-10-17 已把描摹的 15 个重做（8 个手绘 + 7 个平滑重拟合），字体那 9 个未动。新增/替换图标：统一 `viewBox="0 0 100 100"`、内容留 10~90 的 10 单位边距、线宽≈7，`<path fill="#FFFFFF">` 或 `fill="none" stroke="#FFFFFF"`。

改完必须用 `encodeSvg()`（vector_graphics_compiler，flutter_svg 同解析器）逐个编译验证；flutter_test 里要关掉三个 optimizer（`enableMasking/Clipping/OverdrawOptimizer: false`），否则 `PathOps library was not initialized`。

## 环境注意事项（本机）

- **shell 里搜索一律用 `rg`/`fd`，不要用 `grep`/`find`**：PATH 里的这两个是 WorkBuddy 的 toybox shim（`toybox 0.8.13 (is not GNU grep 9.0)`），精简实现会漏匹配。原生版在 `/opt/homebrew/bin`，结构化搜索优先用宿主 Grep/Glob 工具。
- `flutter` 不在 PATH：用前 `export PATH="$HOME/flutter/bin:$PATH"`。
- 沙箱拦截 `~/.pub-cache` 写入，`flutter analyze` 必须带 `--no-pub`。
- 沙箱注入的 `HTTP_PROXY/HTTPS_PROXY` 会让 `flutter test` 全部加载失败（`WebSocketException: Invalid WebSocket upgrade request`），跑测试前必须 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy all_proxy ALL_PROXY && export NO_PROXY=127.0.0.1,localhost`。
- 本机没有 `groovy`/`pwsh`。Groovy 片段可用 Gradle 自带 jar 验证：`java -cp "$HOME/.gradle/wrapper/dists/gradle-8.14-all/*/gradle-8.14/lib/*" groovy.ui.GroovyMain xxx.groovy`。
