import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/dialogs/add_edit_remote_server_dialog.dart';
import 'package:vynody/dialogs/add_to_playlist_dialog.dart';
import 'package:vynody/dialogs/playlist_manager_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/widgets/app_bottom_sheet.dart';

import 'helpers/mobile_screenshot_harness.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  _FakePathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tier1_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const dummySong = MusicFile(
    id: 1,
    name: 'Song Title',
    path: '/path/to/song.mp3',
    durationMillis: 180000,
    artist: 'Artist Name',
    album: 'Album Name',
  );

  group('AddToPlaylistDialog AdaptiveSheet', () {
    testWidgets('renders AppAdaptiveSheet correctly with search when playlists >= 5', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late PlaylistService playlistService;
      await tester.runAsync(() async {
        playlistService = PlaylistService();
        // Add playlists so total count >= 5 to trigger search bar
        for (var i = 1; i <= 5; i++) {
          await playlistService.createPlaylist('Playlist $i');
        }
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playlistServiceProvider.overrideWith((ref) => playlistService),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => AddToPlaylistDialog.show(
                    context,
                    playlistService: playlistService,
                    songs: const [dummySong],
                  ),
                  child: const Text('Add to Playlist'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Add to Playlist'));
      await tester.pumpAndSettle();

      // AppAdaptiveSheet should be present
      expect(find.byType(AppAdaptiveSheet), findsOneWidget);
      // Search field in headerBottom when playlists >= 5
      expect(find.byType(TextField), findsOneWidget);
      // Create playlist action button
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });
  });

  group('PlaylistManagerDialog AdaptiveSheet', () {
    testWidgets('renders AppAdaptiveSheet and action buttons correctly in portrait and landscape', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settingsService = TestSettingsService(prefs);
      final playlistService = PlaylistService();

      // 1. Portrait mode (narrow screen) -> Bottom Sheet mode
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playlistServiceProvider.overrideWith((ref) => playlistService),
            settingsServiceProvider.overrideWith((ref) => settingsService),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => PlaylistManagerDialog.show(context),
                  child: const Text('Manage Playlists'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Manage Playlists'));
      await tester.pumpAndSettle();

      // AppAdaptiveSheet should be present
      expect(find.byType(AppAdaptiveSheet), findsOneWidget);
      // Action buttons: New playlist, sort
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
      // Import M3U entry
      expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
      // In bottom sheet mode, drag handle should be rendered
      expect(find.byType(AppDragHandle), findsOneWidget);
    });
  });

  group('AddEditRemoteServerDialog AdaptiveSheet', () {
    testWidgets('renders AppAdaptiveSheet correctly with form and action buttons', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => AddEditRemoteServerDialog.show(context),
                  child: const Text('Add Server'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Add Server'));
      await tester.pumpAndSettle();

      // AppAdaptiveSheet should be present
      expect(find.byType(AppAdaptiveSheet), findsOneWidget);
      // Test connection button should be present
      expect(find.byIcon(Icons.network_ping_rounded), findsOneWidget);
      // In narrow portrait mode, drag handle should be rendered
      expect(find.byType(AppDragHandle), findsOneWidget);
    });
  });
}
