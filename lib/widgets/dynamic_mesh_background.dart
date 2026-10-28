import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_flow/mesh_flow.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/player/settings/theme_color_helper.dart';

/// 播放页动态流变背景。
///
/// 取代原先基于 `mesh_gradient` 的 4 色点流体实现，改用 [MeshFlow] 的
/// 28×28 钉边驻波网格 + 封面微型贴图：
/// - 纹理来源优先取当前曲目的封面字节，其次本地封面文件，最后回落到
///   由封面主题色合成的渐变贴图（远程曲目、无封面场景）。
/// - 换曲时由 [MeshFlow] 在 GPU 端做双纹理 + 网格地形的平滑过渡。
/// - 流动速度沿用「流体 Mesh 背景速度」设置项，语义与旧实现保持一致。
class DynamicMeshBackground extends ConsumerStatefulWidget {
  const DynamicMeshBackground({super.key});

  @override
  ConsumerState<DynamicMeshBackground> createState() =>
      _DynamicMeshBackgroundState();
}

class _DynamicMeshBackgroundState extends ConsumerState<DynamicMeshBackground>
    with WidgetsBindingObserver {
  List<Color>? _stableTargetColors;
  String? _lastPaletteRecalcAttemptPath;

  /// 纹理来源曲目路径。只在换曲时重新解析，保证 [MeshFlow] 侧收到的
  /// `coverBytes` / `image` 身份稳定，否则每次 build 都会重启过渡动画。
  String? _coverSourcePath;
  Uint8List? _coverBytes;
  ImageProvider? _coverImage;

  /// 应用是否处于前台。退到后台 / 最小化时停掉网格形变，避免空转耗电。
  bool _isFlowActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isFlowActive = _readForegroundState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool isActive = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (isActive != _isFlowActive) {
      setState(() => _isFlowActive = isActive);
    }
  }

  /// `inactive` 在桌面端只是失焦，仍然算前台；只有真正被挂起才停止。
  bool _readForegroundState() {
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  bool _isListEqual(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].toARGB32() != b[i].toARGB32()) return false;
    }
    return true;
  }

  /// 解析当前曲目的封面纹理来源（内存字节优先，其次本地封面文件）。
  ///
  /// 只在尚无纹理时尝试，成功解析一次后即固定，避免重复解码与过渡重启。
  void _syncCoverSource(MusicFile? music) {
    final String? path = music?.path;
    if (path != _coverSourcePath) {
      _coverSourcePath = path;
      _coverBytes = null;
      _coverImage = null;
    }

    if (_coverBytes != null || _coverImage != null) return;
    if (path == null || path.isEmpty) return;

    final Uint8List? direct = music?.artworkBytes;
    if (direct != null && direct.isNotEmpty) {
      _coverBytes = direct;
      return;
    }

    final audio = ref.read(audioServiceProvider);
    final Uint8List? cached = audio.getCachedArtwork(path);
    if (cached != null && cached.isNotEmpty) {
      _coverBytes = cached;
      return;
    }

    final String resolvedPath = ScannerPathUtils.resolveIosSandboxPath(path);
    if (resolvedPath != path) {
      final Uint8List? resolvedCached = audio.getCachedArtwork(resolvedPath);
      if (resolvedCached != null && resolvedCached.isNotEmpty) {
        _coverBytes = resolvedCached;
        return;
      }
    }

    final String? rawArtworkPath = music?.artworkPath;
    if (rawArtworkPath != null && rawArtworkPath.isNotEmpty) {
      final File artworkFile = File(
        ScannerPathUtils.resolveIosSandboxPath(rawArtworkPath),
      );
      if (artworkFile.existsSync()) {
        _coverImage = FileImage(artworkFile);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ref.watch(audioCurrentThemeColorsMapProvider);
    final dynamicStartColor = ref.watch(audioDynamicStartColorProvider);
    final dynamicEndColor = ref.watch(audioDynamicEndColorProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final meshSpeed = ref.watch(
      settingsServiceProvider.select(
        (settings) => settings.playbackMeshBackgroundSpeed,
      ),
    );
    final edgeStyleIndex = ref.watch(
      settingsServiceProvider.select(
        (settings) => settings.playbackMeshBackgroundEdgeStyle,
      ),
    );
    final edgeStyle = switch (edgeStyleIndex) {
      1 => MeshFlowEdgeStyle.soft,
      2 => MeshFlowEdgeStyle.sharp,
      _ => MeshFlowEdgeStyle.random,
    };

    final List<Color> resolvedTarget = ThemeColorHelper.resolveMeshColors(
      themeColors,
      dynamicStartColor: dynamicStartColor,
      dynamicEndColor: dynamicEndColor,
    );

    final currentPath = currentMusic?.path;
    if (currentPath != null &&
        currentPath.isNotEmpty &&
        _lastPaletteRecalcAttemptPath != currentPath &&
        ThemeColorHelper.shouldRebuildPalette(resolvedTarget)) {
      _lastPaletteRecalcAttemptPath = currentPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          ref
              .read(audioServiceProvider)
              .recomputeThemeColorsWithMaster(songPath: currentPath),
        );
      });
    }

    // 稳定目标色，避免主题色反复重算时无谓地重建纹理。
    if (_stableTargetColors == null ||
        !_isListEqual(_stableTargetColors!, resolvedTarget)) {
      _stableTargetColors = resolvedTarget;
    }

    _syncCoverSource(currentMusic);

    final bool hasCoverTexture = _coverBytes != null || _coverImage != null;
    final List<Color> fallbackPalette =
        _stableTargetColors != null && _stableTargetColors!.length > 1
            ? _stableTargetColors!
            : const [Colors.black, Colors.black];

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 纹理（封面解码 / 调色盘合成）是异步的，就绪前先用同色渐变兜底，
          // 避免切换背景类型时闪一帧纯黑。
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: fallbackPalette,
                ),
              ),
            ),
          ),
          MeshFlow(
            key: const ValueKey('playback_mesh_flow'),
            coverKey: _coverSourcePath,
            coverBytes: _coverBytes,
            image: _coverImage,
            // 有真实封面时不再传调色盘：主题色会随播放异步刷新，
            // 传进去会让 MeshFlow 判定「封面变了」而反复重启过渡。
            palette: hasCoverTexture ? null : _stableTargetColors,
            edgeStyle: edgeStyle,
            speed: meshSpeed,
            // 播放页本身已有径向渐变 / 歌词遮罩两层叠加，这里不再叠暗角。
            vignetteAlpha: 0,
            // 透明底让上面的兜底渐变透出来。
            fallbackColor: Colors.transparent,
            animating: _isFlowActive,
          ),
        ],
      ),
    );
  }
}
