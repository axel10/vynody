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

## 环境注意事项

- Bash 工具的 `grep` 在本机结果不可靠（会漏匹配），排查代码一律优先用 Grep 工具。
- 本机没有 `groovy` 命令，但可用 Gradle 自带 jar 验证 Groovy 片段（项目用 Gradle 8.14 → Groovy 3.0.24）：
  `java -cp "$HOME/.gradle/wrapper/dists/gradle-8.14-all/*/gradle-8.14/lib/*" groovy.ui.GroovyMain xxx.groovy`
  改完 `*.gradle` 跑一遍能提前发现语法/解析错误，比等 Android 构建报错快得多。
- 本机没有 `pwsh`，PowerShell 脚本改完无法本地验证。
- `flutter` 不在 PATH，用前先 `export PATH="$HOME/flutter/bin:$PATH"`。
- 沙箱会拦截 `~/.pub-cache` 写入，直接 `flutter analyze` 会因 pub get 失败而中断，
  必须带上 `--no-pub`（项目已有 `.dart_tool/package_config.json`，够用）。

## 协作偏好

- 称呼用户直接用「你」，不要用名字。
