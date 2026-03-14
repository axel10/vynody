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
          ListTile(
            title: const Text('波形采样步长 (sampleStride)'),
            subtitle: const Text('值越大扫描越快，但波形精度越低（默认 4）'),
            trailing: SizedBox(
              width: 120,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: settings.sampleStride > 1
                        ? () => settings.sampleStride--
                        : null,
                  ),
                  Text(
                    '${settings.sampleStride}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: settings.sampleStride < 20
                        ? () => settings.sampleStride++
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
