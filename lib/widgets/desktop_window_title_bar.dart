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
    this.showButtonGroupBackground = false,
  });

  final Brightness brightness;
  final double height;
  final bool showSmallWindowButton;
  final bool showButtonGroupBackground;

  @override
  ConsumerState<DesktopWindowTitleBar> createState() =>
      _DesktopWindowTitleBarState();
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
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
    }
    await _syncWindowState();
  }

  @override
  Widget build(BuildContext context) {
    final isMacOS = Platform.isMacOS;
    final isWindowsOrLinux = Platform.isWindows || Platform.isLinux;
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
                icon: isSmallWindowMode
                    ? Icons.open_in_full
                    : Icons.picture_in_picture_alt,
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
            if (isWindowsOrLinux)
              _WindowsCapsuleButtons(
                buttons: [
                  if (showMiniButton) ...[
                    _CapsuleButtonData(
                      icon: isSmallWindowMode
                          ? Icons.open_in_full
                          : Icons.picture_in_picture_alt,
                      iconSize: isSmallWindowMode ? 14 : 16,
                      onPressed: () {
                        settings.isSmallWindowMode =
                            !settings.isSmallWindowMode;
                      },
                    ),
                    if (isSmallWindowMode)
                      _CapsuleButtonData(
                        icon: Icons.queue_music,
                        iconSize: 14,
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
                    _CapsuleButtonData(
                      icon: _isFullScreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      iconSize: 16,
                      onPressed: () async {
                        await _setFullScreen(!_isFullScreen);
                      },
                    ),
                    _CapsuleButtonData(
                      icon: Icons.remove,
                      iconSize: 16,
                      onPressed: () async {
                        if (_isFullScreen) {
                          await _setFullScreen(false);
                        }
                        await windowManager.minimize();
                      },
                    ),
                    _CapsuleButtonData(
                      icon: _isMaximized
                          ? Icons.filter_none
                          : Icons.crop_square,
                      iconSize: 12,
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
                  _CapsuleButtonData(
                    icon: Icons.close,
                    iconSize: 16,
                    isClose: true,
                    onPressed: windowManager.close,
                  ),
                ],
                brightness: widget.brightness,
                height: widget.height,
                showBackground: widget.showButtonGroupBackground,
              ),
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
  State<_MacosSmallWindowButton> createState() =>
      _MacosSmallWindowButtonState();
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

class _CapsuleButtonData {
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final Color? color;
  final bool isClose;

  _CapsuleButtonData({
    required this.icon,
    required this.onPressed,
    this.iconSize = 16,
    this.color,
    this.isClose = false,
  });
}

class _WindowsCapsuleButtons extends StatelessWidget {
  final List<_CapsuleButtonData> buttons;
  final Brightness brightness;
  final double height;
  final bool showBackground;

  const _WindowsCapsuleButtons({
    required this.buttons,
    required this.brightness,
    required this.height,
    required this.showBackground,
  });

  @override
  Widget build(BuildContext context) {
    if (buttons.isEmpty) return const SizedBox.shrink();

    final isDark = brightness == Brightness.dark;

    final Color capsuleBg = Colors.black.withValues(alpha: 0.12);

    final Color capsuleBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.16);

    if (!showBackground) {
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(buttons.length, (index) {
              return _WindowsCapsuleButton(
                data: buttons[index],
                brightness: brightness,
                height: height,
              );
            }),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(13),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(13),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              height: height,
              padding: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: capsuleBg,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(13),
                ),
                border: Border.all(color: capsuleBorderColor, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(buttons.length, (index) {
                  return _WindowsCapsuleButton(
                    data: buttons[index],
                    brightness: brightness,
                    height: height,
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowsCapsuleButton extends StatefulWidget {
  final _CapsuleButtonData data;
  final Brightness brightness;
  final double height;

  const _WindowsCapsuleButton({
    required this.data,
    required this.brightness,
    required this.height,
  });

  @override
  State<_WindowsCapsuleButton> createState() => _WindowsCapsuleButtonState();
}

class _WindowsCapsuleButtonState extends State<_WindowsCapsuleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;
    final buttonRadius = BorderRadius.only(
      bottomLeft: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
      topLeft: Radius.circular(widget.height / 8),
      topRight: Radius.circular(widget.height / 8),
    );

    Color iconColor =
        widget.data.color ?? (isDark ? Colors.white70 : Colors.black87);

    if (_isHovered) {
      if (widget.data.isClose) {
        iconColor = Colors.white;
      } else if (widget.data.color == null) {
        iconColor = isDark ? Colors.white : Colors.black;
      }
    }

    Color hoverBg;
    if (widget.data.isClose) {
      hoverBg = Colors.redAccent.withValues(alpha: 0.85);
    } else {
      hoverBg = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.10);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.data.onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: widget.height,
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: widget.height - 10,
            decoration: BoxDecoration(
              color: _isHovered ? hoverBg : Colors.transparent,
              borderRadius: buttonRadius,
            ),
            child: Icon(
              widget.data.icon,
              size: widget.data.iconSize,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
