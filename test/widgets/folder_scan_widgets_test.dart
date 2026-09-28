import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/widgets/folder_scan_widgets.dart';

class MockScannerService extends ScannerService {
  bool _mockIsScanning = false;

  @override
  bool get isScanning => _mockIsScanning;

  void setScanning(bool scanning) {
    _mockIsScanning = scanning;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ScanProgressInfoNotifier builds and updates without uninitialized state error',
      (tester) async {
    final mockScanner = MockScannerService();

    // Start with scanning = true to specifically verify uninitialized build handling
    mockScanner.setScanning(true);

    final container = ProviderContainer(
      overrides: [
        scannerServiceProvider.overrideWith((ref) => mockScanner),
      ],
    );
    addTearDown(container.dispose);

    // Initial read during build when scanning is true
    final initialInfo = container.read(scanProgressInfoProvider);
    expect(initialInfo.isScanning, isTrue);

    // Test rendering the FolderScanSpinner widget
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: FolderScanSpinner(),
          ),
        ),
      ),
    );

    expect(find.byType(FolderScanSpinner), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Stop scanning
    mockScanner.setScanning(false);
    await tester.pump();

    final stoppedInfo = container.read(scanProgressInfoProvider);
    expect(stoppedInfo.isScanning, isFalse);
  });
}
