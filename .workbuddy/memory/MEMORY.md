# 长期项目笔记

## FFmpeg 预编译产物下载地址集中管理

约定：`audio_core/ffmpeg_version.env` 是**唯一**的下载地址/版本来源，新增平台必须从这里读，禁止在脚本/构建文件里硬编码。

env 文件格式：
```
FFMPEG_VERSION=0.7
FFMPEG_BASE_URL=https://github.com/axel10/audio_core/releases/download
# 平台级覆盖（可选，设置后整条覆盖，忽略上面两项）
# FFMPEG_URL_APPLE= / FFMPEG_URL_LINUX= / FFMPEG_URL_WINDOWS= / FFMPEG_URL_ANDROID=
```

各平台接入情况（截至 2026-09-09，已全部接入）：
- `download-ffmpeg-apple.sh` / `download-ffmpeg-linux.sh`：shell，`source` env
- `download-ffmpeg-windows.ps1`：手写 KV 解析（跳过 `#` 开头行）
- `android/build.gradle` 的 `downloadFFmpeg` 任务：Groovy 手写解析 +
  `inputs.file(env)` 声明（改版本能让任务失效重跑）+ `ffmpeg_lib/version.txt` 版本校验

改版本时必须手工同步的**离线场景**（读不到 env）：
- `packaging/flatpak/io.github.axel10.vynody.yml`：URL 和 `sha256` 都要改；`generated/` 是 flatpak-builder 产物，不要手改
- `.github/workflows/build-ffmpeg.yml`：发布用的 release tag 必须与 `FFMPEG_VERSION` 一致（目前只在输入框描述里写了提示，未做硬校验）

调用链（改脚本路径时要一并检查）：
- Apple: `cargokit/build_pod.sh` → `download-ffmpeg-apple.sh`
- Linux: `cargokit/cmake/cargokit.cmake` → `download-ffmpeg-linux.sh`
- Windows: `windows/CMakeLists.txt` / `download_sources.sh` → `download-ffmpeg-windows.ps1`

## 左侧导航栏（Rail）宽度常量集中管理

约定：`lib/utils/layout_constants.dart` 是 rail 宽度的**唯一**来源，禁止在页面里硬编码 `80.0`：
- `kSidebarRailWidthCollapsed = 80.0`（纯图标）
- `kSidebarRailWidthExtended = 216.0`（图标 + 文字）
- `kSidebarRailExtendedMinWindowWidth = 900.0`
- `sidebarRailWidthFor(windowWidth)` 按窗口宽度返回实际宽度

涉及位置（改宽度时必须一起检查）：`main_layout.dart` 的 `railWidth` / `SizedBox(width:)` /
`_buildCurrentPage` 的 `leftPadding`，以及 `library_page.dart` 的 `railWidth` 入参。

桌面端媒体库已取消顶部 TabBar，六个二级入口改由 Rail 承载（折叠式，仅媒体库页激活时展开），
设置页钉在 Rail 左下角；窗口高度不足时 Rail 中间区可滚动。竖屏/移动端仍走
卡片索引页 + `LibrarySubPage`。

## 媒体库多选（LibrarySelection）约定

- 单一数据源：`lib/widgets/library_selection_scope.dart` 的 `librarySelectionStateProvider`
  （全局一份，靠 `scope` 区分 library / artist / album / playlist / queue / folder / genre / year …）。
  页面通过 `SelectionStateMixin` / `SongSelectionMixin` 接入，两个 mixin 的 `dispose` 会用
  `Future.microtask(clearIfScope(scope))` 收尾。
- **禁止**按多选状态条件性地在「包一层 PopScope」与「返回原 widget」之间切换：
  根节点 runtimeType 一变，Flutter 会销毁并重建整棵子树，持有选中项的 widget 也在其中，
  其 dispose 的微任务会把刚建立的多选状态清掉（表现为一进入多选就退出），
  同时搜索词/排序/滚动位置等 State 全部丢失。
  正确写法：PopScope 常驻，只切 `canPop: !isSelectionMode`（参考
  `remote_control_page.dart:249`、`remote_folder_browser_page.dart:1844`）。
  但**只适用于自己独占一条路由的页面**；常驻在 `IndexedStack` 里的 tab 页不能这么干（见下节）。
- 测试：`test/pages/library_multiselect_test.dart`（真实页面级：LibrarySubHostPage + ArtistsTab、
  横屏内嵌歌曲多选、专辑/艺术家详情页、返回键语义）。该文件在「条件性 PopScope」写法下会有 4 条失败，
  可用来验证这类回归。

## 媒体库条目的右键菜单（全站统一三件套）

新增「一类实体」的右键菜单照抄三件套（已有 album / artist / genre / year）：
1. `lib/widgets/<entity>_context_menu.dart`：`show<Entity>ContextMenu`（`AppContextMenu.show` +
   `buildContextMenuItem`，后者定义在 `lib/utils/song_context_menu_utils.dart`）
   + `show<Entity>BottomSheet` + 共用的 `_handle<Entity>MenuAction`。
2. 卡片/列表项根节点挂 `GestureDetector(behavior: HitTestBehavior.opaque, onSecondaryTapDown, onLongPress)`；
   右键 → ContextMenu，长按 → BottomSheet。已用 `InkWell` 的（艺术家条目）直接用其自带回调。
3. l10n 需要 `view<Entity>Details` / `copy<Entity>Name` 两个键，改完 9 个 arb 必须跑 `flutter gen-l10n`。

覆盖范围（截至 2026-10-16 全部接通）：媒体库二级页（专辑/艺术家/流派/年份 tab）、
`library_dashboard_view.dart` 首页五类卡片（歌曲/专辑/艺术家/流派/年份）。
仪表盘的卡片**不传** `onMultiSelect`（首页没有多选 UI），所以菜单里没有「多选」项。
回归测试：`test/widgets/views_layout_smoke_test.dart` 的「五类条目均支持右键菜单」
（`tester.tap(..., buttons: kSecondaryMouseButton)`，需 `import 'package:flutter/gestures.dart'`）。

## MainLayout 是全应用 rebuild 的放大器

`main_layout.dart` 的 `MainLayout.build()` 里 watch 了 `audioCurrentMusicProvider` /
`settingsServiceProvider` / `librarySelectionScopeProvider` / `rightQueueDrawerProvider` /
`isCoverFlowImmersiveActiveProvider` / `isEffectiveWaveformEnabledProvider`，并且
`_buildCurrentPage()`（约 `:846`）**每次 build 都新建非 const 的 `FoldersPage` / `LibraryPage` 实例**
（`QueuePage` / `SharingPage` 是 `const`，靠 `==` 短路，不受影响）。

后果：**任何 `setState`（最典型是 `_expandPlayback()` 置 `_isPlaybackDrawerOpen`）都会
把当前页 + 所有已访问页的整棵子树 rebuild 一遍**，包括 `IndexedStack` 里不可见的那几页。
实测打开播放页的前 3 帧因此付出 19/59/37ms 的 CPU 忙时（帧预算 16.7ms）。

改这块时要留意：拆页面 State、或把页面实例缓存到字段、或对 IndexedStack 子页加
`RepaintBoundary`+const 化，都能直接削掉这个代价；不要在这里随手加 `ref.watch`。

## 性能排查时的两个坑

- **`stackDepth: 128` 会把深层栈的根侧帧截断**（DevTools 导出的 CPU profile）。
  按「栈内是否含 `drawFrame` / `flushSemantics`」做阶段归属时，深层 rebuild 栈会系统性少算这些帧。
  结论要以 **leaf 自耗时** 为准，不要只看 inclusive。
- **真机/模拟器开了无障碍服务时 semantics 全程开启**，播放页整页 `Transform.translate` 滑动会让
  语义树几何每帧失效、全量重传（实测 `__updateSemantics` FFI 可占自耗 9%）。
  项目自身没有 `ensureSemantics` / `SemanticsHandle`，遇到这类异常占比先确认是不是设备侧无障碍或 DevTools 造成的。

## 环境注意事项

- Bash 工具的 `grep` 在本机结果不可靠（会漏匹配），排查代码一律优先用 Grep 工具。
- 本机没有 `groovy` 命令，但可用 Gradle 自带 jar 验证 Groovy 片段（项目用 Gradle 8.14 → Groovy 3.0.24）：
  `java -cp "$HOME/.gradle/wrapper/dists/gradle-8.14-all/*/gradle-8.14/lib/*" groovy.ui.GroovyMain xxx.groovy`
  改完 `*.gradle` 跑一遍能提前发现语法/解析错误，比等 Android 构建报错快得多。
- 本机没有 `pwsh`，PowerShell 脚本改完无法本地验证。
- `flutter` 不在 PATH，用前先 `export PATH="$HOME/flutter/bin:$PATH"`。
- 沙箱会拦截 `~/.pub-cache` 写入，直接 `flutter analyze` 会因 pub get 失败而中断，
  必须带上 `--no-pub`（项目已有 `.dart_tool/package_config.json`，够用）。
- 沙箱注入的 `HTTP_PROXY/HTTPS_PROXY` 会让 `flutter test` 全部加载失败
  （`Unable to connect to flutter_tester process: WebSocketException: Invalid WebSocket upgrade request`），
  跑测试前必须清掉代理：
  `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy all_proxy ALL_PROXY && export NO_PROXY=127.0.0.1,localhost`
  （`flutter analyze` 不受影响，无需清）。

## ScannerService 订阅粒度约定

**禁止**在页面/Widget 里裸写 `ref.watch(scannerServiceProvider)`（无 select）。
它的 `notifyListeners()` 在非扫描期是**立即全量**通知，而底层的
`updateSongThumbnailPath` 每生成一张缩略图就会触发一次 —— 一屏歌曲滚进来就是几十次整页重建。

- 页面拿实例一律 `ref.read(scannerServiceProvider)`；需要响应树变化的，订阅
  `scannerServiceProvider.select((s) => s.structureRevision)`（int，轻量可判等）。
- `structureRevision` 由 `_refreshStructureRevision()` 推进，靠
  `_computeStructureFingerprint()` **自动检测**，不需要在几十处树写入点手写标记：
  指纹 = `_rootFolders`/`_scannedRootFolders` 的长度与元素 `identityHashCode`
  + `_navigationState.currentFolder?.path` + `historyLength` + `metadataStore.metadataMap.length`。
- **指纹里不能放任何缩略图相关的量**，否则又退化成每张缩略图触发一次重建。
- 调用点只有三个：重写的 `notifyListeners()`（必须在扫描节流判断**之前**）、
  `_handleNavigationChanged()`（它走 `super.notifyListeners()`，绕过了重写，要单独调）、
  `updateMetadataForPath(syncTree: true)`（显式 `++`）。
- `MusicFolder` 是**可变对象**，内容变不改变 identity。所以：
  - `folder.files` 内部变动靠 `metadataMap.length` 进指纹；
  - 标签编辑（就地替换 folder.files 里的 MusicFile）指纹看不到，靠上面第三条显式 `++` 兜底。
- **`rootFolders` getter 返回缓存视图 `_rootFoldersView`**，不要在 getter 里现写
  `List.unmodifiable(_rootFolders)` —— 那样每次都是新实例，`select` 永不判等，等于没 select
  （历史上 `folder_root_view` / `onboarding_page` / `music_folders_dialog` 三处都是这个坑）。
  结构变化时在 `_refreshStructureRevision()` 里置空。视图存的是元素**引用**，
  所以 folder.files 的变动无需重建视图即可见。
- `ScanProgressInfo` **没有覆写 `==`**，所以 `ScanProgressInfoNotifier` 每次 build 都会刷新
  全部下游，且会把 stream 推的实时进度覆盖回 `_lastLocalProgressInfo`。它的 `build()` 里
  只能 select 极小粒度（现在只订阅 `isScanning`），**不能**直接换成 `ref.read`——
  那样本地扫描结束时没有路径把 state 复位成 `isScanning: false`。

## Android 返回键的唯一裁决点：MainLayout

`MainLayout` 那个 `PopScope(canPop: false)`（`main_layout.dart:1315` 附近）是全应用唯一的返回入口，
回调里执行 `_handleBackPressed()`，顺序为：最上层 Modal → 播放抽屉 → `_currentIndex == 2`
（媒体库 3D 视图 / 子页）→ `_currentIndex == 0`（目录页回上级）→ `_currentIndex == 4`
（共享页：有进行中传输则 toast 拦住，否则继续往下）→ `SystemNavigator.pop()`。
非 Android 平台该函数直接 return。

**禁止在 IndexedStack 的常驻子页里挂 PopScope 做「确认/拦截」**：PopScope 注册在**路由**上，
与 widget 可不可见无关（`IndexedStack` 用 `Visibility(maintainState/maintainAnimation: true)`
包 child，连 TickerMode 都没套，判断可见性只能靠 `mainTabIndexProvider`）。两个后果：
1. `ModalRoute.popDisposition` 是聚合判断 —— 只要有一个 PopEntry 说 `canPop == false`，
   整条路由就是 `doNotPop`；
2. `ModalRoute.onPopInvokedWithResult` 会把回调派发给该路由上**全部** PopEntry
   （`routes.dart:2045`），所以别的 tab 按返回也会触发这一页的回调。

历史 bug：共享页传输中切到其他 tab 按返回 → 弹出「正在传输文件，请勿离开共享页」；
同时它自己的 `canPop: false` 又拦不住 `_handleBackPressed()` 末尾的 `SystemNavigator.pop()`，
即「禁止离开」只有提示没有拦截。已改为：删掉 `sharing_page.dart` 的 PopScope，
在 `_handleBackPressed()` 里加 index 4 分支。

## 页面转场与 ink 反馈（Android）

`lib/main.dart` 的 `pageTransitionsTheme` 里 **android 必须用
`ZoomPageTransitionsBuilder(allowSnapshotting: false)`**（2026-10-16 真机验证后落地）。
默认的 Zoom 转场中，`_ZoomExitTransition` 会给下层页面套 `SnapshotWidget`
（动画进行中 `allowSnapshotting = true`），返回时把下层页面的**当前画面截成静态图**播完整个转场；
而恢复绘制的第一帧，下层页面的 ink 水波纹还没被 tick 归零（页面被覆盖期间被
`TickerMode(false)` 冻结，恢复后要等下一次 `handleBeginFrame` 才 tick），
于是表现为「按返回键时上一页被点击的入口残留高亮，动画结束后消失」。

相关事实：
- ink 动画总时长（Android M3 默认 InkSparkle 617ms / InkRipple 225+375ms）远长于路由过渡
  300ms，所以 push 完成时水波纹必然还停在中途 —— 这是该现象成立的前提。
- iOS/macOS 走 Cupertino 转场、无 SnapshotWidget，所以没这个问题；
  windows/linux 目前仍是默认 Zoom（同一机制存在，尚未处理）。
- 换成 `FadeUpwardsPageTransitionsBuilder` 或全局去掉涟漪也能规避，但前者视觉不符、
  后者丢失点击反馈，均不作为选项。
- 排查全过程见 `2026-10-16.md`。

## 曲库单一数据源（LibraryCatalog）约定

**全应用只有 `lib/player/library/library_catalog.dart` 的 `libraryCatalogProvider` 允许订阅
`db.watchAllSongMetadata()`。** 新增任何曲库视图（按专辑/艺术家/流派/年份/评分/播放次数的聚合）
一律走 `catalogDerived(ref, (catalog) => ...)` 从快照派生，禁止再自己 `await for` 那个流 ——
否则就回到「一次 songs 表写入触发 N 路全表重扫」的老问题。

- `LibraryCatalog` 的聚合字段全是 `late final`，**必须保持惰性**：
  只打开年份页时只算年份，不能变成「算全部」。这是不产生单页回归的前提。
- 派生 provider 必须保持 `StreamProvider<...>` 类型与名字，
  因为测试用 `overrideWith((ref) => Stream.value(...))`（如
  `test/widgets/views_layout_smoke_test.dart:426/431`）。
- 过滤语义目前**两层**：`catalog.songs`（仅排除 external / deletedAt）与
  `catalog.visibleSongs`（再加活动根目录 + 来源过滤）。
  `allRatedSongsProvider` / `timeMachineAlbumsProvider` 用前者，其余用后者 —— 是历史遗留的不一致，
  尚未统一。
- `library_catalog.dart` ↔ `album_library.dart` / `artist_library.dart` 是**循环 import**
  （Dart 允许；顶层 provider 都是惰性构造，无初始化顺序风险）。改这几个文件时别被绕晕。
- `ArtistLibraryRepository.buildSummariesFor()` 是艺术家聚合的唯一实现，
  `watchArtistSummaries()` 只是它的流式包装，仍被 `audio_service.dart` 的
  「播放下一首/上一首艺术家」使用（那条路径每次全表扫一次，低频，未优化）。
- catalog 常驻（媒体库页在 MainLayout 的 IndexedStack 里常驻，dashboard 又在 Navigator 栈底），
  所以它是长期活着的单例快照；这也是它能省下 5 份重复 `SongMetadata` 的原因。

## 协作偏好

- 称呼用户直接用「你」，不要用名字。
