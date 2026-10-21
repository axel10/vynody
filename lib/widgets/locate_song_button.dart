import 'package:flutter/material.dart';
import 'package:vynody/utils/song_locator_helper.dart';

import 'folder_nav_bar_scaffold.dart';

/// 定位按钮的转圈图标。
///
/// 定位一首 Subsonic / Jellyfin 歌曲要先请求服务端解析它所属的专辑，
/// 连接超时 10s、Jellyfin 还要先鉴权，这段静默期原本看起来就是「点了没反应」。
class LocateSpinner extends StatelessWidget {
  const LocateSpinner({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Padding(
        padding: EdgeInsets.all(size * 0.12),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: color,
        ),
      ),
    );
  }
}

/// 目录页 / 远程浏览页导航栏里的定位按钮（[FolderNavIconButton] 版）。
///
/// 定位进行中把图标换成转圈并禁用点击，避免连点压出重复的专辑页。
class LocateSongNavButton extends StatelessWidget {
  const LocateSongNavButton({
    super.key,
    required this.style,
    required this.tooltip,
    required this.onPressed,
  });

  final FolderNavBarStyle style;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SongLocatorHelper.isLocating,
      builder: (context, locating, _) => FolderNavIconButton(
        style: style,
        tooltip: tooltip,
        icon: locating
            ? LocateSpinner(size: 20, color: style.iconColor)
            : Icon(
                Icons.my_location_rounded,
                size: 20,
                color: style.iconColor,
                shadows: style.shadows,
              ),
        onPressed: locating ? null : onPressed,
      ),
    );
  }
}

/// 远程库首页 / 专辑详情页头部的定位按钮（标准 [IconButton] 版）。
class LocateSongIconButton extends StatelessWidget {
  const LocateSongIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 20,
  });

  final String? tooltip;
  final VoidCallback onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<bool>(
      valueListenable: SongLocatorHelper.isLocating,
      builder: (context, locating, _) => IconButton(
        tooltip: tooltip,
        icon: locating
            ? LocateSpinner(size: iconSize, color: primary)
            : Icon(Icons.my_location_rounded, size: iconSize),
        onPressed: locating ? null : onPressed,
      ),
    );
  }
}
