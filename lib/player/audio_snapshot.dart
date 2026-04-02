import 'dart:typed_data';

import 'package:audio_core/audio_core.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../models/music_file.dart';
import 'lyrics_service.dart';

class AudioSnapshot {
  static final DeepCollectionEquality _deepEquality = DeepCollectionEquality();

  final bool isPlaying;
  final bool isTransitioning;
  final bool? isLastActionNext;
  final String? currentFilePath;
  final String? currentFileName;
  final String? currentArtist;
  final String? currentAlbum;
  final int? currentSongId;
  final List<double> currentWaveform;
  final Uint8List? currentArtworkBytes;
  final String? currentArtworkPath;
  final String? thumbnailPath;
  final Uint8List? backgroundArtworkBytes;
  final String? backgroundArtworkPath;
  final int? artworkWidth;
  final int? artworkHeight;
  final Duration position;
  final Duration duration;
  final double volume;
  final bool isMuted;
  final List<MusicFile> playbackQueue;
  final int currentIndex;
  final bool isRandomMode;
  final bool isShuffleRandomMode;
  final PlaylistMode playbackMode;
  final int? historyCursor;
  final int? deckCursor;
  final bool isVisualizerEnabled;
  final Color? dynamicStartColor;
  final Color? dynamicEndColor;
  final Map<String, Color> currentThemeColorsMap;
  final bool isLyricsLoading;
  final bool hasLyrics;
  final bool isLyricsSynced;
  final List<LyricLine> currentLyricsLines;
  final String currentLyricsText;
  final String? currentLyricsTitle;
  final double progress;

  AudioSnapshot({
    required this.isPlaying,
    required this.isTransitioning,
    required this.isLastActionNext,
    required this.currentFilePath,
    required this.currentFileName,
    required this.currentArtist,
    required this.currentAlbum,
    required this.currentSongId,
    required List<double> currentWaveform,
    required this.currentArtworkBytes,
    required this.currentArtworkPath,
    required this.thumbnailPath,
    required this.backgroundArtworkBytes,
    required this.backgroundArtworkPath,
    required this.artworkWidth,
    required this.artworkHeight,
    required this.position,
    required this.duration,
    required this.volume,
    required this.isMuted,
    required List<MusicFile> playbackQueue,
    required this.currentIndex,
    required this.isRandomMode,
    required this.isShuffleRandomMode,
    required this.playbackMode,
    required this.historyCursor,
    required this.deckCursor,
    required this.isVisualizerEnabled,
    required this.dynamicStartColor,
    required this.dynamicEndColor,
    required Map<String, Color> currentThemeColorsMap,
    required this.isLyricsLoading,
    required this.hasLyrics,
    required this.isLyricsSynced,
    required List<LyricLine> currentLyricsLines,
    required this.currentLyricsText,
    required this.currentLyricsTitle,
  }) : currentWaveform = List<double>.unmodifiable(currentWaveform),
       playbackQueue = List<MusicFile>.unmodifiable(playbackQueue),
       currentLyricsLines = List<LyricLine>.unmodifiable(currentLyricsLines),
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
            currentFilePath == other.currentFilePath &&
            currentFileName == other.currentFileName &&
            currentArtist == other.currentArtist &&
            currentAlbum == other.currentAlbum &&
            currentSongId == other.currentSongId &&
            _deepEquality.equals(currentWaveform, other.currentWaveform) &&
            _deepEquality.equals(
              currentArtworkBytes,
              other.currentArtworkBytes,
            ) &&
            _deepEquality.equals(
              backgroundArtworkBytes,
              other.backgroundArtworkBytes,
            ) &&
            backgroundArtworkPath == other.backgroundArtworkPath &&
            currentArtworkPath == other.currentArtworkPath &&
            artworkWidth == other.artworkWidth &&
            artworkHeight == other.artworkHeight &&
            position == other.position &&
            duration == other.duration &&
            volume == other.volume &&
            isMuted == other.isMuted &&
            _deepEquality.equals(playbackQueue, other.playbackQueue) &&
            currentIndex == other.currentIndex &&
            isRandomMode == other.isRandomMode &&
            isShuffleRandomMode == other.isShuffleRandomMode &&
            playbackMode == other.playbackMode &&
            historyCursor == other.historyCursor &&
            deckCursor == other.deckCursor &&
            isVisualizerEnabled == other.isVisualizerEnabled &&
            dynamicStartColor == other.dynamicStartColor &&
            dynamicEndColor == other.dynamicEndColor &&
            isLyricsLoading == other.isLyricsLoading &&
            hasLyrics == other.hasLyrics &&
            isLyricsSynced == other.isLyricsSynced &&
            _deepEquality.equals(
              currentLyricsLines,
              other.currentLyricsLines,
            ) &&
            currentLyricsText == other.currentLyricsText &&
            currentLyricsTitle == other.currentLyricsTitle &&
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
    currentFilePath,
    currentFileName,
    currentArtist,
    currentAlbum,
    currentSongId,
    _deepEquality.hash(currentWaveform),
    _deepEquality.hash(currentArtworkBytes),
    _deepEquality.hash(backgroundArtworkBytes),
    backgroundArtworkPath,
    currentArtworkPath,
    artworkWidth,
    artworkHeight,
    position,
    duration,
    volume,
    isMuted,
    _deepEquality.hash(playbackQueue),
    currentIndex,
    isRandomMode,
    isShuffleRandomMode,
    playbackMode,
    historyCursor,
    deckCursor,
    isVisualizerEnabled,
    dynamicStartColor,
    dynamicEndColor,
    isLyricsLoading,
    hasLyrics,
    isLyricsSynced,
    _deepEquality.hash(currentLyricsLines),
    currentLyricsText,
    currentLyricsTitle,
    _deepEquality.hash(currentThemeColorsMap),
  ]);
}
