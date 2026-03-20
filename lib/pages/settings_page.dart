import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../player/settings_service.dart';
import '../l10n/app_localizations.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings, style: const TextStyle(color: Colors.white))),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(l10n.immersiveTabBar, style: const TextStyle(color: Colors.white)),
            subtitle: Text(l10n.immersiveTabBarDescription, style: const TextStyle(color: Colors.white70)),
            value: settings.isImmersiveTabBarEnabled,
            onChanged: (value) {
              settings.isImmersiveTabBarEnabled = value;
            },
          ),
          ListTile(
            title: Text(l10n.sampleStride, style: const TextStyle(color: Colors.white)),
            subtitle: Text(l10n.sampleStrideDescription, style: const TextStyle(color: Colors.white70)),
            trailing: SizedBox(
              width: 120,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white),
                    onPressed: settings.sampleStride > 1
                        ? () => settings.sampleStride--
                        : null,
                  ),
                  Text(
                    '${settings.sampleStride}',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: settings.sampleStride < 20
                        ? () => settings.sampleStride++
                        : null,
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            title: Text(l10n.waveformSegments, style: const TextStyle(color: Colors.white)),
            subtitle: Text(l10n.waveformSegmentsDescription, style: const TextStyle(color: Colors.white70)),
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
            title: Text(l10n.enableWaveformProgressBar,
                style: const TextStyle(color: Colors.white)),
            subtitle: Text(l10n.enableWaveformProgressBarDescription,
                style: const TextStyle(color: Colors.white70)),
            value: settings.isWaveformProgressBarEnabled,
            onChanged: (value) {
              settings.isWaveformProgressBarEnabled = value;
            },
          ),
        ],
      ),
    );
  }
}

