# Vynody

<p align="center">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/logo_with_text.jpg" alt="Vynody Logo" width="600">
</p>

<p align="center">
  <a href="README.md">English</a> | <b>简体中文</b>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/id6799339894"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" height="42" alt="在 App Store 下载"></a>
  &nbsp;&nbsp;
  <a href="https://apps.microsoft.com/detail/9nmzrzz6rsd3"><img src="https://get.microsoft.com/images/en-us%20dark.svg" height="42" alt="从 Microsoft Store 获取"></a>
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter"></a>
  <a href="https://www.rust-lang.org"><img src="https://img.shields.io/badge/Rust-Core-000000?logo=rust&logoColor=white" alt="Rust"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL%20v3-blue.svg" alt="License: GPL v3"></a>
</p>

---

Vynody 是一款界面美观、功能丰富且极低资源占用的跨平台本地音乐播放器。使用 Flutter 构建现代美观的交互界面，并根据不同操作系统接入量身定制的原生音频内核，兼顾全平台统一的高品质体验与底层硬件能力。

## 为什么制作 Vynody？

我是一名音乐爱好者，同时也是一名程序员。长期以来，不同平台上的本地音乐播放器体验严重碎片化——要么界面陈旧、要么资源占用臃肿、要么不同平台之间体验割裂。为了获得纯粹、精致的听歌体验，我决定自己动手开发这款 App。

本项目采用现代的 **Vibe Coding**（AI 辅助开发）工作流进行构建。经过数月的高强度迭代与实机实测，Vynody 现已具备出色的日常稳定性和成熟度。

除了高效的媒体库管理、秒级歌曲索引构建与极低的系统资源占用外，Vynody 还拥有许多传统本地播放器少有的**特色与进阶能力**：
- **逐字歌词（卡拉 OK 动效）与 AI 时间轴生成**
- **跨设备免服务器的歌词、歌单与音乐文件局域网同步**
- **丰富的主题与高度自定义的进度条样式**
- **全平台深度适配**：Windows、macOS、Linux、iOS 与 Android 均获得一致且贴合系统的体验。

## 下载与安装

<p align="center">
  <a href="https://apps.apple.com/app/id6799339894"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" height="42" alt="在 App Store 下载"></a>
  &nbsp;&nbsp;
  <a href="https://apps.microsoft.com/detail/9nmzrzz6rsd3"><img src="https://get.microsoft.com/images/en-us%20dark.svg" height="42" alt="从 Microsoft Store 获取"></a>
</p>

| 平台 | 获取渠道 | 链接 |
| :--- | :--- | :--- |
| **iOS / macOS** | Apple App Store | [前往 App Store 下载](https://apps.apple.com/app/id6799339894) |
| **Windows** | 微软应用商店 | [前往 Microsoft Store 获取](https://apps.microsoft.com/detail/9nmzrzz6rsd3) |
| **全部平台** | GitHub Releases | [GitHub Releases 下载页面](https://github.com/axel10/vynody/releases) |

## 截图

<p align="center">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/general_playback_pc.jpg" alt="播放界面">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/general_lyric_pc.jpg" alt="歌词界面">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/zh/folder_pc.jpg" alt="文件夹">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/zh/album_pc.jpg" alt="专辑">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/zh/navidrome_pc.jpg" alt="Navidrome">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/zh/share_pc.jpg" alt="局域网共享">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/general_playback_mobile.jpg" width="32%" alt="播放界面 (移动端)">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/general_lyric_mobile.jpg" width="32%" alt="歌词界面 (移动端)">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/zh/folder_mobile.jpg" width="32%" alt="文件夹 (移动端)">
</p>

## 功能特性

- **全平台覆盖与原生体验**：全面支持 Windows、macOS、Linux、iOS 与 Android，按系统深度接入最适宜的底层播放内核。
- **WASAPI 独占输出**：Windows 端支持 WASAPI 独占模式，实现纯净音频直通输出。
- **本地曲库与极速索引**：智能秒级扫描与文件增量更新，极低的内存与 CPU 占用，适合全天候后台常驻。
- **音频指纹与标签补全**：内置 AcoustID 与 MusicBrainz 数据库，支持一键识别未知曲目，自动补全歌曲元数据与高清封面。
- **全能歌词增强**：
  - **LRCLIB 在线获取**：自动搜索并匹配高精度歌词
  - **AI 智能赋能**：根据音频自动生成带时间轴歌词，支持**逐字（卡拉 OK）动效**与时间轴校正
  - **多语言翻译**：支持一键将歌词翻译为目标语言并本地缓存
- **免服务器局域网同步**：自动发现同局域网设备，秒级互传音乐文件、双向同步**歌单（Playlists）**、歌词与翻译缓存，并支持浏览器 Web 端跨端传输。
- **全格式远程媒体库**：
  - **流媒体服务接入**：连接个人 **Navidrome** 与 **Jellyfin** 服务器进行在线浏览与串流播放
  - **远程存储挂载**：挂载 **WebDAV** 与 **SMB** 存储，利用 HTTP Range / 分段请求实现无需下载整曲即可直接解析展示元数据
- **沉浸式视觉与桌面交互**：动态音频频谱、波形图、封面实时取色背景、多种可选进度条样式，以及桌面端播放队列抽屉与全局快捷键。
- **睡眠定时器**：睡前设置倒计时自动停止播放。

## 技术架构与播放内核

Vynody 在全平台统一使用 **Flutter** 作为前端 UI 和系统交互引擎。在底层音频引擎上，针对各系统特性进行了深度定制：

| 平台 | 播放内核 | 技术实现 |
| :--- | :--- | :--- |
| **Windows** | Audio Core (Rust) | 基于 Rodio 对接 FFmpeg 解码，支持 WASAPI 独占模式 |
| **Linux** | Audio Core (Rust) | 基于 Rodio 对接 FFmpeg 解码 |
| **macOS** | Audio Core (Rust) | 基于 Rodio，**AVFoundation 解码优先，FFmpeg 解码兜底** |
| **iOS** | Audio Core (Rust) | 基于 Rodio，**AVFoundation 解码优先，FFmpeg 解码兜底** |
| **Android** | ExoPlayer (Media3) | 接入 Android 系统音频硬件卸载（Audio Offload），实现超低功耗 |

**核心技术栈与服务：**
- **UI & 架构**：Flutter 3.x + Riverpod 状态管理
- **本地数据库**：SQLite + Drift（毫秒级本地曲库与缓存检索）
- **远程与网络库**：LRCLIB（歌词）、Navidrome / Jellyfin（媒体服务串流）、WebDAV / SMB（轻量元数据按需解析与串流）
- **音频智能**：AcoustID（音频指纹）、MusicBrainz（标签补全）、可配置 AI 服务商（歌词与翻译）
- **局域网互联**：UDP 广播发现 + 内置 HTTP 共享传输服务

## 开发与运行

### 基本依赖
- Flutter SDK (3.x)
- Rust toolchain (包含 cargo)
- 对应平台的原生构建工具（Xcode / Visual Studio / Android SDK & NDK）

### 拉取项目
```bash
git clone --recurse-submodules https://github.com/axel10/vynody
cd vynody
```
> 💡 *如果您之前克隆仓库时未使用 `--recurse-submodules`，请先运行 `git submodule update --init` 以初始化 `audio_core` 模块。*

### 运行
```bash
flutter pub get
flutter run -d <device-id>
```

## 贡献

欢迎提交 Issue 或 Pull Request。参与开发前建议运行单元测试保证代码质量：

```bash
flutter test
```

## License

本项目基于 [GPL-3.0](LICENSE) 协议开源。
