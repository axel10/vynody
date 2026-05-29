enum ScanPhase {
  idle,
  scanningRoots,
  scanningArtwork,
  applyingIncrementalChanges,
  cancelled,
  failed,
}

class ScannerRuntimeState {
  const ScannerRuntimeState({
    required this.phase,
    required this.sessionId,
    required this.rescanQueued,
    required this.backgroundPaused,
    this.activeRootPath,
    this.lastError,
  });

  const ScannerRuntimeState.idle({
    int sessionId = 0,
    bool backgroundPaused = false,
  }) : this(
         phase: ScanPhase.idle,
         sessionId: sessionId,
         rescanQueued: false,
         backgroundPaused: backgroundPaused,
       );

  final ScanPhase phase;
  final int sessionId;
  final bool rescanQueued;
  final bool backgroundPaused;
  final String? activeRootPath;
  final Object? lastError;

  bool get isScanning =>
      phase == ScanPhase.scanningRoots ||
      phase == ScanPhase.scanningArtwork ||
      phase == ScanPhase.applyingIncrementalChanges;

  ScannerRuntimeState copyWith({
    ScanPhase? phase,
    int? sessionId,
    bool? rescanQueued,
    bool? backgroundPaused,
    String? activeRootPath,
    bool clearActiveRootPath = false,
    Object? lastError,
    bool clearLastError = false,
  }) {
    return ScannerRuntimeState(
      phase: phase ?? this.phase,
      sessionId: sessionId ?? this.sessionId,
      rescanQueued: rescanQueued ?? this.rescanQueued,
      backgroundPaused: backgroundPaused ?? this.backgroundPaused,
      activeRootPath: clearActiveRootPath
          ? null
          : (activeRootPath ?? this.activeRootPath),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}
