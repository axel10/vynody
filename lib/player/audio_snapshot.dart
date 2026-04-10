import 'package:audio_core/audio_core.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../models/music_file.dart';

class AudioSnapshot {
  static final DeepCollectionEquality _deepEquality = DeepCollectionEquality();

  final bool isPlaying;
  final bool isTransitioning;
  final bool? isLastActionNext;
  final MusicFile? currentMusic;
  final Duration position;
  final Duration duration;
  final double volume;
  final bool isMuted;
  final List<MusicFile> playbackQueue;
  final int currentIndex;
  final bool isRandomMode;
  final bool isShuffleRandomMode;
  final PlaylistMode playbackMode;
  final EqualizerConfig equalizerConfig;
  final VisualizerOptimizationOptions currentVisualizerOptions;
  final List<MusicFile> randomHistory;
  final List<MusicFile> randomQueue;
  final int? historyCursor;
  final int? deckCursor;
  final bool isVisualizerEnabled;
  final Color? dynamicStartColor;
  final Color? dynamicEndColor;
  final Map<String, Color> currentThemeColorsMap;
  final bool isLyricsActive;
  final double progress;

  AudioSnapshot({
    required this.isPlaying,
    required this.isTransitioning,
    required this.isLastActionNext,
    required this.currentMusic,
    required this.position,
    required this.duration,
    required this.volume,
    required this.isMuted,
    required List<MusicFile> playbackQueue,
    required this.currentIndex,
    required this.isRandomMode,
    required this.isShuffleRandomMode,
    required this.playbackMode,
    required this.equalizerConfig,
    required this.currentVisualizerOptions,
    required List<MusicFile> randomHistory,
    required List<MusicFile> randomQueue,
    required this.historyCursor,
    required this.deckCursor,
    required this.isVisualizerEnabled,
    required this.dynamicStartColor,
    required this.dynamicEndColor,
    required Map<String, Color> currentThemeColorsMap,
    required this.isLyricsActive,
  }) : playbackQueue = List<MusicFile>.unmodifiable(playbackQueue),
       randomHistory = List<MusicFile>.unmodifiable(randomHistory),
       randomQueue = List<MusicFile>.unmodifiable(randomQueue),
       currentThemeColorsMap = Map<String, Color>.unmodifiable(
         currentThemeColorsMap,
       ),
       progress = duration.inMilliseconds > 0
           ? position.inMilliseconds / duration.inMilliseconds
           : 0.0;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AudioSnapshot &&
            isPlaying == other.isPlaying &&
            isTransitioning == other.isTransitioning &&
            isLastActionNext == other.isLastActionNext &&
            currentMusic == other.currentMusic &&
            position == other.position &&
            duration == other.duration &&
            volume == other.volume &&
            isMuted == other.isMuted &&
            _deepEquality.equals(playbackQueue, other.playbackQueue) &&
            currentIndex == other.currentIndex &&
            isRandomMode == other.isRandomMode &&
            isShuffleRandomMode == other.isShuffleRandomMode &&
            playbackMode == other.playbackMode &&
            equalizerConfig == other.equalizerConfig &&
            currentVisualizerOptions == other.currentVisualizerOptions &&
            _deepEquality.equals(randomHistory, other.randomHistory) &&
            _deepEquality.equals(randomQueue, other.randomQueue) &&
            historyCursor == other.historyCursor &&
            deckCursor == other.deckCursor &&
            isVisualizerEnabled == other.isVisualizerEnabled &&
            dynamicStartColor == other.dynamicStartColor &&
            dynamicEndColor == other.dynamicEndColor &&
            isLyricsActive == other.isLyricsActive &&
            _deepEquality.equals(
              currentThemeColorsMap,
              other.currentThemeColorsMap,
            );
  }

  @override
  int get hashCode => Object.hashAll([
    isPlaying,
    isTransitioning,
    isLastActionNext,
    currentMusic,
    position,
    duration,
    volume,
    isMuted,
    _deepEquality.hash(playbackQueue),
    currentIndex,
    isRandomMode,
    isShuffleRandomMode,
    playbackMode,
    equalizerConfig,
    currentVisualizerOptions,
    _deepEquality.hash(randomHistory),
    _deepEquality.hash(randomQueue),
    historyCursor,
    deckCursor,
    isVisualizerEnabled,
    dynamicStartColor,
    dynamicEndColor,
    isLyricsActive,
    _deepEquality.hash(currentThemeColorsMap),
  ]);
}
