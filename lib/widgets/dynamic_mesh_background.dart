import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_flow/mesh_flow.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/player/settings/theme_color_helper.dart';
import 'package:vynody/utils/app_log.dart';
import 'package:vynody/utils/artwork_signature.dart';

/// 播放页「动态流变」背景族。
///
/// 两套实现共存，由 `playbackBackgroundType` 选择：
/// - [DynamicMeshBackground]（设置项「动态流变」）：基于 `mesh_gradient`
///   的 4 色点流体渐变，纯调色盘驱动，不读取封面。
/// - [MeshFlowBackground]（设置项「动态流变 v2」）：基于 `mesh_flow` 的
///   28×28 钉边驻波网格 + 封面微型贴图，支持 GPU 端换曲过渡。
///
/// 两者共用 [_PlaybackMeshPaletteMixin] 的调色盘解析与主色重算调度，
/// 避免同一套主题色逻辑写两遍。

/// 动态流变背景族的共享调色盘逻辑。
///
/// 只做一件事：把当前曲目的主题色解析成稳定的 4 色目标盘，并在调色盘
/// 明显失效时补一次主色重算。稳定化是必需的——主题色会随播放异步刷新，
/// 直接把 `resolveMeshColors` 的结果喂给动画组件会让它反复重启过渡。
mixin _PlaybackMeshPaletteMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  List<Color>? _stableTargetColors;
  String? _lastPaletteRecalcAttemptPath;

  bool _isPaletteEqual(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].toARGB32() != b[i].toARGB32()) return false;
    }
    return true;
  }

  /// 解析当前曲目的稳定调色盘，并顺带返回当前曲目。
  ({List<Color> palette, MusicFile? music}) resolvePlaybackMeshPalette() {
    final themeColors = ref.watch(audioCurrentThemeColorsMapProvider);
    final dynamicStartColor = ref.watch(audioDynamicStartColorProvider);
    final dynamicEndColor = ref.watch(audioDynamicEndColorProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);

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

    if (_stableTargetColors == null ||
        !_isPaletteEqual(_stableTargetColors!, resolvedTarget)) {
      _stableTargetColors = resolvedTarget;
    }

    return (palette: _stableTargetColors!, music: currentMusic);
  }
}

/// 补齐 / 裁剪成 4 色——`mesh_gradient` 的着色器要求恰好 4 个颜色。
List<Color> _fitPaletteToFour(List<Color> colors) {
  if (colors.length == 4) return colors;
  if (colors.isEmpty) {
    return const [Colors.black, Colors.black, Colors.black, Colors.black];
  }
  return List<Color>.generate(4, (i) => colors[i % colors.length]);
}

/// 播放页「动态流变」背景（`mesh_gradient` 实现）。
///
/// 由 4 个角点的流体扰动生成动态渐变，颜色全部来自封面主题色，
/// 不依赖封面图像本身。
class DynamicMeshBackground extends ConsumerStatefulWidget {
  const DynamicMeshBackground({super.key});

  @override
  ConsumerState<DynamicMeshBackground> createState() =>
      _DynamicMeshBackgroundState();
}

class _DynamicMeshBackgroundState extends ConsumerState<DynamicMeshBackground>
    with WidgetsBindingObserver, _PlaybackMeshPaletteMixin {
  /// `mesh_gradient` 的 ticker 是裸 [Ticker]，不受 `TickerMode` 管，
  /// 只能通过 controller 在退到后台时停表。
  final AnimatedMeshGradientController _controller =
      AnimatedMeshGradientController();

  bool _isFlowActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isFlowActive = _readForegroundState();
    if (_isFlowActive) _controller.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool isActive = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    AppLog.log(
      '[IdleProbe] mesh_gradient lifecycle -> $state isActive=$isActive '
      'wasActive=$_isFlowActive',
      mirrorToConsole: true,
    );
    if (isActive == _isFlowActive) return;
    _isFlowActive = isActive;
    if (isActive) {
      _controller.start();
      AppLog.log('[IdleProbe] mesh_gradient controller start', mirrorToConsole: true);
    } else {
      _controller.stop();
      AppLog.log('[IdleProbe] mesh_gradient controller stop', mirrorToConsole: true);
    }
    setState(() {});
  }

  /// `inactive` 在桌面端只是失焦，仍然算前台；只有真正被挂起才停止。
  bool _readForegroundState() {
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> colors =
        _fitPaletteToFour(resolvePlaybackMeshPalette().palette);
    final meshSpeed = ref.watch(
      settingsServiceProvider.select(
        (settings) => settings.playbackMeshGradientSpeed,
      ),
    );
    // 着色器侧对 totalSpeed 有 0.01~15 的断言，先夹住脏值再传。
    final double totalSpeed = meshSpeed.clamp(0.01, 15.0);

    return SizedBox.expand(
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: TweenAnimationBuilder<List<Color>>(
            tween: _ListColorTween(end: colors),
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeInOut,
            builder: (context, animatedColors, child) {
              return AnimatedMeshGradient(
                key: const ValueKey('playback_mesh_gradient'),
                // 过渡中间帧也必须是 4 色，否则着色器断言会炸。
                colors: _fitPaletteToFour(animatedColors),
                options: AnimatedMeshGradientOptions(totalSpeed: totalSpeed),
                controller: _controller,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 播放页「动态流变 v2」背景（`mesh_flow` 实现）。
///
/// 28×28 钉边驻波网格 + 封面微型贴图：
/// - 纹理来源优先取当前曲目的封面字节，其次本地封面文件，最后回落到
///   由封面主题色合成的渐变贴图（远程曲目、无封面场景）。
/// - 换曲时由 [MeshFlow] 在 GPU 端做双纹理 + 网格地形的平滑过渡。
/// - 流动速度沿用「流速」设置项（[SettingsService.playbackMeshBackgroundSpeed]）。
class MeshFlowBackground extends ConsumerStatefulWidget {
  const MeshFlowBackground({super.key});

  @override
  ConsumerState<MeshFlowBackground> createState() => _MeshFlowBackgroundState();
}

class _MeshFlowBackgroundState extends ConsumerState<MeshFlowBackground>
    with WidgetsBindingObserver, _PlaybackMeshPaletteMixin {
  /// 纹理来源曲目路径。只在换曲时重新解析，保证 [MeshFlow] 侧收到的
  /// `coverBytes` / `image` 身份稳定，否则每次 build 都会重启过渡动画。
  String? _coverSourcePath;
  Uint8List? _coverBytes;
  ImageProvider? _coverImage;

  /// 当前已生效封面内容的签名（见 [artworkBytesSignature] / [artworkFileSignature]）。
  ///
  /// 只按 `path` 判断是不够的：标签补全 / 手动改标签会把**同一首歌**的封面换成
  /// 另一张，path 不变而内容变了。少了这一层判定，网格纹理（以及 [MeshFlow]
  /// 的 `coverKey`）会一直停在旧封面上，而同页的轮播封面早已换新。
  String? _coverSignature;

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
    AppLog.log(
      '[IdleProbe] mesh_flow lifecycle -> $state isActive=$isActive '
      'wasActive=$_isFlowActive',
      mirrorToConsole: true,
    );
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

  /// 解析当前曲目的封面纹理来源（内存字节优先，其次本地封面文件）。
  ///
  /// 每帧 build 都会调用，但只有「内容签名变了」才会换纹理——签名相同就直接
  /// 返回，避免每次 rebuild 都重启 [MeshFlow] 的过渡动画。内存字节优先，
  /// 其次是 `AudioService` 的封面缓存（远程曲目 / 尚未水合的场景），最后才是
  /// 封面文件。
  void _syncCoverSource(MusicFile? music) {
    final String? path = music?.path;
    if (path != _coverSourcePath) {
      _coverSourcePath = path;
      _coverBytes = null;
      _coverImage = null;
      _coverSignature = null;
    }
    if (path == null || path.isEmpty) return;

    final Uint8List? bytes = _resolveCoverBytes(music, path);
    final String? rawArtworkPath = music?.artworkPath;
    final String? artworkPath = (rawArtworkPath != null && rawArtworkPath.isNotEmpty)
        ? ScannerPathUtils.resolveIosSandboxPath(rawArtworkPath)
        : null;

    final String? signature = artworkSignatureOf(
      bytes: bytes,
      filePath: artworkPath,
    );
    if (signature == _coverSignature) return;

    if (signature == null) {
      // 既没有字节也没有文件：封面被清除了。必须丢掉上一张纹理，
      // 否则背景会继续贴着已经被删掉的那张封面，直到下次换曲。
      _coverSignature = null;
      _coverBytes = null;
      _coverImage = null;
      return;
    }

    _coverSignature = signature;
    if (bytes != null && bytes.isNotEmpty) {
      _coverBytes = bytes;
      _coverImage = null;
    } else {
      _coverBytes = null;
      _coverImage = FileImage(File(artworkPath!));
    }
  }

  Uint8List? _resolveCoverBytes(MusicFile? music, String path) {
    final Uint8List? direct = music?.artworkBytes;
    if (direct != null && direct.isNotEmpty) return direct;

    final audio = ref.read(audioServiceProvider);
    final Uint8List? cached = audio.getCachedArtwork(path);
    if (cached != null && cached.isNotEmpty) return cached;

    final String resolvedPath = ScannerPathUtils.resolveIosSandboxPath(path);
    if (resolvedPath != path) {
      final Uint8List? resolvedCached = audio.getCachedArtwork(resolvedPath);
      if (resolvedCached != null && resolvedCached.isNotEmpty) {
        return resolvedCached;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = resolvePlaybackMeshPalette();
    final List<Color> palette = resolved.palette;
    final currentMusic = resolved.music;

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

    _syncCoverSource(currentMusic);

    final bool hasCoverTexture = _coverBytes != null || _coverImage != null;
    final List<Color> fallbackPalette =
        palette.isNotEmpty ? palette : const [Colors.black, Colors.black];

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
            // 带上内容签名：同一首歌换封面时 [FileImage] 的 `==` 仍相等
            // （路径 + scale），只靠 `coverKey` 里的路径判等会让 MeshFlow
            // 认为封面没变、纹理停在旧图上。
            coverKey: '${_coverSourcePath}_${_coverSignature ?? 'none'}',
            coverBytes: _coverBytes,
            image: _coverImage,
            // 有真实封面时不再传调色盘：主题色会随播放异步刷新，
            // 传进去会让 MeshFlow 判定「封面变了」而反复重启过渡。
            palette: hasCoverTexture ? null : palette,
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

/// 在两个调色盘之间逐色插值，长度不等时循环补齐。
class _ListColorTween extends Tween<List<Color>> {
  _ListColorTween({super.end});

  @override
  List<Color> lerp(double t) {
    if (begin == null || end == null) return end ?? [];
    final int length = max(begin!.length, end!.length);
    return List<Color>.generate(length, (i) {
      final Color start = i < begin!.length
          ? begin![i]
          : (end!.isNotEmpty ? end![i % end!.length] : Colors.transparent);
      final Color target = i < end!.length
          ? end![i]
          : (begin!.isNotEmpty
                ? begin![i % begin!.length]
                : Colors.transparent);
      return Color.lerp(start, target, t) ?? target;
    });
  }
}
