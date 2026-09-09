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

## 环境注意事项

- Bash 工具的 `grep` 在本机结果不可靠（会漏匹配），排查代码一律优先用 Grep 工具。
- 本机没有 `groovy` 命令，但可用 Gradle 自带 jar 验证 Groovy 片段（项目用 Gradle 8.14 → Groovy 3.0.24）：
  `java -cp "$HOME/.gradle/wrapper/dists/gradle-8.14-all/*/gradle-8.14/lib/*" groovy.ui.GroovyMain xxx.groovy`
  改完 `*.gradle` 跑一遍能提前发现语法/解析错误，比等 Android 构建报错快得多。
- 本机没有 `pwsh`，PowerShell 脚本改完无法本地验证。

## 协作偏好

- 称呼用户直接用「你」，不要用名字。
