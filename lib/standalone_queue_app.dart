import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/utils/list_reorder_utils.dart';
import 'package:vynody/widgets/app_tooltip.dart';
import 'package:vynody/widgets/queue_file_drop_target.dart';

class StandaloneQueueApp extends StatefulWidget {
  final String windowId;
  final String arguments;

  const StandaloneQueueApp({
    super.key,
    required this.windowId,
    required this.arguments,
  });

  @override
  State<StandaloneQueueApp> createState() => _StandaloneQueueAppState();
}

class _StandaloneQueueAppState extends State<StandaloneQueueApp>
    with WidgetsBindingObserver {
  late final WindowController _controller;
  late final WindowMethodChannel _subChannel;
  late final WindowMethodChannel _mainChannel;

  List<MusicFile> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  final _keyPool = ReorderableKeyPool(debugPrefix: 'standalone-queue-tile');

  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = const Color(0xFF6750A4);

  final ScrollController _scrollController = ScrollController();

  bool get _isEffectiveDark {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  void _updateNativeTitleBar() {
    if (!Platform.isWindows) return;
    try {
      _controller.setDarkMode(_isEffectiveDark);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WindowController.fromWindowId(widget.windowId);
    _subChannel = WindowMethodChannel(
      'vynody/standalone_queue_sub_${widget.windowId}',
      mode: ChannelMode.unidirectional,
    );
    _mainChannel = const WindowMethodChannel(
      'vynody/standalone_queue_main',
      mode: ChannelMode.unidirectional,
    );

    _parseInitialArguments();
    _initIpc();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateNativeTitleBar();
    });
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (_themeMode == ThemeMode.system) {
      if (mounted) {
        setState(() {});
      }
      _updateNativeTitleBar();
    }
  }

  void _parseInitialArguments() {
    if (widget.arguments.isEmpty) return;
    try {
      final decoded = jsonDecode(widget.arguments);
      if (decoded is Map<String, dynamic>) {
        _applySyncData(decoded);
      } else if (decoded is Map) {
        _applySyncData(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      debugPrint('[StandaloneQueueApp] Error parsing initial arguments: $e');
    }
  }

  void _initIpc() {
    _subChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'sync_state':
          final map = call.arguments as Map?;
          if (map != null) {
            _onSyncStateReceived(Map<String, dynamic>.from(map));
          }
          return true;

        case 'sync_playback_state':
          final map = call.arguments as Map?;
          if (map != null && mounted) {
            setState(() {
              _isPlaying = map['isPlaying'] as bool? ?? false;
            });
          }
          return true;

        case 'close_window':
          _closeWindow();
          return true;

        default:
          return null;
      }
    });

    // Request initial sync from main window
    Future.microtask(() {
      _sendIpc('request_initial_sync');
    });
  }

  void _onSyncStateReceived(Map<String, dynamic> data) {
    if (!mounted) {
      _applySyncData(data);
      return;
    }

    setState(() {
      _applySyncData(data);
    });
  }

  void _applySyncData(Map<String, dynamic> data) {
    final rawQueue = data['queue'] as List? ?? [];
    final queue = rawQueue
        .map((item) => _musicFileFromJson(Map<String, dynamic>.from(item)))
        .toList();

    final currentIndex = data['currentIndex'] as int? ?? -1;
    final isPlaying = data['isPlaying'] as bool? ?? false;
    final themeModeIdx = data['themeMode'] as int?;
    final accentVal = data['accentColor'] as int?;

    _queue = queue;
    _currentIndex = currentIndex;
    _isPlaying = isPlaying;

    if (themeModeIdx != null) {
      if (themeModeIdx == 0) _themeMode = ThemeMode.system;
      if (themeModeIdx == 1) _themeMode = ThemeMode.light;
      if (themeModeIdx == 2) _themeMode = ThemeMode.dark;
    }
    if (accentVal != null) {
      _accentColor = Color(accentVal);
    }

    _updateNativeTitleBar();
  }

  MusicFile _musicFileFromJson(Map<String, dynamic> json) {
    return MusicFile(
      path: json['path'] as String,
      name: json['name'] as String? ?? '',
      title: json['title'] as String?,
      artist: json['artist'] as String?,
      albumArtist: json['albumArtist'] as String?,
      album: json['album'] as String?,
      trackNumber: json['trackNumber'] as int?,
      durationMillis: json['durationMillis'] as int?,
      thumbnailPath: json['thumbnailPath'] as String?,
      artworkPath: json['artworkPath'] as String?,
      mediaUri: json['mediaUri'] as String?,
      isMissing: json['isMissing'] as bool? ?? false,
    );
  }

  void _sendIpc(String method, [dynamic arguments]) {
    try {
      _mainChannel.invokeMethod(method, arguments);
    } catch (e) {
      debugPrint('[StandaloneQueueApp] Error sending IPC method $method: $e');
    }
  }

  void _playIndex(int index) {
    _sendIpc('play_index', index);
  }

  void _removeIndex(int index) {
    if (index >= 0 && index < _queue.length) {
      setState(() {
        _queue.removeAt(index);
        if (_currentIndex == index) {
          _currentIndex = -1;
        } else if (_currentIndex > index) {
          _currentIndex--;
        }
      });
    }
    _sendIpc('remove_index', index);
  }

  void _clearQueue() {
    _sendIpc('clear_queue');
  }

  void _reorderQueue(int oldIndex, int newIndex) {
    if (!ListReorderUtils.moveItem(_queue, oldIndex, newIndex)) return;

    _keyPool.moveKey(oldIndex, newIndex);
    setState(() {
      _currentIndex = ListReorderUtils.reorderIndex(
        _currentIndex,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
    });

    _sendIpc('reorder', {'oldIndex': oldIndex, 'newIndex': newIndex});
  }

  void _dockToMainWindow() async {
    _sendIpc('dock_to_main');
    try {
      await _controller.hide();
    } catch (_) {}
  }

  void _closeWindow() async {
    _sendIpc('window_closed');
    try {
      await _controller.hide();
    } catch (_) {}
  }

  void _scrollToCurrent() {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      if (_scrollController.hasClients) {
        final offset = (_currentIndex * 60.0) - 100;
        _scrollController.animateTo(
          offset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  String _formatDuration(int ms) {
    final dur = Duration(milliseconds: ms);
    final minutes = dur.inMinutes;
    final seconds = dur.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subChannel.setMethodCallHandler(null);
    _scrollController.dispose();
    _keyPool.clear();
    super.dispose();
  }

  ThemeData _buildTheme(Brightness brightness, Color primaryColor) {
    final isDark = brightness == Brightness.dark;
    final isPrimaryDark =
        ThemeData.estimateBrightnessForColor(primaryColor) == Brightness.dark;
    final onPrimary = isPrimaryDark ? Colors.white : Colors.black;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
    ).copyWith(
      primary: primaryColor,
      onPrimary: onPrimary,
      surface: isDark ? const Color(0xFF141218) : null,
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF141218) : null,
      useMaterial3: true,
      fontFamily: (!kIsWeb && Platform.isWindows) ? 'Segoe UI' : null,
      fontFamilyFallback: (!kIsWeb && (Platform.isMacOS || Platform.isIOS))
          ? const [
              'PingFang SC',
              'PingFang TC',
              'Heiti SC',
              'sans-serif',
            ]
          : const [
              'Microsoft YaHei UI',
              'Microsoft YaHei',
              'PingFang SC',
              'Heiti SC',
              'Noto Sans CJK SC',
              'Noto Sans SC',
              'Source Han Sans SC',
              'sans-serif',
            ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = _buildTheme(Brightness.light, _accentColor);
    final darkTheme = _buildTheme(Brightness.dark, _accentColor);

    _keyPool.syncLength(_queue.length);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '播放队列 - Vynody',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      home: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            body: QueueFileDropTarget(
              enabled: true,
              displayQueue: _queue,
              queueSongs: _queue,
              itemKeyBuilder: (index, song) => _keyPool.getKey(index),
              showPreview: _queue.isNotEmpty,
              indicatorHorizontalPadding: 12.0,
              onFilesDropped: (paths, insertIndex) async {
                _sendIpc('add_files', {
                  'paths': paths,
                  'insertIndex': insertIndex,
                  'playNow': false,
                });
              },
              child: Column(
                children: [
                  _buildTitleBar(context),
                  Expanded(
                    child: _queue.isEmpty
                        ? _buildEmptyView(context)
                        : _buildQueueList(context),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(
            Icons.queue_music_rounded,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '播放队列',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_queue.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: SizedBox(height: double.infinity),
          ),
          if (_queue.isNotEmpty) ...[
            AppTooltip(
              message: '定位到当前播放',
              child: IconButton(
                icon: const Icon(Icons.my_location_rounded, size: 18),
                onPressed: _scrollToCurrent,
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            AppTooltip(
              message: '清空队列',
              child: IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                onPressed: () {
                  _showClearConfirmDialog(context);
                },
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          AppTooltip(
            message: '吸附回主窗口',
            child: IconButton(
              icon: const Icon(Icons.vertical_align_bottom_rounded, size: 18),
              onPressed: _dockToMainWindow,
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          AppTooltip(
            message: '关闭独立窗口',
            child: IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: _closeWindow,
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  void _showClearConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空队列'),
        content: const Text('确定要清空当前的播放队列吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearQueue();
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.queue_music_rounded,
            size: 56,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 16),
          Text(
            '播放队列为空',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '从媒体库、目录页或外部将歌曲拖拽到此处',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList(BuildContext context) {
    final theme = Theme.of(context);

    return ReorderableListView.builder(
      scrollController: _scrollController,
      buildDefaultDragHandles: false,
      itemCount: _queue.length,
      onReorderItem: (oldIndex, newIndex) {
        _reorderQueue(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final song = _queue[index];
        final isCurrent = index == _currentIndex;

        return Material(
          key: _keyPool.getKey(index),
          color: isCurrent
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
              : Colors.transparent,
          child: InkWell(
            onTap: () => _playIndex(index),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Builder(
                    builder: (context) {
                      final hasThumb = song.thumbnailPath != null &&
                          song.thumbnailPath!.isNotEmpty &&
                          File(song.thumbnailPath!).existsSync();
                      final hasArt = song.artworkPath != null &&
                          song.artworkPath!.isNotEmpty &&
                          File(song.artworkPath!).existsSync();
                      final coverPath = hasThumb
                          ? song.thumbnailPath
                          : (hasArt ? song.artworkPath : null);

                      return Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          image: coverPath != null
                              ? DecorationImage(
                                  image: FileImage(File(coverPath)),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: coverPath == null
                            ? Icon(
                                Icons.music_note_rounded,
                                size: 20,
                                color: isCurrent
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              )
                            : null,
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isCurrent) ...[
                              Icon(
                                _isPlaying
                                    ? Icons.volume_up_rounded
                                    : Icons.pause_rounded,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                song.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isCurrent
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist ?? '未知歌手',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (song.durationMillis != null && song.durationMillis! > 0)
                    Text(
                      _formatDuration(song.durationMillis!),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    onPressed: () => _removeIndex(index),
                    visualDensity: VisualDensity.compact,
                    tooltip: '从队列中移除',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
