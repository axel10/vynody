# Vynody

<p align="center">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/logo_with_text.jpg" alt="Vynody Logo" width="600">
</p>

<p align="center">
  <b>English</b> | <a href="README_zh.md">简体中文</a>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/id6799339894"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" height="42" alt="Download on the App Store"></a>
  &nbsp;&nbsp;
  <a href="https://apps.microsoft.com/detail/9nmzrzz6rsd3"><img src="https://get.microsoft.com/images/en-us%20dark.svg" height="42" alt="Get it from Microsoft"></a>
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter"></a>
  <a href="https://www.rust-lang.org"><img src="https://img.shields.io/badge/Rust-Core-000000?logo=rust&logoColor=white" alt="Rust"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL%20v3-blue.svg" alt="License: GPL v3"></a>
</p>

---

Vynody is a visually refined, feature-rich, and lightweight cross-platform local music player. Built with Flutter for a sleek modern UI and integrated with platform-specific native audio backends, it delivers a unified experience while unlocking low-level hardware audio capabilities across all platforms.

## Why Vynody?

I am both a music enthusiast and a software developer. For a long time, the local music player ecosystem across different platforms has been severely fragmented—either plagued by dated UIs, bloated resource usage, or jarring inconsistencies across devices. To craft a clean, pure, and cohesive listening experience, I decided to build this application.

Vynody is developed using a modern **Vibe Coding** (AI-assisted development) workflow. After months of intensive iterations and real-device testing, Vynody offers solid stability, maturity, and performance for daily use.

Beyond fast media library indexing, lightweight system footprints, and smooth local playback, Vynody brings **unique and advanced features** rarely found in traditional players:
- **Karaoke-style word-by-word synced lyrics and AI timeline generation**
- **Serverless cross-device LAN syncing for music tracks and lyrics**
- **Customizable themes and progress bar visual styles**
- **Deep native platform optimization** across Windows, macOS, Linux, iOS, and Android.

## Downloads

<p align="center">
  <a href="https://apps.apple.com/app/id6799339894"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" height="42" alt="Download on the App Store"></a>
  &nbsp;&nbsp;
  <a href="https://apps.microsoft.com/detail/9nmzrzz6rsd3"><img src="https://get.microsoft.com/images/en-us%20dark.svg" height="42" alt="Get it from Microsoft"></a>
</p>

| Platform | Channel | Link |
| :--- | :--- | :--- |
| **iOS / macOS** | Apple App Store | [Download on App Store](https://apps.apple.com/app/id6799339894) |
| **Windows** | Microsoft Store | [Get from Microsoft Store](https://apps.microsoft.com/detail/9nmzrzz6rsd3) |
| **All Platforms** | GitHub Releases | [GitHub Releases](https://github.com/axel10/vynody/releases) |

## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/general_playback_pc.jpg" alt="Playback">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/general_lyric_pc.jpg" alt="Lyrics">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/en/folder_pc.jpg" alt="Folder">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/en/album_pc.jpg" alt="Album">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/en/navidrome_pc.jpg" alt="Navidrome">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/en/share_pc.jpg" alt="LAN Share">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/general_playback_mobile.jpg" width="32%" alt="Playback (Mobile)">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/general_lyric_mobile.jpg" width="32%" alt="Lyrics (Mobile)">
  <img src="https://raw.githubusercontent.com/axel10/vynody/refs/heads/main/assets/readme/en/folder_mobile.jpg" width="32%" alt="Folder (Mobile)">
</p>

## Features Overview

- **Full Cross-Platform Support**: Desktop (Windows / macOS / Linux) and mobile (iOS / Android).
- **Platform-Specific Native Audio Backends**: Tailored audio engines chosen for optimal performance on each OS.
- **Windows WASAPI Exclusive Mode**: Direct, bit-perfect audio stream output.
- **Local Media Library**: Fast scanning, incremental indexing, and comprehensive library organization.
- **Audio Fingerprinting & Tag Completion**: Matches AcoustID and MusicBrainz to complete missing metadata and album artwork.
- **Enhanced Lyric Capabilities**:
  - LRCLIB integration for instant lyric search and matching
  - AI-assisted timeline generation (including word-by-word / Karaoke sync)
  - Multilingual AI translation with bilingual displays
- **Song Recognition**: Acoustic fingerprinting to identify unknown audio files.
- **LAN Sharing & Sync**: Serverless file transfer and bidirectional lyric/translation sync across local devices.
- **Sleep Timer**: Built-in countdown timer for automatic playback shutoff.
- **Remote Music Libraries (Navidrome, Jellyfin, WebDAV, SMB)**:
  - Stream directly from self-hosted Navidrome / Jellyfin instances
  - Mount WebDAV / SMB remote storage with chunked metadata parsing to instantly display song tags without downloading complete audio files
- **Immersive Visuals**: Dynamic audio spectrum, waveforms, dynamic background palette extraction, and customizable progress bar styles.
- **Desktop Enhancements**: Playback queue drawer, floating quick-access panels, and global keyboard shortcuts.

## Architecture & Audio Engines

Vynody uses **Flutter** across all platforms for UI presentation and system interaction, paired with platform-tailored native audio backends:

| Platform | Audio Engine | Implementation |
| :--- | :--- | :--- |
| **Windows** | Audio Core (Rust) | Rodio backend integrated with FFmpeg decoding; supports WASAPI Exclusive mode |
| **Linux** | Audio Core (Rust) | Rodio backend integrated with FFmpeg decoding |
| **macOS** | Audio Core (Rust) | Rodio backend, **AVFoundation decoding prioritized with FFmpeg fallback** |
| **iOS** | Audio Core (Rust) | Rodio backend, **AVFoundation decoding prioritized with FFmpeg fallback** |
| **Android** | ExoPlayer (Media3) | Leverages Android Audio Offload for hardware-level low power consumption |

**Core Tech Stack & Integrations:**
- **UI & Architecture**: Flutter 3.x + Riverpod state management
- **Database**: SQLite + Drift for high-speed local indexing and caching
- **Remote Services & Protocols**: LRCLIB (lyrics), Navidrome / Jellyfin (streaming), WebDAV / SMB (remote storage & on-demand metadata parsing)
- **Audio Intelligence**: AcoustID (fingerprints), MusicBrainz (metadata), configurable AI models (lyrics & translation)
- **Networking**: UDP broadcast discovery + embedded HTTP sharing server

## Core Capabilities

### 1. Local Playback & Media Library
- Fast directory scanning and instant incremental updates on library changes.
- Flexible browsing by albums, artists, tracks, and directory structures.
- Ultra-low RAM and CPU usage, ideal for persistent background playback.

### 2. Metadata & Tag Completion
- Identifies audio files using acoustic fingerprints.
- Matches against AcoustID and MusicBrainz databases.
- Auto-populates missing track titles, artists, album names, and high-res cover art.

### 3. Lyrics Search, AI Generation & Translation
- Connects to LRCLIB for synced lyrics.
- Generates precise timestamps and word-by-word synced lyrics via AI.
- Translates lyrics to your target language with bilingual viewing.

### 4. Song Recognition
- Extracts acoustic fingerprints from local clips to identify unknown tracks.

### 5. Local Network (LAN) Sharing
- Auto-discovery of Vynody instances on the same subnet.
- Fast transfer of individual tracks or complete album folder trees.
- Syncs local lyric caches, timelines, and translation databases across devices.
- Built-in browser web interface for uploading/downloading tracks from any web browser.

### 6. Remote Music Libraries (Navidrome, Jellyfin, WebDAV, SMB)
- **Media Streaming (Navidrome & Jellyfin)**: Seamless connection to personal streaming servers for browsing playlists, albums, and remote streaming.
- **Remote Storage (WebDAV & SMB)**: Mount remote network shares with on-demand header parsing via chunked requests to extract ID3/metadata tags directly without downloading whole audio files.

## Development & Setup

### Prerequisites
- Flutter SDK (3.x)
- Rust toolchain (with `cargo`)
- Native build toolchain for your target OS (Xcode / Visual Studio / Android SDK & NDK)

### Cloning
```bash
git clone --recurse-submodules https://github.com/axel10/vynody
cd vynody
```
> 💡 *If you cloned without `--recurse-submodules`, run `git submodule update --init` before building.*

### Running
```bash
flutter pub get
flutter run -d <device-id>
```

## Contributing

Issues and Pull Requests are welcome! Before submitting code, please ensure tests pass:

```bash
flutter test
```

## License

Licensed under the [GPL-3.0 License](LICENSE).
