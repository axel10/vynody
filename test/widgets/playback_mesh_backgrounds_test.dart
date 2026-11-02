import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/dynamic_mesh_background.dart';

void main() {
  testWidgets('动态流变 与 动态流变 v2 都能渲染', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);

    const music = MusicFile(
      path: '/demo/a.mp3',
      name: 'a.mp3',
      title: 'A',
      artist: 'B',
      album: 'C',
    );

    // 同色相 4 色，避免触发主色重算（那样会去读真实 AudioService）。
    const palette = <String, Color>{
      'mesh1': Color(0xFF101828),
      'mesh2': Color(0xFF101A2C),
      'mesh3': Color(0xFF121C30),
      'mesh4': Color(0xFF14203A),
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
          isProUnlockedProvider.overrideWith((ref) => true),
          audioCurrentMusicProvider.overrideWithValue(music),
          audioCurrentThemeColorsMapProvider.overrideWithValue(palette),
          audioDynamicStartColorProvider.overrideWithValue(
            const Color(0xFF101828),
          ),
          audioDynamicEndColorProvider.overrideWithValue(
            const Color(0xFF14203A),
          ),
        ],
        child: const MaterialApp(
          home: Stack(
            children: [DynamicMeshBackground(), MeshFlowBackground()],
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byType(DynamicMeshBackground), findsOneWidget);
    expect(find.byType(MeshFlowBackground), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
