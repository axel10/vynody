# Vynody F-Droid 上架适配工作计划

## 1. 现状分析

目前项目（`app.vynody.player`，`GPL-3.0`）已具备较好的开源基础（无闭源 SDK 追踪器、Git 仓库未跟踪 `.jks`/`.so` 等二进制文件、`audio_core` 已自带 Android FFmpeg 源码编译脚本 [audio_core/build-ffmpeg-android.sh](../../audio_core/build-ffmpeg-android.sh)），但在直接提交 F-Droid 构建与扫描时会存在以下阻塞项：

1. **Google Play Billing 非自由依赖**：[pubspec.yaml](../../pubspec.yaml) 引入了 `in_app_purchase`（[pubspec.lock](../../pubspec.lock) 解析出 `in_app_purchase_android`），会将闭源的 Google Play Billing Library 编译进 Android APK。
2. **FFmpeg 预编译二进制下载**：[audio_core/android/build.gradle](../../audio_core/android/build.gradle) 中的 `downloadFFmpeg` 任务会在缺失 `audio_core/android/ffmpeg_lib` 时从 GitHub Releases 下载预编译 `.so` 压缩包。
3. **SQLite 预编译二进制下载**：`sqlite3`（`3.9.1`）在未配置 `hooks.user_defines.sqlite3` 时，默认在 [hook/build.dart](../../.pub-cache/hosted/pub.flutter-io.cn/sqlite3-3.9.1/hook/build.dart) 中从 GitHub Releases 下载预编译 `libsqlite3.so`。
4. **缺少 F-Droid 商店元数据与构建配方**：仓库缺少 `fastlane/metadata/android/` 目录与对应的 F-Droid 构建配方模板。

---

## 2. 痛点与约束

- **零破坏性要求**：不能影响现有 Windows、macOS、Linux、iOS、App Store、Microsoft Store 以及 GitHub Actions 的构建产物与发版流程。
- **可维护性**：自研 Flutter 插件仍需保留在 `pubspec.yaml` 中（通过已入库的 `pubspec.lock` 锁定提交），避免每次更新插件都要手动同步哈希。
- **断网可构建**：F-Droid 构建机在 `prebuild` 阶段之后处于断网隔离环境，正式 `build` 阶段不得发生任何网络下载。

---

## 3. 理想状态

1. 提供一套可重复执行的 F-Droid 预处理脚本（例如 `scripts/fdroid_prebuild.sh`），在隔离构建前自动完成：
   - 剔除 `pubspec.yaml` 中的 `in_app_purchase` / `in_app_purchase_storekit` 并切换为纯开源无内购 stub 实现；
   - 配置 `sqlite3` 使用 `source: source` 从 SQLite 官方 C amalgamation 源码编译；
   - 调用 `audio_core` 的源码下载与 `build-ffmpeg-android.sh` 完成 FFmpeg 现场交叉编译，并写入匹配的 `version.txt` 使 Gradle 跳过联网下载；
   - 预取 Flutter Pub 与 Rust Cargo 依赖（离线可用）。
2. 仓库内补齐标准 `fastlane/metadata/android/` 元数据（中/英文简介、图标、截图、changelog）以及 `packaging/fdroid/app.vynody.player.yml` 配方模板。
3. 使用 `fdroid scanner` 与断网构建验证通过：APK 内所有 `.so` 均来自源码编译，Gradle 依赖树无任何非自由库。

---

## 4. 改动方法（待确认后实施）

1. **IAP 剥离层**
   - 将 [lib/player/pro/iap_service.dart](../../lib/player/pro/iap_service.dart) 拆分为可替换结构，或在 F-Droid 预处理脚本中将其替换为无 `package:in_app_purchase` 依赖的 FOSS 空实现（默认与 `AppChannel.isGitHubRelease` 一致，直接解锁完整功能）。
2. **F-Droid 预处理脚本（`scripts/fdroid_prebuild.sh`）**
   - 自动修改临时构建工作区内的 `pubspec.yaml`（移除 IAP 依赖、写入 `hooks.user_defines.sqlite3` 指向本地下载校验后的 `sqlite3.c`）。
   - 执行 `audio_core/download_sources.sh` 与 `audio_core/build-ffmpeg-android.sh` 生成 `ffmpeg_lib` 并写入 `audio_core/ffmpeg_version.env` 对应的 `version.txt`。
   - 执行 `flutter pub get` 与 Rust `cargo fetch` / `cargo vendor`，保证后续 `build` 阶段完全离线。
3. **FFmpeg / Audio Core 离线兼容性检查**
   - 确认 [audio_core/android/build.gradle](../../audio_core/android/build.gradle) 在 `ffmpeg_lib` 与 `version.txt` 已存在时完全跳过网络请求。
   - 检查 `audio_core/download_sources.sh` 是否兼容无交互/纯 Android 最小源码拉取（避免拉取不必要的 Windows vcpkg 等）。
4. **Fastlane 元数据与配方模板**
   - 创建 `fastlane/metadata/android/en-US/` 与 `zh-CN/`（`title.txt`、`short_description.txt`、`full_description.txt`、图标、截图与 changelog）。
   - 创建 `packaging/fdroid/app.vynody.player.yml` 模板，声明 `flutter`、`ndk`、`rust`、`prebuild`、`build` 与 `scanignore`（如需要）等字段。
5. **验证**
   - 本地测试 `scripts/fdroid_prebuild.sh` + 断网 `flutter build apk --release`。
   - 检查 `unzip -l` APK `.so` 列表及 `./gradlew :app:dependencies --configuration releaseRuntimeClasspath`。
