import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../player/settings_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('沉浸式Tab栏'),
            subtitle: const Text('在播放界面持续5秒不操作则导航栏完全透明'),
            value: settings.isImmersiveTabBarEnabled,
            onChanged: (value) {
              settings.isImmersiveTabBarEnabled = value;
            },
          ),
        ],
      ),
    );
  }
}
