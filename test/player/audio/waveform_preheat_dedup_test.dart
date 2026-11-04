import 'dart:io';
import 'dart:typed_data';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/playback_queue_processor.dart';
import 'package:vynody/player/audio/waveform_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/settings/settings_service.dart';

/// 回归：起播瞬间「播放侧正在整首解码当前曲」时，队列后台预热不能对同一首再解一遍。
///
/// 两路并发解同一文件会互相抢 IO（外接盘上尤其明显），把后续曲目的预热整体
/// 推后一整首的时间。守的是 [PlaybackQueueProcessor.isWaveformReading] 这道门。
class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String appSupportPath;
  _FakePathProvider(this.appSupportPath);

  @override
  Future<String?> getApplicationSupportPath() async => appSupportPath;
  @override
  Future<String?> getTemporaryPath() async => appSupportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MetadataDatabase db;
  late AudioCoreController player;
  late SettingsService settingsService;
  late WaveformService waveformService;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('waveform_preheat_dedup_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    db = MetadataDatabase();
    await db.ensureOpen();
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'remote_prefetch_count': 0});
    final prefs = await SharedPreferences.getInstance();
    settingsService = SettingsService(prefs);
    player = AudioCoreController();
    waveformService = WaveformService(db: db, player: player);
  });

  /// 当前曲已经有封面和主题色，只缺波形：这样「进不进入重活」只取决于波形这一项。
  Future<String> seedCurrentSong() async {
    final path = '${tempDir.path}/current_${DateTime.now().microsecondsSinceEpoch}.mp3';
    await File(path).writeAsString('dummy current content');
    await db.insertOrUpdateSong(
      SongMetadata(
        path: path,
        title: 'Current',
        artist: 'Artist',
        album: 'Album',
        duration: 200000,
        thumbnailPath: '${tempDir.path}/thumb_current.jpg',
        artworkPath: '${tempDir.path}/art_current.jpg',
        themeColorsBlob: Uint8List.fromList(<int>[1, 2, 3, 4]),
      ),
    );
    return path;
  }

  /// 相邻曲目缺主题色，用来证明跳过只作用于当前曲，而不是整轮都不干活。
  Future<String> seedNeighbourSong() async {
    final path = '${tempDir.path}/neighbour_${DateTime.now().microsecondsSinceEpoch}.mp3';
    await File(path).writeAsString('dummy neighbour content');
    await db.insertOrUpdateSong(
      SongMetadata(
        path: path,
        title: 'Neighbour',
        artist: 'Artist',
        album: 'Album',
        duration: 200000,
        thumbnailPath: '${tempDir.path}/thumb_neighbour.jpg',
      ),
    );
    return path;
  }

  Future<List<String>> runQueue({
    required String currentPath,
    required String neighbourPath,
    bool Function(String path)? isWaveformReading,
  }) async {
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      final processor = PlaybackQueueProcessor(
        db: db,
        player: player,
        settingsService: settingsService,
        waveformService: waveformService,
        isWaveformReading: isWaveformReading,
      );
      await processor.processQueue(
        playlist: [
          MusicFile(path: currentPath, name: 'current.mp3'),
          MusicFile(path: neighbourPath, name: 'neighbour.mp3'),
        ],
        currentFilePath: currentPath,
        onUpdate: (path, updates) {},
      );
    } finally {
      debugPrint = originalDebugPrint;
    }
    return logs
        .where((line) => line.contains('Thumbnail/Colors/Waveform'))
        .toList(growable: false);
  }

  bool touched(List<String> logs, String path) =>
      logs.any((line) => line.endsWith(path));

  test('播放侧未在解码时，当前曲的波形由后台预热负责', () async {
    final current = await seedCurrentSong();
    final neighbour = await seedNeighbourSong();

    final logs = await runQueue(
      currentPath: current,
      neighbourPath: neighbour,
    );

    expect(touched(logs, current), isTrue);
    expect(touched(logs, neighbour), isTrue);
  });

  test('播放侧正在解码当前曲时，后台预热跳过这一首、其余曲目照常', () async {
    final current = await seedCurrentSong();
    final neighbour = await seedNeighbourSong();
    final queried = <String>[];

    final logs = await runQueue(
      currentPath: current,
      neighbourPath: neighbour,
      isWaveformReading: (path) {
        queried.add(path);
        return path == current;
      },
    );

    expect(queried, contains(current)); // 门确实被问了
    expect(touched(logs, current), isFalse); // 但这一首不再重复解码
    expect(touched(logs, neighbour), isTrue); // 相邻曲目不受影响
  });
}
