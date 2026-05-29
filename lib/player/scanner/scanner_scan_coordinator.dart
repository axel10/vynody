import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:vibe_flow/player/scanner/scanner_state.dart';

class ScannerScanCoordinator extends ChangeNotifier {
  ScannerRuntimeState _state = const ScannerRuntimeState.idle();
  bool _isDisposed = false;

  ScannerRuntimeState get state => _state;

  bool get isScanning => _state.isScanning;

  bool get isBackgroundPaused => _state.backgroundPaused;

  void setBackgroundPaused(bool paused) {
    if (_state.backgroundPaused == paused) {
      return;
    }
    _setState(_state.copyWith(backgroundPaused: paused));
  }

  bool isSessionCurrent(int sessionId) {
    return !_isDisposed && _state.sessionId == sessionId;
  }

  void requestRescan() {
    final nextSessionId = _state.sessionId + 1;
    _setState(
      _state.copyWith(
        sessionId: nextSessionId,
        rescanQueued: true,
        phase: _state.isScanning ? _state.phase : ScanPhase.idle,
      ),
    );
  }

  void cancelActiveScan() {
    if (!_state.isScanning) {
      return;
    }
    final nextSessionId = _state.sessionId + 1;
    _setState(
      _state.copyWith(
        phase: ScanPhase.cancelled,
        sessionId: nextSessionId,
        rescanQueued: false,
        clearActiveRootPath: true,
      ),
    );
  }

  void beginArtworkPhase(int sessionId) {
    if (!isSessionCurrent(sessionId)) {
      return;
    }
    _setState(
      _state.copyWith(
        phase: ScanPhase.scanningArtwork,
        clearLastError: true,
      ),
    );
  }

  void beginIncrementalPhase() {
    if (_state.isScanning) {
      return;
    }
    _setState(
      _state.copyWith(
        phase: ScanPhase.applyingIncrementalChanges,
        clearLastError: true,
        clearActiveRootPath: true,
      ),
    );
  }

  void setActiveRootPath(String? rootPath) {
    if (_state.activeRootPath == rootPath) {
      return;
    }
    _setState(
      _state.copyWith(
        activeRootPath: rootPath,
        clearActiveRootPath: rootPath == null,
      ),
    );
  }

  void completeIncrementalPhase() {
    if (_state.phase != ScanPhase.applyingIncrementalChanges) {
      return;
    }
    _setState(
      _state.copyWith(
        phase: ScanPhase.idle,
        clearActiveRootPath: true,
      ),
    );
  }

  Future<void> runFullScan(
    Future<void> Function(int sessionId) action,
  ) async {
    if (_state.isScanning) {
      return;
    }

    final sessionId = _state.sessionId + 1;
    _setState(
      _state.copyWith(
        phase: ScanPhase.scanningRoots,
        sessionId: sessionId,
        rescanQueued: false,
        clearActiveRootPath: true,
        clearLastError: true,
      ),
    );

    try {
      await action(sessionId);
    } catch (error) {
      _setState(
        _state.copyWith(
          phase: ScanPhase.failed,
          lastError: error,
          clearActiveRootPath: true,
        ),
      );
      rethrow;
    } finally {
      final shouldRescan = _state.rescanQueued && !_isDisposed;
      _setState(
        _state.copyWith(
          phase: ScanPhase.idle,
          rescanQueued: false,
          clearActiveRootPath: true,
        ),
      );
      if (shouldRescan) {
        await runFullScan(action);
      }
    }
  }

  void _setState(ScannerRuntimeState next) {
    if (_isDisposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
