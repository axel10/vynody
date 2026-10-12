import 'package:flutter/material.dart';

class RemoteLibraryHeaderBottom extends StatelessWidget
    implements PreferredSizeWidget {
  final TabBar tabBar;

  const RemoteLibraryHeaderBottom({
    super.key,
    required this.tabBar,
  });

  @override
  Size get preferredSize => const Size.fromHeight(40.0);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40.0,
      child: Center(child: tabBar),
    );
  }
}

typedef NavidromeHeaderBottom = RemoteLibraryHeaderBottom;
