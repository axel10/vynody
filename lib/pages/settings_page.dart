import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../dialogs/acoustid_api_key_dialog.dart';
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
            isThreeLine: true,
            leading: const Icon(Icons.fingerprint, color: Colors.white),
            title: const Text(
              'AcoustID API Key',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.hasCustomAcoustidApiKey
                      ? '已保存自定义 key，音频指纹识别会优先使用它。'
                      : '当前使用应用内置的默认 key，建议申请你自己的 key 后替换。',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () async {
                    final uri = Uri.parse(
                      'https://acoustid.org/new-application',
                    );
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  child: const Text(
                    '申请 API key: https://acoustid.org/new-application',
                    style: TextStyle(
                      color: Colors.lightBlueAccent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            trailing: FilledButton.tonal(
              onPressed: () async {
                final enteredApiKey = await showAcoustidApiKeyDialog(
                  context,
                  initialApiKey: settings.hasCustomAcoustidApiKey
                      ? settings.acoustidApiKey
                      : '',
                );
                if (enteredApiKey == null) {
                  return;
                }

                settings.acoustidApiKey = enteredApiKey;
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('AcoustID API Key 已保存')),
                );
              },
              child: Text(settings.hasCustomAcoustidApiKey ? '修改' : '填写'),
            ),
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
                  ref: ref,
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
