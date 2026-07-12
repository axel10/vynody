# Vynody

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Rust](https://img.shields.io/badge/Rust-Core-000000?logo=rust&logoColor=white)](https://www.rust-lang.org)
[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)

Vynody 是一款以本地音乐播放为核心的跨平台播放器，使用 Flutter 构建界面，并根据不同平台接入对应的原生音频内核，兼顾统一体验与底层能力。

项目当前面向以下平台：

- Windows
- Linux
- macOS
- iOS
- Android

## 特性概览

- 跨平台本地音乐播放器，覆盖桌面端与移动端
- 多平台原生播放内核接入，按平台选择更合适的实现
- 本地媒体库扫描、增量更新与歌曲管理
- 歌曲标签在线补全，支持通过音频指纹补全元数据
- 在线歌词获取，支持从 LRCLIB 拉取歌词
- 听歌识曲能力，基于音频指纹进行歌曲识别
- 本地局域网歌词与音乐文件共享
- 睡眠定时器
- 歌词相关增强能力，包括在线搜索、缓存与时间轴处理
- 频谱、波形、封面取色等播放界面增强体验

## 平台播放内核

Vynody 并不是所有平台都共用同一套播放器内核，而是按平台采用不同实现：

| 平台 | 播放内核 |
| :--- | :--- |
| Windows | Rust 音频内核 |
| Linux | Rust 音频内核 |
| Android | ExoPlayer |
| macOS | SFBAudioEngine |
| iOS | SFBAudioEngine |

这种设计的目标是：在保证跨平台 UI 一致性的同时，尽量利用各平台成熟的底层音频能力。

## 核心能力

### 1. 本地播放与媒体库

- 扫描本地文件夹并建立媒体库
- 支持文件变更后的增量更新
- 提供专辑、艺术家、歌曲等常见浏览方式
- 面向本地播放器场景，强调稳定播放与日常管理效率

### 2. 歌曲标签在线补全

针对标签不完整或信息缺失的音频文件，Vynody 支持在线补全歌曲元数据。

- 使用音频指纹识别歌曲
- 结合 AcoustID 与 MusicBrainz 匹配结果
- 补全标题、艺术家、专辑等标签信息
- 支持封面等元数据的补充

这部分能力尤其适合整理来源较杂、标签质量不一致的本地曲库。

### 3. 在线歌词获取

项目内置在线歌词搜索与获取能力，当前可接入：

- LRCLIB

可用于：

- 搜索匹配当前歌曲的在线歌词
- 获取纯文本歌词或带时间轴歌词
- 将歌词与本地歌曲关联并缓存
- 对已有歌词做进一步整理和时间轴处理

### 4. 听歌识曲

Vynody 支持基于音频指纹的歌曲识别能力，可用于：

- 识别本地音频文件对应的歌曲
- 为歌曲标签补全提供候选结果
- 辅助整理未知来源或缺失元数据的文件

### 5. 睡眠定时器

内置睡眠定时器，适合夜间听歌或临睡前使用。

- 支持设置播放停止倒计时
- 支持查看剩余时间
- 支持手动取消

### 6. 局域网歌词与音乐文件共享

Vynody 内置局域网共享能力，可在同一网络下与其他设备交换音乐文件和歌词数据。

- 自动发现局域网内运行中的 Vynody 设备
- 支持发送单个音乐文件
- 支持发送整个音乐文件夹，并保留相对目录结构
- 支持设备之间双向同步歌词缓存与翻译缓存
- 支持通过浏览器访问本机共享页面，进行上传或下载

这项能力适合在多台设备之间迁移曲库，或者把一台设备上整理好的歌词同步到另一台设备。

## 技术架构

项目整体采用“Flutter UI + 平台原生音频实现”的思路：

- Flutter：负责跨平台界面与交互
- Rust：承担 Windows / Linux 平台的核心音频能力，以及部分底层处理
- ExoPlayer：承担 Android 平台播放能力
- SFBAudioEngine：承担 Apple 平台播放能力
- SQLite / Drift：用于本地媒体库与缓存管理

在线相关能力主要包括：

- LRCLIB：在线歌词获取
- AcoustID：音频指纹识别
- MusicBrainz：标签与元数据补全

局域网共享相关能力主要包括：

- UDP 广播发现局域网设备
- 内置 HTTP 共享服务
- 浏览器网页传输入口
- 歌词缓存导入、导出与冲突处理


## 开发与运行

### 基本依赖

- Flutter SDK
- Rust toolchain
- 对应平台的原生构建环境

不同平台还需要各自的系统依赖，例如：

- Android：Android Studio / SDK / NDK（按项目实际配置）
- iOS / macOS：Xcode 与 Apple 平台构建环境
- Windows：Visual Studio C++ 构建工具
- Linux：Flutter Desktop 与系统开发依赖

### 拉取项目

```bash
git clone https://github.com/axel10/vynody
cd vynody
```

### 运行

```bash
flutter pub get
flutter run -d <device-id>
```

如果你是在桌面平台首次构建，通常还需要先确认 Flutter Desktop 与 Rust 工具链都已经可用。

## 可配置能力

项目中已经包含或预留了多项可配置能力，常见包括：

- 播放相关设置
- 歌词来源与歌词处理相关设置
- AcoustID API Key
- 外观、主题、可视化效果
- 快捷键与交互行为

如果你准备长期使用歌曲标签补全和音频指纹识别，建议配置自己的 AcoustID API Key。

## 贡献

欢迎提交 issue 或 pull request。

如果你要参与开发，建议至少先完成以下检查：

```bash
flutter test
```

并尽量保持代码风格与现有工程结构一致。

## License

本项目基于 [GPL-3.0](LICENSE) 开源。
