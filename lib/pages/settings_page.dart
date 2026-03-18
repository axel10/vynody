import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../player/settings_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(color: Colors.white))),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Immersive Tab Bar', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Hide navigation bar after 5 seconds of inactivity', style: TextStyle(color: Colors.white70)),
            value: settings.isImmersiveTabBarEnabled,
            onChanged: (value) {
              settings.isImmersiveTabBarEnabled = value;
            },
          ),
          ListTile(
            title: const Text('Sample Stride', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Larger values scan faster but with lower waveform precision (default: 4)', style: TextStyle(color: Colors.white70)),
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
            title: const Text('Waveform Segments', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Number of waveform bars to display (default: 80)', style: TextStyle(color: Colors.white70)),
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
        ],
      ),
    );
  }
}
