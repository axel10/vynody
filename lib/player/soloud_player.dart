import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

import 'base_player.dart';

class SoLoudPlayer implements BasePlayer {
  final SoLoud _soLoud = SoLoud.instance;

  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  final StreamController<int> _indexController =
      StreamController<int>.broadcast();

  final List<String> _playlist = [];
  AudioSource? _currentSource;
  SoundHandle? _currentHandle;
  Timer? _positionTimer;

  bool _initialized = false;
  bool _isPlaying = false;
  bool _isSwitchingTrack = false;
  int _currentIndex = -1;
  Duration _duration = Duration.zero;
  double _volume = 100.0;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<double> get volumeStream => _volumeController.stream;

  @override
  Stream<int> get indexStream => _indexController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _soLoud.init();
    _initialized = true;
    _soLoud.setGlobalVolume(_volume / 100);
    _emitState();
  }

  @override
  Future<void> playFile(String path) async {
    await playPlaylist([path], initialIndex: 0);
  }

  @override
  Future<void> playPlaylist(List<String> paths, {int initialIndex = 0}) async {
    if (paths.isEmpty) return;
    await _ensureInitialized();

    _playlist
      ..clear()
      ..addAll(paths);

    final safeIndex = initialIndex.clamp(0, paths.length - 1);
    await _playAtIndex(safeIndex, resume: true);
  }

  @override
  Future<void> addToPlaylist(List<String> paths) async {
    if (paths.isEmpty) return;
    await _ensureInitialized();

    final wasEmpty = _playlist.isEmpty;
    _playlist.addAll(paths);

    if (wasEmpty) {
      await _playAtIndex(0, resume: true);
    }
  }

  @override
  Future<void> removeFromPlaylist(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    await _ensureInitialized();

    final removingCurrent = index == _currentIndex;
    _playlist.removeAt(index);

    if (_playlist.isEmpty) {
      await clearPlaylist();
      return;
    }

    if (removingCurrent) {
      final nextIndex = index >= _playlist.length
          ? _playlist.length - 1
          : index;
      await _playAtIndex(nextIndex, resume: _isPlaying);
      return;
    }

    if (index < _currentIndex) {
      _currentIndex -= 1;
      _indexController.add(_currentIndex);
    }
  }

  @override
  Future<void> clearPlaylist() async {
    await _ensureInitialized();

    _playlist.clear();
    _currentIndex = -1;
    _duration = Duration.zero;
    _positionTimer?.cancel();
    await _stopAndDisposeCurrent();

    _isPlaying = false;
    _indexController.add(_currentIndex);
    _durationController.add(Duration.zero);
    _positionController.add(Duration.zero);
    _playingController.add(false);
  }

  @override
  Future<void> next() async {
    await _ensureInitialized();
    if (_currentIndex < 0 || _currentIndex >= _playlist.length - 1) return;
    await _playAtIndex(_currentIndex + 1, resume: true);
  }

  @override
  Future<void> previous() async {
    await _ensureInitialized();
    if (_currentIndex <= 0) return;
    await _playAtIndex(_currentIndex - 1, resume: true);
  }

  @override
  Future<void> togglePlay() async {
    await _ensureInitialized();
    final handle = _currentHandle;
    if (handle == null || !_soLoud.getIsValidVoiceHandle(handle)) return;

    _isPlaying = !_isPlaying;
    _soLoud.setPause(handle, !_isPlaying);
    _playingController.add(_isPlaying);
  }

  @override
  Future<void> seek(Duration position) async {
    await _ensureInitialized();
    final handle = _currentHandle;
    if (handle == null || !_soLoud.getIsValidVoiceHandle(handle)) return;
    _soLoud.seek(handle, position);
    _positionController.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _ensureInitialized();
    _volume = volume.clamp(0.0, 100.0);
    _soLoud.setGlobalVolume(_volume / 100);

    final handle = _currentHandle;
    if (handle != null && _soLoud.getIsValidVoiceHandle(handle)) {
      _soLoud.setVolume(handle, _volume / 100);
    }
    _volumeController.add(_volume);
  }

  @override
  Future<void> dispose() async {
    _positionTimer?.cancel();
    await _stopAndDisposeCurrent();
    if (_initialized) {
      _soLoud.deinit();
      _initialized = false;
    }
    await _playingController.close();
    await _positionController.close();
    await _durationController.close();
    await _volumeController.close();
    await _indexController.close();
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  Future<void> _playAtIndex(int index, {required bool resume}) async {
    if (index < 0 || index >= _playlist.length) return;
    await _ensureInitialized();

    _isSwitchingTrack = true;
    try {
      await _stopAndDisposeCurrent();

      _currentIndex = index;
      _indexController.add(_currentIndex);
      var path = p.normalize(_playlist[index]).replaceAll(r'\', '/');
      final source = await _soLoud.loadFile(path);
      _currentSource = source;
      _duration = _soLoud.getLength(source);
      _durationController.add(_duration);

      final handle = await _soLoud.play(source, volume: _volume / 100);
      _currentHandle = handle;
      _isPlaying = resume;
      _soLoud.setPause(handle, !resume);
      _playingController.add(_isPlaying);
      _positionController.add(Duration.zero);

      _startPositionTicker();
    } finally {
      _isSwitchingTrack = false;
    }
  }

  void _startPositionTicker() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final handle = _currentHandle;
      if (handle == null) return;

      if (!_soLoud.getIsValidVoiceHandle(handle)) {
        if (_isSwitchingTrack) return;
        _onTrackEnded();
        return;
      }

      final position = _soLoud.getPosition(handle);
      _positionController.add(position);
    });
  }

  void _onTrackEnded() {
    if (_isSwitchingTrack) return;
    _isPlaying = false;
    _playingController.add(false);

    final hasNext = _currentIndex >= 0 && _currentIndex < _playlist.length - 1;
    if (hasNext) {
      unawaited(_playAtIndex(_currentIndex + 1, resume: true));
    } else {
      _positionController.add(_duration);
    }
  }

  Future<void> _stopAndDisposeCurrent() async {
    final handle = _currentHandle;
    final source = _currentSource;
    _currentHandle = null;
    _currentSource = null;

    if (handle != null && _soLoud.getIsValidVoiceHandle(handle)) {
      await _soLoud.stop(handle);
    }
    if (source != null) {
      await _soLoud.disposeSource(source);
    }
  }

  void _emitState() {
    _playingController.add(_isPlaying);
    _positionController.add(Duration.zero);
    _durationController.add(_duration);
    _volumeController.add(_volume);
    _indexController.add(_currentIndex);
  }
}
