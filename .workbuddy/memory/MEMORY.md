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
  正确写法：PopScope 常驻，只切 `canPop: !isSelectionMode`（参考 `sharing_page.dart:721`、
  `remote_control_page.dart:249`、`remote_folder_browser_page.dart:1844`）。
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

## 协作偏好

- 称呼用户直接用「你」，不要用名字。
