import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowTitleBar extends StatefulWidget {
  const DesktopWindowTitleBar({
    super.key,
    required this.brightness,
    this.height = 32,
  });

  final Brightness brightness;
  final double height;

  @override
  State<DesktopWindowTitleBar> createState() => _DesktopWindowTitleBarState();
}

class _DesktopWindowTitleBarState extends State<DesktopWindowTitleBar>
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

    final Widget titleBarContent = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) {
        windowManager.startDragging();
      },
      onDoubleTap: () async {
        if (_isFullScreen) return;
        if (_isMaximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: SizedBox(
        height: widget.height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!isMacOS) ...[
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

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.brightness,
    this.isClose = false,
    this.iconSize = 18,
    this.hoverColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

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
