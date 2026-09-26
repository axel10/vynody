import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/settings/shortcut_bindings.dart';
import 'package:vynody/utils/list_reorder_utils.dart';
import 'package:vynody/utils/selection_utils.dart';
import 'package:vynody/widgets/app_tooltip.dart';
import 'package:vynody/widgets/queue_file_drop_target.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

class _StandaloneShortcutIntent extends Intent {
  final AppShortcutAction action;
  const _StandaloneShortcutIntent(this.action);
}

class _DeleteSelectedIntent extends Intent {
  const _DeleteSelectedIntent();
}

class _EscapeSelectionIntent extends Intent {
  const _EscapeSelectionIntent();
}

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

class _StandaloneQueueShortcutManager extends ShortcutManager {
  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (_isTextInputFocused()) {
      return KeyEventResult.ignored;
    }
    return super.handleKeypress(context, event);
  }

  bool _isTextInputFocused() {
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode == null) return false;

    final context = focusNode.context;
    if (context == null) return false;

    final widget = context.widget;
    if (widget is EditableText ||
        widget is TextField ||
        widget is TextFormField) {
      return true;
    }
    return context.findAncestorWidgetOfExactType<EditableText>() != null ||
        context.findAncestorWidgetOfExactType<TextField>() != null ||
        context.findAncestorWidgetOfExactType<TextFormField>() != null;
  }
}

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
  List<Map<String, dynamic>> _playlists = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  final _queueReorderController =
      ReorderableListController<MusicFile>(debugPrefix: 'standalone-queue-tile');
  final _playlistSongReorderController =
      ReorderableListController<dynamic>(debugPrefix: 'standalone-playlist-song-tile');
  final FocusNode _focusNode = FocusNode();
  late final _StandaloneQueueShortcutManager _shortcutManager;
  Map<AppShortcutAction, ShortcutBinding> _shortcutBindings = {};

  int _currentTabIndex = 0; // 0: 播放队列, 1: 播放列表
  Timer? _tabHoverTimer;
  String? _selectedPlaylistId;

  Map<String, dynamic>? get _activePlaylist {
    if (_playlists.isEmpty) return null;
    return _playlists.firstWhereOrNull((p) => p['id'] == _selectedPlaylistId) ??
        _playlists.first;
  }

  List<MusicFile> get _activePlaylistSongs {
    final active = _activePlaylist;
    if (active == null) return const [];
    final rawSongs = active['songs'] as List? ?? [];
    return rawSongs
        .map((item) => _musicFileFromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  final Set<int> _selectedIndices = {};
  bool _isSelectionMode = false;
  int? _lastAnchorIndex;

  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = const Color(0xFF6750A4);
  bool _isAlwaysOnTop = false;

  final ScrollController _scrollController = ScrollController();
  final ScrollController _playlistScrollController = ScrollController();

  bool get _isEffectiveDark {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  void _updateNativeTitleBar() {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    try {
      _controller.setDarkMode(_isEffectiveDark);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shortcutManager = _StandaloneQueueShortcutManager();
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

    final rawPlaylists = data['playlists'] as List? ?? [];
    final playlists = rawPlaylists
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final currentIndex = data['currentIndex'] as int? ?? -1;
    final isPlaying = data['isPlaying'] as bool? ?? false;
    final themeModeIdx = data['themeMode'] as int?;
    final accentVal = data['accentColor'] as int?;

    _queue = queue;
    _playlists = playlists;
    _currentIndex = currentIndex;
    _isPlaying = isPlaying;

    final serverCurrentPlaylistId = data['currentPlaylistId'] as String?;
    if (_selectedPlaylistId == null && playlists.isNotEmpty) {
      _selectedPlaylistId = serverCurrentPlaylistId ?? playlists.first['id'] as String?;
    } else if (_selectedPlaylistId != null && !playlists.any((p) => p['id'] == _selectedPlaylistId)) {
      _selectedPlaylistId = playlists.isNotEmpty ? playlists.first['id'] as String? : null;
    }

    _selectedIndices.removeWhere((idx) => idx >= _queue.length);

    if (themeModeIdx != null) {
      if (themeModeIdx == 0) _themeMode = ThemeMode.system;
      if (themeModeIdx == 1) _themeMode = ThemeMode.light;
      if (themeModeIdx == 2) _themeMode = ThemeMode.dark;
    }
    if (accentVal != null) {
      _accentColor = Color(accentVal);
    }
    final isAlwaysOnTop = data['isAlwaysOnTop'] as bool?;
    if (isAlwaysOnTop != null) {
      _isAlwaysOnTop = isAlwaysOnTop;
    }

    final rawShortcuts = data['shortcutBindings'] as Map?;
    if (rawShortcuts != null) {
      _shortcutBindings = {
        for (final entry in rawShortcuts.entries)
          AppShortcutActionX.fromStorageKey(entry.key.toString()):
              ShortcutBinding.fromJson(entry.value) ??
                  AppShortcutActionX.fromStorageKey(entry.key.toString()).defaultBinding,
      };
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

  void _onTabHoverEnter(int targetTab) {
    _tabHoverTimer?.cancel();
    if (_currentTabIndex != targetTab) {
      _tabHoverTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _currentTabIndex = targetTab;
            if (_currentTabIndex != 0) {
              _exitSelectionMode();
            }
          });
        }
      });
    }
  }

  void _onTabHoverExit() {
    _tabHoverTimer?.cancel();
    _tabHoverTimer = null;
  }

  void _playIndex(int index) {
    _sendIpc('play_index', index);
  }

  void _exitSelectionMode() {
    if (!mounted) return;
    setState(() {
      _isSelectionMode = false;
      _selectedIndices.clear();
      _lastAnchorIndex = null;
    });
  }

  void _toggleSelectAll() {
    if (_queue.isEmpty) return;
    setState(() {
      _isSelectionMode = true;
      if (_selectedIndices.length == _queue.length) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.clear();
        _selectedIndices.addAll(List.generate(_queue.length, (i) => i));
      }
    });
  }

  void _removeIndex(int index) {
    if (index >= 0 && index < _queue.length) {
      setState(() {
        _queue.removeAt(index);
        _selectedIndices.remove(index);
        if (_currentIndex == index) {
          _currentIndex = -1;
        } else if (_currentIndex > index) {
          _currentIndex--;
        }
      });
    }
    _sendIpc('remove_index', index);
  }

  void _removeSelected() {
    if (_selectedIndices.isEmpty) return;
    final indices = _selectedIndices.toList()..sort();
    _sendIpc('remove_indices', indices);
    setState(() {
      for (int i = indices.length - 1; i >= 0; i--) {
        final idx = indices[i];
        if (idx >= 0 && idx < _queue.length) {
          _queue.removeAt(idx);
          if (_currentIndex == idx) {
            _currentIndex = -1;
          } else if (_currentIndex > idx) {
            _currentIndex--;
          }
        }
      }
      _selectedIndices.clear();
      _isSelectionMode = false;
      _lastAnchorIndex = null;
    });
  }

  void _handleItemTap(int index) {
    final isShift = ModifierKeyUtils.isRangeSelectPressed;
    final isCtrl = ModifierKeyUtils.isDiscreteSelectPressed;

    if (isShift) {
      final anchor = _lastAnchorIndex ?? index;
      final range = ModifierKeyUtils.getIndexRange(anchor, index);
      setState(() {
        _isSelectionMode = true;
        _selectedIndices.addAll(range.where((i) => i >= 0 && i < _queue.length));
        _lastAnchorIndex = index;
      });
    } else if (isCtrl) {
      setState(() {
        _isSelectionMode = true;
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
          if (_selectedIndices.isEmpty) {
            _isSelectionMode = false;
          }
        } else {
          _selectedIndices.add(index);
        }
        _lastAnchorIndex = index;
      });
    } else if (_isSelectionMode) {
      setState(() {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
          if (_selectedIndices.isEmpty) {
            _isSelectionMode = false;
          }
        } else {
          _selectedIndices.add(index);
        }
        _lastAnchorIndex = index;
      });
    } else {
      _lastAnchorIndex = index;
      _playIndex(index);
    }
  }

  void _handleItemRightClick(BuildContext context, Offset globalPos, int index) {
    final isSelected = _selectedIndices.contains(index);
    final count = _selectedIndices.length;

    final items = <PopupMenuEntry<String>>[];

    if (isSelected && count > 1) {
      items.add(
        PopupMenuItem<String>(
          value: 'remove_selected',
          child: Row(
            children: [
              const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text('从队列中移除 ($count 首)'),
            ],
          ),
        ),
      );
      items.add(const PopupMenuDivider());
      items.add(
        const PopupMenuItem<String>(
          value: 'select_all',
          child: Row(
            children: [
              Icon(Icons.select_all_rounded, size: 18),
              SizedBox(width: 8),
              Text('全选'),
            ],
          ),
        ),
      );
      items.add(
        const PopupMenuItem<String>(
          value: 'clear_selection',
          child: Row(
            children: [
              Icon(Icons.deselect_rounded, size: 18),
              SizedBox(width: 8),
              Text('取消选择'),
            ],
          ),
        ),
      );
    } else {
      items.add(
        const PopupMenuItem<String>(
          value: 'play',
          child: Row(
            children: [
              Icon(Icons.play_arrow_rounded, size: 18),
              SizedBox(width: 8),
              Text('播放'),
            ],
          ),
        ),
      );
      items.add(
        const PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('从队列中移除'),
            ],
          ),
        ),
      );
      items.add(const PopupMenuDivider());
      items.add(
        const PopupMenuItem<String>(
          value: 'enter_select',
          child: Row(
            children: [
              Icon(Icons.checklist_rounded, size: 18),
              SizedBox(width: 8),
              Text('多选'),
            ],
          ),
        ),
      );
    }

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPos & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: items,
    ).then((action) {
      if (action == null) return;
      switch (action) {
        case 'remove_selected':
          _removeSelected();
          break;
        case 'select_all':
          _toggleSelectAll();
          break;
        case 'clear_selection':
          _exitSelectionMode();
          break;
        case 'play':
          _playIndex(index);
          break;
        case 'remove':
          _removeIndex(index);
          break;
        case 'enter_select':
          setState(() {
            _isSelectionMode = true;
            _selectedIndices.add(index);
            _lastAnchorIndex = index;
          });
          break;
      }
    });
  }

  void _clearQueue() {
    _sendIpc('clear_queue');
    _exitSelectionMode();
  }

  void _reorderQueue(int oldIndex, int newIndex) {
    setState(() {
      _currentIndex = _queueReorderController.handleReorder(
        oldIndex: oldIndex,
        newIndex: newIndex,
        targetList: _queue,
        currentIndex: _currentIndex,
        selectedIndices: _selectedIndices,
        onPersist: () => _sendIpc('reorder', {'oldIndex': oldIndex, 'newIndex': newIndex}),
      ) ?? _currentIndex;
    });
  }

  void _reorderPlaylistSongs(String playlistId, int oldIndex, int newIndex) {
    final activePl = _activePlaylist;
    final rawSongs = activePl?['songs'] as List?;
    setState(() {
      _playlistSongReorderController.handleReorder(
        oldIndex: oldIndex,
        newIndex: newIndex,
        targetList: rawSongs,
        onPersist: () => _sendIpc('reorder_playlist_songs', {
          'playlistId': playlistId,
          'oldIndex': oldIndex,
          'newIndex': newIndex,
        }),
      );
    });
  }

  void _dockToMainWindow() async {
    _sendIpc('dock_to_main');
    try {
      await _controller.hide();
    } catch (_) {}
  }

  void _toggleAlwaysOnTop() async {
    final nextVal = !_isAlwaysOnTop;
    setState(() {
      _isAlwaysOnTop = nextVal;
    });
    try {
      await _controller.setAlwaysOnTop(nextVal);
    } catch (e) {
      debugPrint('[StandaloneQueueApp] Error setting always on top: $e');
    }
    _sendIpc('set_always_on_top', nextVal);
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
        final offset = (_currentIndex * 56.0) - 100;
        _scrollController.animateTo(
          offset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  String _formatDuration(int durationMs) {
    final minutes = durationMs ~/ 60000;
    final seconds = (durationMs % 60000) ~/ 1000;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建歌单'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '歌单名称',
              hintText: '请输入歌单名称',
              errorText: errorText,
            ),
            onChanged: (val) {
              if (errorText != null) {
                setDialogState(() => errorText = null);
              }
            },
            onSubmitted: (val) {
              final name = val.trim();
              if (name.isNotEmpty) {
                _sendIpc('create_playlist', {'name': name});
                Navigator.pop(ctx);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  _sendIpc('create_playlist', {'name': name});
                  Navigator.pop(ctx);
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabHoverTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _subChannel.setMethodCallHandler(null);
    _scrollController.dispose();
    _playlistScrollController.dispose();
    _focusNode.dispose();
    _shortcutManager.dispose();
    _queueReorderController.clear();
    _playlistSongReorderController.clear();
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

  Map<ShortcutActivator, Intent> _buildShortcutMap() {
    final map = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.delete):
          const _DeleteSelectedIntent(),
      const SingleActivator(LogicalKeyboardKey.backspace):
          const _DeleteSelectedIntent(),
      const SingleActivator(LogicalKeyboardKey.escape):
          const _EscapeSelectionIntent(),
      const SingleActivator(LogicalKeyboardKey.keyA, control: true):
          const _SelectAllIntent(),
      const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
          const _SelectAllIntent(),
    };

    for (final action in AppShortcutAction.values) {
      final binding = _shortcutBindings[action] ?? action.defaultBinding;
      final activator = binding.toActivator();
      if (activator == null) continue;
      if (!map.containsKey(activator)) {
        map[activator] = _StandaloneShortcutIntent(action);
      }
    }

    return map;
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = _buildTheme(Brightness.light, _accentColor);
    final darkTheme = _buildTheme(Brightness.dark, _accentColor);

    final activePlaylistSongs = _activePlaylistSongs;
    _queueReorderController.syncLength(_queue.length);
    _playlistSongReorderController.syncLength(activePlaylistSongs.length);
    _selectedIndices.removeWhere((idx) => idx >= _queue.length);
    _shortcutManager.shortcuts = _buildShortcutMap();

    return ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '播放队列与歌单 - Vynody',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: _themeMode,
        home: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Shortcuts.manager(
            manager: _shortcutManager,
            child: Actions(
              actions: <Type, Action<Intent>>{
                _DeleteSelectedIntent: CallbackAction<_DeleteSelectedIntent>(
                  onInvoke: (_) => _removeSelected(),
                ),
                _EscapeSelectionIntent: CallbackAction<_EscapeSelectionIntent>(
                  onInvoke: (_) => _exitSelectionMode(),
                ),
                _SelectAllIntent: CallbackAction<_SelectAllIntent>(
                  onInvoke: (_) => _toggleSelectAll(),
                ),
                _StandaloneShortcutIntent:
                    CallbackAction<_StandaloneShortcutIntent>(
                  onInvoke: (intent) {
                    _sendIpc('shortcut_action', intent.action.storageKey);
                    return null;
                  },
                ),
              },
              child: Focus(
                focusNode: _focusNode,
                autofocus: true,
                child: Scaffold(
                  backgroundColor: theme.scaffoldBackgroundColor,
                  body: QueueFileDropTarget(
                    enabled: true,
                    displayQueue: _currentTabIndex == 0 ? _queue : activePlaylistSongs,
                    queueSongs: _currentTabIndex == 0 ? _queue : activePlaylistSongs,
                    itemKeyBuilder: (index, song) => _currentTabIndex == 0
                        ? _queueReorderController.getKey(index)
                        : _playlistSongReorderController.getKey(index),
                    showPreview: (_currentTabIndex == 0 ? _queue : activePlaylistSongs).isNotEmpty,
                    indicatorHorizontalPadding: 12.0,
                    onFilesDropped: (paths, insertIndex) async {
                      if (_currentTabIndex == 0) {
                        _sendIpc('add_files', {
                          'paths': paths,
                          'insertIndex': insertIndex,
                          'playNow': false,
                        });
                      } else {
                        final active = _activePlaylist;
                        if (active != null) {
                          _sendIpc('add_to_playlist', {
                            'playlistId': active['id'],
                            'paths': paths,
                          });
                        }
                      }
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isSelecting =
                            _isSelectionMode || _selectedIndices.isNotEmpty;
                        final isWide = constraints.maxWidth >= 380;

                        return Column(
                          children: [
                            _buildTitleBar(context, isWide: isWide),
                            if (!isWide && !isSelecting)
                              _buildTabBarRow(context),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: _currentTabIndex == 0
                                    ? (_queue.isEmpty
                                        ? _buildEmptyView(context)
                                        : _buildQueueList(context))
                                    : _buildPlaylistsView(context),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

  Widget _buildTitleBar(BuildContext context, {required bool isWide}) {
    final theme = Theme.of(context);
    final isSelecting = _isSelectionMode || _selectedIndices.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isSelecting
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isSelecting
                ? theme.colorScheme.primary.withValues(alpha: 0.25)
                : theme.dividerColor.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: isSelecting
          ? Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: _exitSelectionMode,
                  visualDensity: VisualDensity.compact,
                  tooltip: '退出多选',
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 4),
                Text(
                  '已选 ${_selectedIndices.length} 项',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                AppTooltip(
                  message: _selectedIndices.length == _queue.length ? '取消全选' : '全选',
                  child: IconButton(
                    icon: Icon(
                      _selectedIndices.length == _queue.length
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      size: 19,
                    ),
                    onPressed: _toggleSelectAll,
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (_selectedIndices.isNotEmpty)
                  AppTooltip(
                    message: '从队列中移除',
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 19),
                      onPressed: _removeSelected,
                      visualDensity: VisualDensity.compact,
                      color: theme.colorScheme.error,
                    ),
                  ),
                if (!Platform.isLinux)
                  AppTooltip(
                    message: _isAlwaysOnTop ? '取消置顶' : '置顶',
                    child: IconButton(
                      icon: Icon(
                        _isAlwaysOnTop
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 18,
                      ),
                      onPressed: _toggleAlwaysOnTop,
                      visualDensity: VisualDensity.compact,
                      color: _isAlwaysOnTop
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                AppTooltip(
                  message: '吸附回主窗口',
                  child: IconButton(
                    icon: const Icon(Icons.vertical_align_bottom_rounded, size: 18),
                    onPressed: _dockToMainWindow,
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                if (isWide)
                  _buildInlineTabBar(context)
                else ...[
                  Icon(
                    _currentTabIndex == 0
                        ? Icons.queue_music_rounded
                        : Icons.playlist_play_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentTabIndex == 0 ? '播放队列' : '播放列表',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
                const Spacer(),
                if (_currentTabIndex == 0 && _queue.isNotEmpty) ...[
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
                if (!Platform.isLinux)
                  AppTooltip(
                    message: _isAlwaysOnTop ? '取消置顶' : '置顶',
                    child: IconButton(
                      icon: Icon(
                        _isAlwaysOnTop
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 18,
                      ),
                      onPressed: _toggleAlwaysOnTop,
                      visualDensity: VisualDensity.compact,
                      color: _isAlwaysOnTop
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                AppTooltip(
                  message: '吸附回主窗口',
                  child: IconButton(
                    icon: const Icon(Icons.vertical_align_bottom_rounded, size: 18),
                    onPressed: _dockToMainWindow,
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInlineTabBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPillTabItem(
            context: context,
            title: '播放队列',
            count: _queue.length,
            index: 0,
            isSelected: _currentTabIndex == 0,
            isCompact: true,
          ),
          const SizedBox(width: 4),
          _buildPillTabItem(
            context: context,
            title: '播放列表',
            count: _playlists.length,
            index: 1,
            isSelected: _currentTabIndex == 1,
            isCompact: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBarRow(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: Container(
        height: 34,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildPillTabItem(
                context: context,
                title: '播放队列',
                count: _queue.length,
                index: 0,
                isSelected: _currentTabIndex == 0,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _buildPillTabItem(
                context: context,
                title: '播放列表',
                count: _playlists.length,
                index: 1,
                isSelected: _currentTabIndex == 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillTabItem({
    required BuildContext context,
    required String title,
    required int count,
    required int index,
    required bool isSelected,
    bool isCompact = false,
  }) {
    final theme = Theme.of(context);

    return DropRegion(
      formats: const [Formats.fileUri, Formats.plainText, Formats.uri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropEnter: (_) => _onTabHoverEnter(index),
      onDropLeave: (_) => _onTabHoverExit(),
      onDropEnded: (_) => _onTabHoverExit(),
      onDropOver: (event) => DropOperation.copy,
      onPerformDrop: (event) async {},
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _currentTabIndex = index;
            if (_currentTabIndex != 0) {
              _exitSelectionMode();
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          padding: isCompact
              ? const EdgeInsets.symmetric(horizontal: 10)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistsView(BuildContext context) {
    final theme = Theme.of(context);

    if (_playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_play_rounded,
              size: 52,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 14),
            Text(
              '暂无播放列表',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _showCreatePlaylistDialog(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建歌单'),
            ),
          ],
        ),
      );
    }

    final activePlaylist = _activePlaylist;
    if (activePlaylist == null) {
      return const SizedBox.shrink();
    }

    final songs = _activePlaylistSongs;

    return Column(
      children: [
        _buildPlaylistSelectorHeader(context, activePlaylist),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: songs.isEmpty
              ? _buildEmptyPlaylistSongsView(context, activePlaylist)
              : _buildPlaylistSongsList(context, activePlaylist, songs),
        ),
      ],
    );
  }

  Widget _buildPlaylistSelectorHeader(
    BuildContext context,
    Map<String, dynamic> activePlaylist,
  ) {
    final theme = Theme.of(context);
    final plId = activePlaylist['id'] as String? ?? '';
    final rawName = activePlaylist['name'] as String? ?? '';
    final isFavorite =
        activePlaylist['isFavorite'] as bool? ?? (plId == 'favorites');
    final isDefault =
        activePlaylist['isDefault'] as bool? ?? (plId == 'default');
    final plName = isFavorite ? '收藏' : (isDefault ? '默认列表' : rawName);
    final isBuiltin = isFavorite || isDefault;
    final songs = _activePlaylistSongs;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      ),
      child: Row(
        children: [
          Expanded(
            child: Builder(
              builder: (btnContext) => Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    final box = btnContext.findRenderObject() as RenderBox?;
                    final overlay = Overlay.of(context)
                        .context
                        .findRenderObject() as RenderBox?;
                    if (box == null || overlay == null) return;

                    final pos = box.localToGlobal(Offset.zero);
                    final position = RelativeRect.fromRect(
                      pos & box.size,
                      Offset.zero & overlay.size,
                    );

                    await showMenu<String>(
                      context: context,
                      position: position,
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      color: theme.colorScheme.surface,
                      items: _playlists.map((pl) {
                        final id = pl['id'] as String? ?? '';
                        final name = pl['name'] as String? ?? '';
                        final isFav =
                            pl['isFavorite'] as bool? ?? (id == 'favorites');
                        final isDef =
                            pl['isDefault'] as bool? ?? (id == 'default');
                        final displayName =
                            isFav ? '收藏' : (isDef ? '默认列表' : name);
                        final count = pl['songCount'] as int? ??
                            ((pl['songs'] as List?)?.length ?? 0);
                        final isCurrentSelected = id == _selectedPlaylistId;

                        return PopupMenuItem<String>(
                          value: id,
                          child: Row(
                            children: [
                              Icon(
                                isFav
                                    ? Icons.favorite_rounded
                                    : (isDef
                                        ? Icons.queue_music_rounded
                                        : Icons.playlist_play_rounded),
                                size: 18,
                                color: isFav
                                    ? Colors.redAccent
                                    : (isCurrentSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isCurrentSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isCurrentSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ).then((selectedId) {
                      if (selectedId != null && mounted) {
                        setState(() => _selectedPlaylistId = selectedId);
                        _sendIpc('set_current_playlist', {'playlistId': selectedId});
                      }
                    });
                  },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isFavorite
                            ? Icons.favorite_rounded
                            : (isDefault
                                ? Icons.queue_music_rounded
                                : Icons.playlist_play_rounded),
                        size: 16,
                        color: isFavorite
                            ? Colors.redAccent
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$plName (${songs.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),
          const SizedBox(width: 4),
          if (songs.isNotEmpty) ...[
            AppTooltip(
              message: '播放全部',
              child: IconButton(
                icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
                onPressed: () => _sendIpc('play_playlist', {
                  'playlistId': plId,
                  'initialIndex': 0,
                }),
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.primary,
              ),
            ),
            AppTooltip(
              message: '追加到队列末尾',
              child: IconButton(
                icon: const Icon(Icons.playlist_add_rounded, size: 20),
                onPressed: () => _sendIpc('append_playlist_to_queue', {
                  'playlistId': plId,
                }),
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          AppTooltip(
            message: '新建歌单',
            child: IconButton(
              icon: const Icon(Icons.add_rounded, size: 20),
              onPressed: () => _showCreatePlaylistDialog(context),
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            tooltip: '更多选项',
            color: theme.colorScheme.surface,
            onSelected: (action) async {
              if (action == 'clear') {
                _sendIpc('clear_playlist', {'playlistId': plId});
              } else if (action == 'rename') {
                _showRenamePlaylistDialog(context, plId, rawName);
              } else if (action == 'delete') {
                _sendIpc('delete_playlist', {'playlistId': plId});
              }
            },
            itemBuilder: (ctx) => [
              if (songs.isNotEmpty)
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.clear_all_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('清空歌曲'),
                    ],
                  ),
                ),
              if (!isBuiltin) ...[
                const PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('重命名歌单'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('删除歌单', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPlaylistSongsView(
    BuildContext context,
    Map<String, dynamic> playlist,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_add_rounded,
              size: 52,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 14),
            Text(
              '歌单内暂无歌曲',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '可直接拖拽本地音频文件至此添加',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistSongsList(
    BuildContext context,
    Map<String, dynamic> playlist,
    List<MusicFile> songs,
  ) {
    final plId = playlist['id'] as String? ?? '';
    _playlistSongReorderController.syncLength(songs.length);
    final currentMusicPath = (_currentIndex >= 0 && _currentIndex < _queue.length)
        ? _queue[_currentIndex].path
        : null;

    return ReorderableListView.builder(
      scrollController: _playlistScrollController,
      buildDefaultDragHandles: false,
      itemCount: songs.length,
      onReorderItem: (oldIndex, newIndex) {
        _reorderPlaylistSongs(plId, oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final song = songs[index];
        final isCurrent = currentMusicPath != null && currentMusicPath == song.path;

        return _StandalonePlaylistSongTile(
          key: _playlistSongReorderController.getKey(index),
          song: song,
          index: index,
          isCurrent: isCurrent,
          isPlaying: isCurrent && _isPlaying,
          durationFormatted: song.durationMillis != null && song.durationMillis! > 0
              ? _formatDuration(song.durationMillis!)
              : '',
          onTap: () => _sendIpc('play_playlist', {
            'playlistId': plId,
            'initialIndex': index,
          }),
          onSecondaryTap: (pos) => _handlePlaylistSongRightClick(
            context,
            pos,
            song,
            index,
            plId,
          ),
          onRemove: () => _sendIpc('remove_from_playlist', {
            'playlistId': plId,
            'indices': [index],
          }),
        );
      },
    );
  }

  void _handlePlaylistSongRightClick(
    BuildContext context,
    Offset globalPos,
    MusicFile song,
    int index,
    String playlistId,
  ) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      items: [
        PopupMenuItem(
          value: 'play',
          child: Row(
            children: [
              Icon(Icons.play_arrow_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('立即播放'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'next',
          child: Row(
            children: [
              Icon(Icons.playlist_play_rounded, size: 18),
              SizedBox(width: 8),
              Text('下一首播放'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'queue',
          child: Row(
            children: [
              Icon(Icons.playlist_add_rounded, size: 18),
              SizedBox(width: 8),
              Text('追加到队列'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.remove_circle_outline_rounded, size: 18, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('从歌单中移除', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    ).then((action) {
      if (action == 'play') {
        _sendIpc('play_playlist', {
          'playlistId': playlistId,
          'initialIndex': index,
        });
      } else if (action == 'next') {
        _sendIpc('enqueue_next', {'songPaths': [song.path]});
      } else if (action == 'queue') {
        _sendIpc('append_to_queue', {'songPaths': [song.path]});
      } else if (action == 'remove') {
        _sendIpc('remove_from_playlist', {
          'playlistId': playlistId,
          'indices': [index],
        });
      }
    });
  }

  void _showRenamePlaylistDialog(
    BuildContext context,
    String playlistId,
    String currentName,
  ) {
    final controller = TextEditingController(text: currentName);
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('重命名歌单'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '歌单名称',
              errorText: errorText,
            ),
            onSubmitted: (val) {
              final newName = val.trim();
              if (newName.isNotEmpty && newName != currentName) {
                _sendIpc('rename_playlist', {
                  'playlistId': playlistId,
                  'name': newName,
                });
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isNotEmpty && newName != currentName) {
                  _sendIpc('rename_playlist', {
                    'playlistId': playlistId,
                    'name': newName,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
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
    final isSelecting = _isSelectionMode || _selectedIndices.isNotEmpty;

    _queueReorderController.syncLength(_queue.length);

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
        final isSelected = _selectedIndices.contains(index);

        final artist = (song.artist != null && song.artist!.trim().isNotEmpty)
            ? song.artist!.trim()
            : '未知歌手';
        final album = (song.album != null && song.album!.trim().isNotEmpty)
            ? song.album!.trim()
            : null;
        final subtitleText = album != null ? '$artist - $album' : artist;

        final itemColor = isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
            : (isCurrent
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : Colors.transparent);

        return Material(
          key: _queueReorderController.getKey(index),
          color: itemColor,
          child: InkWell(
            onTap: () => _handleItemTap(index),
            onLongPress: () {
              setState(() {
                _isSelectionMode = true;
                if (!_selectedIndices.contains(index)) {
                  _selectedIndices.add(index);
                }
                _lastAnchorIndex = index;
              });
            },
            onSecondaryTapUp: (details) =>
                _handleItemRightClick(context, details.globalPosition, index),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.06),
                  ),
                  left: isSelected
                      ? BorderSide(
                          color: theme.colorScheme.primary,
                          width: 3.0,
                        )
                      : BorderSide.none,
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
                  const SizedBox(width: 4),
                  Expanded(
                    child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 38,
                              height: 38,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Opacity(
                                    opacity: isSelecting
                                        ? (isSelected ? 0.5 : 0.7)
                                        : 1.0,
                                    child: SongThumbnail.fromSong(
                                      song,
                                      size: 38.0,
                                    ),
                                  ),
                                  if (isSelecting)
                                    Positioned.fill(
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                              child: Checkbox(
                                                value: isSelected,
                                                onChanged: (_) {
                                                  setState(() {
                                                    if (_selectedIndices.contains(index)) {
                                                      _selectedIndices.remove(index);
                                                      if (_selectedIndices.isEmpty) {
                                                        _isSelectionMode = false;
                                                      }
                                                    } else {
                                                      _selectedIndices.add(index);
                                                    }
                                                    _lastAnchorIndex = index;
                                                  });
                                                },
                                                fillColor: WidgetStateProperty.all(Colors.white),
                                                checkColor: Colors.black,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                visualDensity: VisualDensity.compact,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
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
                                  subtitleText,
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
                  if (!isSelecting)
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

class _StandalonePlaylistSongTile extends StatefulWidget {
  final MusicFile song;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final String durationFormatted;
  final VoidCallback onTap;
  final ValueChanged<Offset> onSecondaryTap;
  final VoidCallback onRemove;

  const _StandalonePlaylistSongTile({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.durationFormatted,
    required this.onTap,
    required this.onSecondaryTap,
    required this.onRemove,
  });

  @override
  State<_StandalonePlaylistSongTile> createState() =>
      _StandalonePlaylistSongTileState();
}

class _StandalonePlaylistSongTileState
    extends State<_StandalonePlaylistSongTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.song;

    final artist = (song.artist != null && song.artist!.trim().isNotEmpty)
        ? song.artist!.trim()
        : '未知歌手';
    final album = (song.album != null && song.album!.trim().isNotEmpty)
        ? song.album!.trim()
        : null;
    final subtitleText = album != null ? '$artist - $album' : artist;

    final itemColor = widget.isCurrent
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
        : (_isHovered
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : Colors.transparent);

    return Material(
      color: itemColor,
      child: InkWell(
        onTap: widget.onTap,
        onSecondaryTapUp: (details) =>
            widget.onSecondaryTap(details.globalPosition),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.05),
                ),
              ),
            ),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: _isHovered ? 0.6 : 0.25,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      SongThumbnail.fromSong(
                        song,
                        size: 36.0,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (widget.isCurrent) ...[
                                  Icon(
                                    widget.isPlaying
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
                                      fontSize: 13,
                                      fontWeight: widget.isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: widget.isCurrent
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.durationFormatted.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    widget.durationFormatted,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.5),
                  ),
                  onPressed: widget.onRemove,
                  visualDensity: VisualDensity.compact,
                  tooltip: '从歌单中移除',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
