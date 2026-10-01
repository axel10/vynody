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

## 功能概览

- **跨平台全覆盖**：支持桌面端（Windows / macOS / Linux）与移动端（iOS / Android）。
- **多平台原生播放内核**：按平台选择更适合的底层实现。
- **Windows WASAPI 独占输出**：支持 WASAPI 独占模式，实现独占式音频输出。
- **本地媒体库管理**：本地文件夹扫描、增量更新与快速歌曲索引。
- **音频指纹与歌曲标签补全**：支持通过音频指纹匹配 AcoustID / MusicBrainz 补全元数据与封面。
- **全能歌词增强**：
  - LRCLIB 在线歌词搜索与自动匹配
  - AI 生成精准时间轴歌词（支持逐字/卡拉 OK 动效）
  - 歌词多语言智能翻译与双语对照
- **听歌识曲**：基于音频指纹精准识别未知音频文件。
- **本地局域网共享与同步**：免服务器在多设备间互传音乐文件、双向同步歌词、歌单（Playlist）与翻译缓存。
- **睡眠定时器**：支持倒计时自动停止播放。
- **远程音乐库（Navidrome、Jellyfin、WebDAV、SMB）**：
  - 支持连接自建 Navidrome / Jellyfin 服务器串流播放与媒体库浏览
  - 支持挂载 WebDAV 与 SMB 远程存储，并通过分段按需读取实现无需下载整曲即可直接解析展示元数据
- **沉浸式播放视觉**：动态频谱、波形图、封面实时取色背景与多种可选进度条样式。
- **桌面端专属交互**：播放队列抽屉、快捷悬浮弹窗与全局快捷键。

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

## 核心能力详解

### 1. 本地播放与媒体库
- 快速扫描本地文件夹并建立媒体库
- 支持文件变更后的极速增量更新
- 提供专辑、艺术家、文件夹等多种浏览与排序方式
- 极低的内存与 CPU 占用，适合全天候后台常驻

### 2. 歌曲标签在线补全
针对标签不完整或信息缺失的音频文件，Vynody 支持在线补全歌曲元数据：
- 使用音频指纹精准识别歌曲
- 结合 AcoustID 与 MusicBrainz 数据库匹配结果
- 一键补全标题、艺术家、专辑及高清封面等标签信息

### 3. 歌词搜索、AI 生成与翻译
内置在线歌词搜索与智能处理能力：
- 自动接入 LRCLIB 获取标准与时间轴歌词
- 支持利用配置的 AI 大模型，根据音频直接生成带时间轴歌词
- 为已有的纯文本歌词智能生成或校正逐行/逐字时间轴
- 支持将歌词翻译为指定目标语言并缓存结果

### 4. 听歌识曲
- 本地截取音频指纹识别未知曲目
- 为歌曲整理和标签补全提供候选建议

### 5. 局域网歌词、歌单与音乐文件共享
- 自动发现局域网内运行中的 Vynody 实例
- 支持发送单个音乐文件或整个音乐文件夹（保留相对目录结构）
- 支持设备之间双向同步歌词、歌单（Playlist）与翻译缓存
- 支持通过浏览器直接访问本机 Web 端进行文件上传与下载

### 6. 远程音乐库（Navidrome、Jellyfin、WebDAV、SMB）
- **流媒体服务接入（Navidrome & Jellyfin）**：连接个人 Navidrome / Jellyfin 音乐服务器，在线浏览歌单、专辑与串流播放
- **远程存储挂载（WebDAV & SMB）**：直接挂载 WebDAV / SMB 服务，通过 HTTP Range / 分段请求直接读取音频文件头部标签，无需将整首歌曲下载到本地即可快速展示标题、艺术家与专辑信息

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
