import 'dart:math' as math;
import 'package:audio_core/audio_core.dart';
import 'package:vynody/models/music_file.dart';

/// Manages random playback and shuffle decks directly on Vynody's [MusicFile] queue.
class QueueRandomManager {
  QueueRandomManager();

  RandomPolicy? _policy;
  final List<RandomHistoryEntry> _history = [];
  int? _historyCursor;

  final List<String> _deck = [];
  int? _deckCursor;
  String? _stashedNextTrackId;
  String? _stashedForTrackId;
  String? _deckSignature;

  math.Random _random = math.Random();

  RandomPolicy? get policy => _policy;
  List<RandomHistoryEntry> get history => List.unmodifiable(_history);
  int? get historyCursor => _historyCursor;
  List<String> get currentDeck => List.unmodifiable(_deck);
  int? get deckCursor => _deckCursor;
  String? get stashedNextTrackId => _stashedNextTrackId;
  String? get stashedForTrackId => _stashedForTrackId;
  String? get deckSignature => _deckSignature;

  void setPolicy(RandomPolicy? policy) {
    if (_policy?.key == policy?.key) return;
    _policy = policy;
    _random = policy?.seed == null ? math.Random() : math.Random(policy!.seed!);
    _clearState();
  }

  void clearHistory() {
    _history.clear();
    _historyCursor = null;
  }

  void restoreState({
    required RandomPolicy? policy,
    List<RandomHistoryEntry> history = const <RandomHistoryEntry>[],
    int? historyCursor,
    List<String> deck = const <String>[],
    int? deckCursor,
    String? deckSignature,
    String? stashedNextTrackId,
    String? stashedForTrackId,
  }) {
    _policy = policy;
    final seed = policy?.seed;
    _random = seed == null ? math.Random() : math.Random(seed);

    _history
      ..clear()
      ..addAll(history);
    _historyCursor = historyCursor;

    _deck
      ..clear()
      ..addAll(deck);
    _deckCursor = deckCursor;
    _deckSignature = deckSignature;
    _stashedNextTrackId = stashedNextTrackId;
    _stashedForTrackId = stashedForTrackId;
  }

  void _clearState() {
    _history.clear();
    _historyCursor = null;
    _deck.clear();
    _deckCursor = null;
    _deckSignature = null;
    _stashedNextTrackId = null;
    _stashedForTrackId = null;
  }

  void reconcile({
    required List<MusicFile> queue,
    required MusicFile? currentTrack,
    int? currentIndex,
  }) {
    final policy = _policy;
    if (policy == null || currentTrack == null) {
      _clearState();
      return;
    }

    _trimHistory(policy.history.maxEntries);

    bool cursorSynced = false;
    if (_historyCursor != null && _historyCursor! < _history.length) {
      final entry = _history[_historyCursor!];
      if (entry.trackId == currentTrack.path &&
          (currentIndex == null || entry.trackIndex == currentIndex)) {
        cursorSynced = true;
      }
    }

    if (!cursorSynced) {
      final match = _findHistoryCursorForTrack(currentTrack.path, currentIndex);
      if (match != null) {
        _historyCursor = match;
      } else {
        final actualIndex = currentIndex ??
            queue.indexWhere((t) => t.path == currentTrack.path);
        _appendHistory(
          trackPath: currentTrack.path,
          index: actualIndex,
          policyKey: policy.key,
          limit: policy.history.maxEntries,
        );
        _historyCursor = _history.length - 1;
      }
    }

    if (policy.strategy.kind == RandomStrategyKind.fisherYates ||
        policy.strategy.kind == RandomStrategyKind.sequential) {
      final candidates = List<int>.generate(queue.length, (i) => i);
      _syncDeck(queue, candidates, currentTrack, currentIndex);
    }
  }

  int? resolveAdjacentIndex({
    required bool next,
    required List<MusicFile> queue,
    required MusicFile? currentTrack,
    bool peek = false,
  }) {
    final policy = _policy;
    if (policy == null || queue.isEmpty) return null;

    if (!next) {
      final hCursor = _historyCursor;
      if (hCursor != null && hCursor > 0) {
        final target = hCursor - 1;
        final trackIndex = _history[target].trackIndex;
        if (!peek) {
          _historyCursor = target;
          if (policy.strategy.kind == RandomStrategyKind.sequential ||
              policy.strategy.kind == RandomStrategyKind.fisherYates) {
            _deckCursor = _findCurrentDeckCursor(queue, trackIndex);
          }
        }
        return trackIndex;
      }
      return null;
    }

    if (policy.strategy.kind == RandomStrategyKind.sequential ||
        policy.strategy.kind == RandomStrategyKind.fisherYates) {
      final candidates = List<int>.generate(queue.length, (i) => i);
      if (candidates.isEmpty) return null;

      _syncDeck(queue, candidates, currentTrack, null);
      var cursor = _deckCursor ??
          _findCurrentDeckCursor(
            queue,
            currentTrack != null
                ? queue.indexWhere((s) => s.path == currentTrack.path)
                : null,
          );

      int? resultIndex;
      if (cursor != null && cursor < _deck.length - 1) {
        final target = cursor + 1;
        final trackId = _deck[target];
        final trackIdx = queue.indexWhere((t) => t.path == trackId);
        if (trackIdx >= 0) {
          if (!peek) _deckCursor = target;
          resultIndex = trackIdx;
        }
      } else {
        if (policy.exhaustion == RandomExhaustionPolicy.stop) {
          return null;
        }

        if (policy.strategy.kind == RandomStrategyKind.fisherYates) {
          final currentId = currentTrack?.path;
          final nextDeck = _shuffleCandidates(
            queue,
            candidates,
            excludeStartId: currentId,
          );

          if (!peek) {
            _deck
              ..clear()
              ..addAll(nextDeck);
            _deckCursor = _deck.isEmpty ? null : 0;
            _stashedNextTrackId = null;
            _stashedForTrackId = null;
          }

          if (nextDeck.isNotEmpty) {
            final nextId = nextDeck.first;
            final trackIdx = queue.indexWhere((t) => t.path == nextId);
            if (trackIdx >= 0) resultIndex = trackIdx;
          }
        } else {
          if (!peek) _deckCursor = 0;
          if (_deck.isNotEmpty) {
            final trackIdx = queue.indexWhere((t) => t.path == _deck.first);
            if (trackIdx >= 0) resultIndex = trackIdx;
          }
        }
      }

      if (resultIndex != null && !peek) {
        final hCursor = _historyCursor;
        if (hCursor != null &&
            hCursor < _history.length - 1 &&
            _history[hCursor + 1].trackIndex == resultIndex) {
          _historyCursor = hCursor + 1;
        } else {
          _appendHistory(
            trackPath: queue[resultIndex].path,
            index: resultIndex,
            policyKey: policy.key,
            limit: policy.history.maxEntries,
          );
          _historyCursor = _history.length - 1;
        }
      }
      return resultIndex;
    }

    final cursor = _historyCursor;
    if (cursor != null && cursor < _history.length - 1) {
      final target = cursor + 1;
      if (!peek) _historyCursor = target;
      return _history[target].trackIndex;
    }

    final candidates = List<int>.generate(queue.length, (i) => i);
    if (candidates.isEmpty) return null;

    final recentIds = _history
        .sublist(
          (_history.length - policy.history.recentWindow).clamp(
            0,
            _history.length,
          ),
        )
        .map((e) => e.trackId)
        .toSet();

    final filtered = candidates.where((idx) {
      final track = queue[idx];
      return !recentIds.contains(track.path);
    }).toList();

    final usable = filtered.isEmpty ? candidates : filtered;
    final selected = usable[_random.nextInt(usable.length)];

    if (peek) return selected;

    _appendHistory(
      trackPath: queue[selected].path,
      index: selected,
      policyKey: policy.key,
      limit: policy.history.maxEntries,
    );
    _historyCursor = _history.length - 1;

    return selected;
  }

  void _syncDeck(
    List<MusicFile> queue,
    List<int> candidates,
    MusicFile? currentTrack,
    int? currentIndex,
  ) {
    final signature = candidates.map((i) => queue[i].path).join('|');
    if (_deckSignature != signature || _deck.isEmpty) {
      _deckSignature = signature;
      final currentId = currentTrack?.path;
      final isFirstInit = _deck.isEmpty;

      _deck
        ..clear()
        ..addAll(
          _shuffleCandidates(
            queue,
            candidates,
            excludeStartId: isFirstInit ? null : currentId,
          ),
        );

      if (currentId != null && !isFirstInit) {
        _deck.remove(currentId);
        _deck.insert(0, currentId);
        _deckCursor = 0;
      } else {
        _deckCursor = _findCurrentDeckCursor(queue, currentIndex);
      }
    } else {
      _deckCursor = _findCurrentDeckCursor(queue, currentIndex);
    }
  }

  List<String> _shuffleCandidates(
    List<MusicFile> queue,
    List<int> candidates, {
    String? excludeStartId,
  }) {
    final ids = candidates.map((i) => queue[i].path).toList();
    if (ids.length <= 1) return ids;

    for (var i = ids.length - 1; i > 0; i--) {
      final n = _random.nextInt(i + 1);
      final temp = ids[i];
      ids[i] = ids[n];
      ids[n] = temp;
    }

    if (excludeStartId != null && ids.first == excludeStartId) {
      final swapIdx = 1 + _random.nextInt(ids.length - 1);
      final temp = ids[0];
      ids[0] = ids[swapIdx];
      ids[swapIdx] = temp;
    }

    return ids;
  }

  int? _findCurrentDeckCursor(List<MusicFile> queue, int? index) {
    if (index == null || index < 0 || index >= queue.length) return null;
    final trackId = queue[index].path;
    final pos = _deck.indexOf(trackId);
    return pos >= 0 ? pos : null;
  }

  int? _findHistoryCursorForTrack(String trackId, int? index) {
    for (var i = _history.length - 1; i >= 0; i--) {
      final entry = _history[i];
      if (entry.trackId == trackId &&
          (index == null || entry.trackIndex == index)) {
        return i;
      }
    }
    return null;
  }

  void _appendHistory({
    required String trackPath,
    required int index,
    required String policyKey,
    required int limit,
  }) {
    if (_historyCursor != null && _historyCursor! < _history.length - 1) {
      _history.removeRange(_historyCursor! + 1, _history.length);
    }

    _history.add(
      RandomHistoryEntry(
        trackId: trackPath,
        playlistId: 'vynody_queue',
        trackIndex: index,
        policyKey: policyKey,
        generatedAt: DateTime.now(),
      ),
    );
    _trimHistory(limit);
  }

  void _trimHistory(int limit) {
    if (limit <= 0) return;
    while (_history.length > limit) {
      _history.removeAt(0);
      if (_historyCursor != null) {
        _historyCursor = math.max(0, _historyCursor! - 1);
      }
    }
  }
}
