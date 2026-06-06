import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../player/audio/audio_riverpod.dart';

class DesktopWindowTitleBar extends ConsumerStatefulWidget {
  const DesktopWindowTitleBar({
    super.key,
    required this.brightness,
    this.height = 32,
    this.showSmallWindowButton = false,
  });

  final Brightness brightness;
  final double height;
  final bool showSmallWindowButton;

  @override
  ConsumerState<DesktopWindowTitleBar> createState() => _DesktopWindowTitleBarState();
}

class _DesktopWindowTitleBarState extends ConsumerState<DesktopWindowTitleBar>
    with WindowListener {
  bool _isFullScreen = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncWindowState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncWindowState() async {
    if (!mounted) return;

    final isFull = await windowManager.isFullScreen();
    final isMax = await windowManager.isMaximized();
    if (!mounted) return;

    setState(() {
      _isFullScreen = isFull;
      _isMaximized = isMax;
    });
  }

  @override
  void onWindowEnterFullScreen() {
    _syncWindowState();
  }

  @override
  void onWindowLeaveFullScreen() {
    _syncWindowState();
  }

  @override
  void onWindowMinimize() {
    _syncWindowState();
  }

  @override
  void onWindowRestore() {
    _syncWindowState();
  }

  @override
  void onWindowMaximize() {
    _syncWindowState();
  }

  @override
  void onWindowUnmaximize() {
    _syncWindowState();
  }

  Future<void> _setFullScreen(bool enable) async {
    if (enable) {
      await windowManager.maximize();
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
      await windowManager.unmaximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    Color? hoverColor;
    hoverColor = widget.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    final isMacOS = Platform.isMacOS;
    final settings = ref.watch(settingsServiceProvider);
    final isSmallWindowMode = settings.isSmallWindowMode;
    final showMiniButton = widget.showSmallWindowButton || isSmallWindowMode;

    final Widget titleBarContent = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) {
        windowManager.startDragging();
      },
      onDoubleTap: () async {
        if (_isFullScreen) return;
        if (isSmallWindowMode) return;
        if (_isMaximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: SizedBox(
        height: widget.height,
        child: Row(
          children: [
            if (isMacOS && showMiniButton) ...[
              _MacosSmallWindowButton(
                icon: isSmallWindowMode ? Icons.open_in_full : Icons.picture_in_picture_alt,
                iconSize: isSmallWindowMode ? 16 : 18,
                onPressed: () {
                  settings.isSmallWindowMode = !settings.isSmallWindowMode;
                },
              ),
              if (isSmallWindowMode)
                _MacosSmallWindowButton(
                  icon: Icons.queue_music,
                  iconSize: 16,
                  color: settings.isSmallWindowQueueExpanded
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  onPressed: () {
                    settings.isSmallWindowQueueExpanded =
                        !settings.isSmallWindowQueueExpanded;
                  },
                ),
            ],
            const Spacer(),
            if (!isMacOS) ...[
              if (showMiniButton) ...[
                _WindowButton(
                  icon: isSmallWindowMode ? Icons.open_in_full : Icons.picture_in_picture_alt,
                  iconSize: isSmallWindowMode ? 16 : 18,
                  brightness: widget.brightness,
                  hoverColor: hoverColor,
                  onPressed: () {
                    settings.isSmallWindowMode = !settings.isSmallWindowMode;
                  },
                ),
                if (isSmallWindowMode)
                  _WindowButton(
                    icon: Icons.queue_music,
                    iconSize: 18,
                    brightness: widget.brightness,
                    hoverColor: hoverColor,
                    color: settings.isSmallWindowQueueExpanded
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    onPressed: () {
                      settings.isSmallWindowQueueExpanded =
                          !settings.isSmallWindowQueueExpanded;
                    },
                  ),
              ],
              if (!isSmallWindowMode) ...[
                _WindowButton(
                  icon: _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  brightness: widget.brightness,
                  hoverColor: hoverColor,
                  onPressed: () => _setFullScreen(!_isFullScreen),
                ),
                _WindowButton(
                  icon: Icons.remove,
                  brightness: widget.brightness,
                  hoverColor: hoverColor,
                  onPressed: () async {
                    if (_isFullScreen) {
                      await _setFullScreen(false);
                    }
                    await windowManager.minimize();
                  },
                ),
                _WindowButton(
                  icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                  iconSize: 14,
                  brightness: widget.brightness,
                  hoverColor: hoverColor,
                  onPressed: () async {
                    if (_isFullScreen) {
                      await _setFullScreen(false);
                    } else if (_isMaximized) {
                      await windowManager.unmaximize();
                    } else {
                      await windowManager.maximize();
                    }
                  },
                ),
              ],
              _WindowButton(
                icon: Icons.close,
                isClose: true,
                brightness: widget.brightness,
                hoverColor: hoverColor,
                onPressed: windowManager.close,
              ),
            ],
          ],
        ),
      ),
    );

    if (isMacOS) {
      return Padding(
        padding: const EdgeInsets.only(left: 80.0),
        child: titleBarContent,
      );
    }

    return titleBarContent;
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Brightness brightness;
  final bool isClose;
  final double iconSize;
  final Color? hoverColor;
  final Color? color;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.brightness,
    this.isClose = false,
    this.iconSize = 18,
    this.hoverColor,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = color ??
        (brightness == Brightness.dark ? Colors.white : Colors.black87);

    final Color effectiveHoverColor =
        hoverColor ??
        (isClose
            ? Colors.red.withValues(alpha: 0.8)
            : (brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05)));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        hoverColor: effectiveHoverColor,
        child: SizedBox(
          width: 46,
          height: 32,
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }
}

class _MacosSmallWindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;
  final Color? color;

  const _MacosSmallWindowButton({
    required this.icon,
    required this.iconSize,
    required this.onPressed,
    this.color,
  });

  @override
  State<_MacosSmallWindowButton> createState() => _MacosSmallWindowButtonState();
}

class _MacosSmallWindowButtonState extends State<_MacosSmallWindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          width: 42,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: _isHovered
                      ? Colors.white.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                    width: 0.5,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onPressed,
                    hoverColor: Colors.transparent,
                    splashColor: Colors.black.withValues(alpha: 0.05),
                    highlightColor: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    child: Center(
                      child: Icon(
                        widget.icon,
                        color: widget.color ?? Colors.black,
                        size: widget.iconSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
