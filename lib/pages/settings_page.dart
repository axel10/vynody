import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dialogs/gemini_api_key_dialog.dart';
import '../player/audio_riverpod.dart';
import '../l10n/app_localizations.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsServiceProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings, style: const TextStyle(color: Colors.white)),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(
              l10n.immersiveTabBar,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              l10n.immersiveTabBarDescription,
              style: const TextStyle(color: Colors.white70),
            ),
            value: settings.isImmersiveTabBarEnabled,
            onChanged: (value) {
              settings.isImmersiveTabBarEnabled = value;
            },
          ),
          ListTile(
            title: Text(
              l10n.waveformSegments,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              l10n.waveformSegmentsDescription,
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: SizedBox(
              width: 120,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white),
                    onPressed: settings.waveformChunks > 20
                        ? () => settings.waveformChunks -= 10
                        : null,
                  ),
                  Text(
                    '${settings.waveformChunks}',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: settings.waveformChunks < 200
                        ? () => settings.waveformChunks += 10
                        : null,
                  ),
                ],
              ),
            ),
          ),
          SwitchListTile(
            title: Text(
              l10n.enableWaveformProgressBar,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              l10n.enableWaveformProgressBarDescription,
              style: const TextStyle(color: Colors.white70),
            ),
            value: settings.isWaveformProgressBarEnabled,
            onChanged: (value) {
              settings.isWaveformProgressBarEnabled = value;
            },
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined, color: Colors.white),
            title: const Text(
              'Google AI Studio API Key',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              settings.geminiApiKey.trim().isEmpty
                  ? '未保存到本机设置，生成和翻译时会先弹窗提示。'
                  : '已保存到本机设置，可直接用于 Gemini 相关功能。',
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: FilledButton.tonal(
              onPressed: () async {
                final enteredApiKey = await showGeminiApiKeyDialog(
                  context,
                  initialApiKey: settings.geminiApiKey,
                );
                if (enteredApiKey == null || enteredApiKey.trim().isEmpty) {
                  return;
                }

                settings.geminiApiKey = enteredApiKey;
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Google AI Studio API Key 已保存')),
                );
              },
              child: Text(settings.geminiApiKey.trim().isEmpty ? '填写' : '修改'),
            ),
          ),
        ],
      ),
    );
  }
}
