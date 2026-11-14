import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/scanner/scanner_scan_coordinator.dart';
import 'package:vynody/player/scanner/scanner_state.dart';

void main() {
  group('ScannerScanCoordinator', () {
    test('normal full scan lifecycle transitions idle -> scanningRoots -> scanningArtwork -> idle', () async {
      final coordinator = ScannerScanCoordinator();
      final phases = <ScanPhase>[];
      coordinator.addListener(() {
        phases.add(coordinator.state.phase);
      });

      await coordinator.runFullScan((sessionId) async {
        expect(coordinator.isScanning, isTrue);
        expect(coordinator.isSessionCurrent(sessionId), isTrue);
        coordinator.setActiveRootPath('/music/a');
        expect(coordinator.state.activeRootPath, '/music/a');

        coordinator.beginArtworkPhase(sessionId);
        expect(coordinator.state.phase, ScanPhase.scanningArtwork);
      });

      expect(coordinator.isScanning, isFalse);
      expect(coordinator.state.phase, ScanPhase.idle);
      expect(coordinator.state.activeRootPath, isNull);
      expect(
        phases,
        containsAllInOrder([
          ScanPhase.scanningRoots,
          ScanPhase.scanningArtwork,
          ScanPhase.idle,
        ]),
      );
      coordinator.dispose();
    });

    test('requestRescan during active scan invalidates sessionId and chains a second scan', () async {
      final coordinator = ScannerScanCoordinator();
      final gate = Completer<void>();
      final seenSessions = <int>[];
      var firstSessionValidAfterRescan = true;

      final scanFuture = coordinator.runFullScan((sessionId) async {
        seenSessions.add(sessionId);
        if (seenSessions.length == 1) {
          await gate.future;
          firstSessionValidAfterRescan = coordinator.isSessionCurrent(sessionId);
        }
      });

      // Wait until the first scan has started.
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.isScanning, isTrue);

      coordinator.requestRescan();
      expect(coordinator.state.rescanQueued, isTrue);

      gate.complete();
      await scanFuture;

      expect(firstSessionValidAfterRescan, isFalse);
      expect(seenSessions, [1, 3]);
      expect(coordinator.state.phase, ScanPhase.idle);
      expect(coordinator.state.rescanQueued, isFalse);
      coordinator.dispose();
    });

    test('cancelActiveScan sets cancelled phase, clears queue, and invalidates session', () async {
      final coordinator = ScannerScanCoordinator();
      final gate = Completer<void>();
      var sessionValidAfterCancel = true;

      final scanFuture = coordinator.runFullScan((sessionId) async {
        coordinator.setActiveRootPath('/music/root');
        await gate.future;
        sessionValidAfterCancel = coordinator.isSessionCurrent(sessionId);
      });

      await Future<void>.delayed(Duration.zero);
      coordinator.requestRescan();
      coordinator.cancelActiveScan();

      expect(coordinator.state.phase, ScanPhase.cancelled);
      expect(coordinator.state.rescanQueued, isFalse);
      expect(coordinator.state.activeRootPath, isNull);

      gate.complete();
      await scanFuture;

      expect(sessionValidAfterCancel, isFalse);
      expect(coordinator.state.phase, ScanPhase.idle);
      coordinator.dispose();
    });

    test('failed scan records lastError, rethrows, and resets phase to idle', () async {
      final coordinator = ScannerScanCoordinator();
      final phases = <ScanPhase>[];
      coordinator.addListener(() {
        phases.add(coordinator.state.phase);
      });

      await expectLater(
        () => coordinator.runFullScan((_) async {
          throw StateError('disk io failure');
        }),
        throwsA(isA<StateError>()),
      );

      expect(phases, containsAllInOrder([ScanPhase.scanningRoots, ScanPhase.failed, ScanPhase.idle]));
      expect(coordinator.state.phase, ScanPhase.idle);
      expect(coordinator.state.lastError, isA<StateError>());
      coordinator.dispose();
    });

    test('incremental phase is ignored during full scan and completes when idle', () async {
      final coordinator = ScannerScanCoordinator();
      final gate = Completer<void>();

      final scanFuture = coordinator.runFullScan((_) => gate.future);
      await Future<void>.delayed(Duration.zero);

      coordinator.beginIncrementalPhase();
      expect(coordinator.state.phase, ScanPhase.scanningRoots);

      gate.complete();
      await scanFuture;

      coordinator.beginIncrementalPhase();
      expect(coordinator.state.phase, ScanPhase.applyingIncrementalChanges);
      coordinator.completeIncrementalPhase();
      expect(coordinator.state.phase, ScanPhase.idle);
      coordinator.dispose();
    });

    test('setBackgroundPaused toggles state and notifies only on change', () {
      final coordinator = ScannerScanCoordinator();
      var notifyCount = 0;
      coordinator.addListener(() => notifyCount++);

      coordinator.setBackgroundPaused(false);
      expect(notifyCount, 0);

      coordinator.setBackgroundPaused(true);
      expect(coordinator.isBackgroundPaused, isTrue);
      expect(notifyCount, 1);

      coordinator.setBackgroundPaused(true);
      expect(notifyCount, 1);
      coordinator.dispose();
    });
  });
}
