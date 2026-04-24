// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Pure Player';

  @override
  String get systemMediaLibrary => 'System Media Library';

  @override
  String get scanningDirectory => 'Scanning directory...';

  @override
  String filesPreprocessed(Object count) {
    return 'Preprocessed $count';
  }

  @override
  String filesDiscovered(Object count) {
    return 'Discovered $count';
  }

  @override
  String filesFullyProcessed(Object count) {
    return 'Fully processed $count';
  }

  @override
  String get directoryAddedSuccess => 'Directory added successfully';

  @override
  String get directoryAddedNoMusic =>
      'Directory added, but no playable audio files found';

  @override
  String get scanDirectory => 'Scan Directory';

  @override
  String get sort => 'Sort';

  @override
  String get addRootDirectory => 'Add Root Directory';

  @override
  String get goBack => 'Go Back';

  @override
  String get noMediaLibraryPermission => 'No media library access permission';

  @override
  String get grantPermission => 'Grant Permission';

  @override
  String get needPermissionToScan => 'Permission required to scan local music';

  @override
  String get rebuildTagDatabase => 'Rebuild Tag Database';

  @override
  String get rebuildDatabase => 'Rebuild Database';

  @override
  String get confirmRebuildDatabase =>
      'Are you sure you want to manually refresh all song tag information? This may take some time to reload covers and metadata.';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get rebuildingDatabase => 'Rebuilding song tag database...';

  @override
  String get sortBy => 'Sort By';

  @override
  String get sortScope => 'Scope';

  @override
  String get sortOrder => 'Sort Order';

  @override
  String get title => 'Title';

  @override
  String get fileName => 'File Name';

  @override
  String get trackNumber => 'Track Number';

  @override
  String get ascending => 'Ascending';

  @override
  String get descending => 'Descending';

  @override
  String get currentFolderScope => 'Current Folder';

  @override
  String get globalScope => 'Global';

  @override
  String get visualizerSettings => 'Playback Page Settings';

  @override
  String get algorithm => 'Spectrum';

  @override
  String get appearance => 'Appearance';

  @override
  String get spectrumAppearanceGroup => 'Spectrum Appearance';

  @override
  String get spectrumAdvancedOptions => 'Spectrum Advanced Options';

  @override
  String get resetAlgorithm => 'Reset Algorithm';

  @override
  String get resetAppearance => 'Reset Appearance';

  @override
  String get smoothing => 'Smoothing';

  @override
  String get gravity => 'Gravity';

  @override
  String get logScale => 'Log Scale';

  @override
  String get contrast => 'Contrast';

  @override
  String get normalization => 'Normalization';

  @override
  String get multiplier => 'Multiplier';

  @override
  String get skipHighFrequency => 'Skip High Frequency';

  @override
  String get frequencyGroups => 'Frequency Groups';

  @override
  String get aggregationMode => 'Aggregation Mode';

  @override
  String get opacity => 'Opacity';

  @override
  String get enableGradient => 'Enable Gradient';

  @override
  String get startColor => 'Start Color';

  @override
  String get endColor => 'End Color';

  @override
  String get gradientRangeStop1 => 'Gradient Range Stop 1';

  @override
  String get gradientRangeStop2 => 'Gradient Range Stop 2';

  @override
  String get gradientRepeatMode => 'Gradient Repeat Mode';

  @override
  String get color => 'Color';

  @override
  String get followCoverColor => 'Follow Cover Color';

  @override
  String get selectColor => 'Select Color';

  @override
  String get volume => 'Volume';

  @override
  String get clearQueue => 'Clear Queue';

  @override
  String get confirmClearQueue =>
      'Are you sure you want to clear the current queue?';

  @override
  String get queueCleared => 'Queue cleared';

  @override
  String get queue => 'Queue';

  @override
  String get queueEmpty => 'Queue is empty';

  @override
  String selectedSongs(int count) {
    return '$count songs selected';
  }

  @override
  String get unknownArtist => 'Unknown Artist';

  @override
  String deletedSongs(int count) {
    return '$count songs deleted';
  }

  @override
  String get delete => 'Delete';

  @override
  String get createPlaylist => 'Create Playlist';

  @override
  String get playlistName => 'Playlist Name';

  @override
  String get enterPlaylistName => 'Enter playlist name';

  @override
  String get renamePlaylist => 'Rename Playlist';

  @override
  String get deletePlaylist => 'Delete Playlist';

  @override
  String confirmDeletePlaylist(String name) {
    return 'Are you sure you want to delete the playlist \"$name\"?';
  }

  @override
  String get addToPlaylist => 'Add to Playlist';

  @override
  String songCount(int count) {
    return '$count songs';
  }

  @override
  String addedToPlaylist(int count, String playlist) {
    return 'Added $count songs to $playlist';
  }

  @override
  String get createNewList => 'Create New List';

  @override
  String createdPlaylist(String name, int count) {
    return 'Created playlist \"$name\" and added $count songs';
  }

  @override
  String get rename => 'Rename';

  @override
  String get playlist => 'Playlist';

  @override
  String get mostPlayed => 'Most Played';

  @override
  String get recentlyAdded => 'Recently Added';

  @override
  String get albums => 'Albums';

  @override
  String get artists => 'Artists';

  @override
  String get mostPlayedDescription => 'Ranked by completed plays';

  @override
  String get recentlyAddedDescription =>
      'Sorted by when songs entered your library';

  @override
  String get allTime => 'All Time';

  @override
  String get pastWeek => 'Past Week';

  @override
  String get pastMonth => 'Past Month';

  @override
  String get past90Days => 'Past 90 Days';

  @override
  String get noPlayHistory => 'No play history yet';

  @override
  String get noPlayHistoryInRange => 'No play history in this time range';

  @override
  String get noRecentlyAddedSongs => 'No songs in your library yet';

  @override
  String get noRecentlyAddedInRange => 'No songs were added in this time range';

  @override
  String get addedOn => 'Added On';

  @override
  String get lastPlayed => 'Last played';

  @override
  String playCountLabel(int count) {
    return '$count plays';
  }

  @override
  String get playAll => 'Play All';

  @override
  String get shufflePlay => 'Shuffle Play';

  @override
  String get noAlbums => 'No albums found yet';

  @override
  String get noArtists => 'No artists found yet';

  @override
  String get searchAlbums => 'Search albums or artists';

  @override
  String get searchArtists => 'Search artists';

  @override
  String get albumSort => 'Sort';

  @override
  String get sortArtistAsc => 'Artist A-Z';

  @override
  String get sortTitleAsc => 'Album Title A-Z';

  @override
  String get sortTrackCount => 'Song Count';

  @override
  String get sortDuration => 'Total Duration';

  @override
  String get sortRecentAdded => 'Recently Added';

  @override
  String get sortAscending => 'Ascending';

  @override
  String get sortDescending => 'Descending';

  @override
  String get playNext => 'Play Next';

  @override
  String get addToFavorites => 'Add to Favorites';

  @override
  String get removeFromFavorites => 'Remove from Favorites';

  @override
  String get viewAlbumDetails => 'View Album Details';

  @override
  String get viewArtistDetails => 'View Artist Details';

  @override
  String get openFileLocation => 'Open File Location';

  @override
  String get copyAlbumTitle => 'Copy Album Title';

  @override
  String get copyArtistName => 'Copy Artist Name';

  @override
  String albumCount(int count) {
    return '$count albums';
  }

  @override
  String get emptyList => 'List is empty';

  @override
  String get dragToAddMusic => 'Drag files or folders to add music';

  @override
  String get unknownAlbum => 'Unknown Album';

  @override
  String get managePlaylists => 'Manage Playlists';

  @override
  String get createNewPlaylist => 'Create New Playlist';

  @override
  String get defaultList => 'Default List';

  @override
  String get playbackMode => 'Playback Mode';

  @override
  String get playbackOptions => 'Playback Options';

  @override
  String get setVisualizerDisplay => 'Set Visualizer Display';

  @override
  String get noPlaybackContent => 'No playback content';

  @override
  String get file => 'File';

  @override
  String get play => 'Play';

  @override
  String get list => 'Library';

  @override
  String get queueTab => 'Queue';

  @override
  String get more => 'More';

  @override
  String get settings => 'Settings';

  @override
  String get themeMode => 'Theme';

  @override
  String get themeModeSystem => 'Follow System';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get immersiveTabBar => 'Immersive Tab Bar';

  @override
  String get immersiveTabBarDescription =>
      'Show the navigation bar when the mouse moves, then hide it after 3 seconds of inactivity';

  @override
  String get sampleStride => 'Sample Stride';

  @override
  String get sampleStrideDescription =>
      'Larger values scan faster but with lower waveform precision (default: 4)';

  @override
  String get waveformSegments => 'Waveform Segments';

  @override
  String get waveformSegmentsDescription =>
      'Number of waveform bars to display (default: 80)';

  @override
  String get playbackBackground => 'Playback Background';

  @override
  String get blurredArtwork => 'Blurred Artwork (Default)';

  @override
  String get dynamicMesh => 'Dynamic Mesh (Apple Music style)';

  @override
  String get unknown => 'Unknown';

  @override
  String get playlistModeSingle => 'Single';

  @override
  String get playlistModeSingleLoop => 'Single Loop';

  @override
  String get playlistModeQueue => 'Queue';

  @override
  String get playlistModeQueueLoop => 'Queue Loop';

  @override
  String get playlistModeAutoQueueLoop => 'Auto Queue Loop';

  @override
  String get visualizer => 'Visualizer';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get pause => 'Pause';

  @override
  String get autoMode => 'Auto Mode';

  @override
  String get advancedOptions => 'Advanced Options';

  @override
  String get spectrumQuantity => 'Spectrum Quantity';

  @override
  String get speed => 'Speed';

  @override
  String get quantityHigh => 'High';

  @override
  String get quantityMedium => 'Medium';

  @override
  String get quantityLow => 'Low';

  @override
  String get speedFast => 'Fast';

  @override
  String get speedMedium => 'Medium';

  @override
  String get speedSlow => 'Slow';

  @override
  String get portraitFrequencyGroups => 'Portrait Freq Quantity';

  @override
  String get landscapeFrequencyGroups => 'Landscape Freq Quantity';

  @override
  String get portraitGap => 'Portrait Gap';

  @override
  String get landscapeGap => 'Landscape Gap';

  @override
  String get enableWaveformProgressBar => 'Enable Waveform Progress Bar';

  @override
  String get enableWaveformProgressBarDescription =>
      'Use full-song waveform instead of standard slider';

  @override
  String get randomMode => 'Random Mode';

  @override
  String get randomHistory => 'Random History';

  @override
  String get randomRange => 'Random Range';

  @override
  String get randomMethod => 'Random Method';

  @override
  String get currentQueue => 'Current Queue';

  @override
  String get globalRange => 'Global (All Playlists)';

  @override
  String get completeRandom => 'Complete Random';

  @override
  String get shuffleRandom => 'Shuffle Random';

  @override
  String get randomQueue => 'Random Queue';

  @override
  String get notSelected => 'No Music Selected';

  @override
  String get saveTagsToFile => 'Save Tags to File';

  @override
  String get saveCurrentTagsToFile => 'Save current song tags to file';

  @override
  String get saveQueueTagsToFile => 'Save all queue tags to file';

  @override
  String get tagsSaved => 'Tags saved successfully';

  @override
  String tagsSavedCount(Object count) {
    return 'Tags saved ($count songs)';
  }

  @override
  String get tagsSaveFailed => 'Failed to save tags';

  @override
  String tagsSaveFailedCount(Object count) {
    return 'Failed to save $count songs';
  }

  @override
  String unsupportedFormat(Object count) {
    return '$count songs have unsupported formats (OGG/Opus cannot be saved)';
  }

  @override
  String get unsupportedFormatSingle =>
      'This format (OGG/Opus) does not support saving tags';

  @override
  String get savingTags => 'Saving tags...';

  @override
  String get noModifiedTagsToSave => 'No modified tags to save';

  @override
  String get clearPlaylist => 'Clear List';

  @override
  String get copyTitle => 'Copy Title';

  @override
  String get openFolderLocation => 'Open Folder Location';

  @override
  String get songTagsSavedToSourceFileAndApp =>
      'Song tags saved to the source file and the app';

  @override
  String get songTagsSavedToApp => 'Song tags saved to the app';

  @override
  String get durationZero => '0:00';

  @override
  String get generateLyrics => 'Generate Lyrics';

  @override
  String get generateTimeline => 'Generate Timeline';

  @override
  String get queueGenerateLyrics => 'Queue Lyrics Generation';

  @override
  String get pauseAutoScroll => 'Pause Auto Scroll';

  @override
  String get resumeAutoScroll => 'Resume Auto Scroll';

  @override
  String get translateLyrics => 'Translate Lyrics';

  @override
  String get clearLyricsCache => 'Clear Current Lyrics Cache';

  @override
  String get clearTranslationCache => 'Clear Current Translation Cache';

  @override
  String get requery => 'Requery';

  @override
  String get sleepTimerTitle => 'Sleep Timer';

  @override
  String get sleepTimerDescription =>
      'Choose a countdown and playback will pause when time is up.';

  @override
  String get sleepTimerRunningTitle => 'Sleep Timer Running';

  @override
  String get sleepTimerRunningDescription =>
      'Playback will pause automatically when the countdown ends.';

  @override
  String get remainingTime => 'Remaining time';

  @override
  String get startCountdown => 'Start Countdown';

  @override
  String get end => 'End';

  @override
  String get equalizer => 'Equalizer';

  @override
  String get equalizerEnabledStatus => 'High-fidelity adjustment enabled';

  @override
  String get equalizerDisabledStatus => 'Disabled';

  @override
  String get bassBoost => 'Bass Boost';

  @override
  String get preampGain => 'Preamp Gain';

  @override
  String get reset => 'Reset';

  @override
  String get close => 'Close';

  @override
  String get timelineAdjustmentTitle => 'Adjust Timeline';

  @override
  String get timelineAdjustmentDescription =>
      'Drag right to delay the lyrics, drag left to make them play earlier.';

  @override
  String timelineOffsetEarlier(Object seconds) {
    return 'Ahead by ${seconds}s';
  }

  @override
  String timelineOffsetLater(Object seconds) {
    return 'Behind by ${seconds}s';
  }

  @override
  String get timelineOffsetCurrent => 'Current offset: 0.0s';

  @override
  String get enterAcoustidApiKeyTitle => 'Enter AcoustID API Key';

  @override
  String get acoustidApiKeyDescription =>
      'Used for audio fingerprinting. Leaving it blank will restore the built-in default key.';

  @override
  String get acoustidApiKeyHint => 'Paste your AcoustID API Key';

  @override
  String get apiKey => 'API Key';

  @override
  String get save => 'Save';

  @override
  String get enterLyricsTitle => 'Enter Lyrics';

  @override
  String get lyricsInputHint =>
      'Paste or type lyrics here. Multiline text is supported.';

  @override
  String get enterGoogleAiStudioApiKeyTitle => 'Enter Google AI Studio API Key';

  @override
  String get googleAiStudioApiKeyDescription =>
      'Used for lyric generation, timeline generation, and translation in Google AI Studio.';

  @override
  String get pasteGoogleAiStudioApiKey => 'Paste Google AI Studio API Key';

  @override
  String get enterOpenRouterApiKeyTitle => 'Enter OpenRouter API Key';

  @override
  String get openRouterApiKeyDescription =>
      'Used for lyric generation and timeline generation in OpenRouter. Translation always uses Gemini.';

  @override
  String get pasteOpenRouterApiKey => 'Paste OpenRouter API Key';

  @override
  String get enterGeminiApiKeyTitle => 'Enter Gemini API Key';

  @override
  String get geminiApiKeyDescription => 'Used for lyric translation.';

  @override
  String get pasteGeminiApiKey => 'Paste Gemini API Key';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get enterApiKey => 'Please enter an API key.';

  @override
  String get testingConnection => 'Testing connection...';

  @override
  String get getKey => 'Get key';

  @override
  String get editSongTagsTitle => 'Edit Song Tags';

  @override
  String get editSongTagsDescription =>
      'You can save changes only in the app, or write them back to the source file as well.';

  @override
  String get artistLabel => 'Artist';

  @override
  String get albumLabel => 'Album';

  @override
  String get trackNumberLabel => 'Track Number';

  @override
  String get trackNumberMustBeInteger => 'Track number must be an integer';

  @override
  String get leaveBlankKeepsCurrentValue =>
      'Leave blank to keep the current value';

  @override
  String get currentFileFormatCannotWriteBack =>
      'This file format does not support writing back to the source file. Changes can only be saved in the app.';

  @override
  String get leaveBlankDoesNotClearOriginalValue =>
      'Tip: leaving a field blank will not clear the original value; it keeps the current tag.';

  @override
  String get saveToApp => 'Save to App';

  @override
  String get saveToSourceFileAndApp => 'Save to Source File and App';

  @override
  String get saveToSourceFileFailed =>
      'Failed to save to the source file. Please make sure the file format supports writing and the file is not in use.';

  @override
  String get saveFailed => 'Save failed. Please try again later.';

  @override
  String apiKeySaved(Object provider) {
    return '$provider API key saved';
  }

  @override
  String get apiKeySavedAcoustid => 'AcoustID API key saved';

  @override
  String get generalSectionTitle => 'Interface';

  @override
  String get generalSectionDescription =>
      'These options affect the overall appearance of the pages and playback UI.';

  @override
  String get scanSectionTitle => 'Scanning';

  @override
  String get scanSectionDescription =>
      'These options control how the library scan treats audio files.';

  @override
  String get skipShortAudioDuringScan => 'Skip short audio during scan';

  @override
  String get skipShortAudioDuringScanDescription =>
      'Audio shorter than the threshold will not be added to the library.';

  @override
  String get shortAudioScanThreshold => 'Short audio threshold';

  @override
  String get shortAudioScanThresholdDescription =>
      'Files shorter than this duration will be skipped.';

  @override
  String shortAudioScanThresholdValue(Object seconds) {
    return '$seconds s';
  }

  @override
  String get shortcutSettingsTitle => 'Custom Shortcuts';

  @override
  String get shortcutSettingsDescription =>
      'Click to re-record and save shortcuts for player actions.';

  @override
  String get edit => 'Edit';

  @override
  String get lyricsSectionTitle => 'Lyrics';

  @override
  String get lyricsSectionDescription =>
      'These settings only affect lyric generation and timeline generation.';

  @override
  String get autoSwitchLyricsProvider => 'Auto-switch lyric provider';

  @override
  String get autoSwitchLyricsProviderEnabledDesc =>
      'Google AI Studio is tried first. If both the primary and fallback models fail with 429 or 5xx errors, the app automatically switches to OpenRouter and keeps trying.';

  @override
  String get autoSwitchLyricsProviderDisabledDesc =>
      'You need API keys for both Google AI Studio and OpenRouter before auto-switching can be enabled.';

  @override
  String get lyricsAiProviderTitle => 'Lyrics AI Provider';

  @override
  String get lyricsAiProviderDescription =>
      'This only affects lyric generation and timeline generation. Translation always uses Google AI Studio.';

  @override
  String get googleAiStudioApiKeySaved => 'Google AI Studio API key saved';

  @override
  String get googleAiStudioApiKeyMissing =>
      'No Google AI Studio API key is saved yet. Lyric generation and timeline generation will prompt you first.';

  @override
  String get openRouterApiKeySaved => 'OpenRouter API key saved';

  @override
  String get openRouterApiKeyMissing =>
      'No OpenRouter API key is saved yet. Lyric generation and timeline generation will prompt you first.';

  @override
  String get fill => 'Fill in';

  @override
  String get modify => 'Modify';

  @override
  String get geminiModelsSectionTitle => 'Gemini Models';

  @override
  String get geminiModelsSectionDescription =>
      'These two models are used for lyric generation and timeline generation in Google AI Studio.';

  @override
  String get primaryModelLabel => 'Primary model';

  @override
  String get backupModelLabel => 'Fallback model';

  @override
  String get fetching => 'Fetching...';

  @override
  String get fetchModelList => 'Fetch model list';

  @override
  String get restoreDefault => 'Restore default';

  @override
  String get acoustidSectionTitle => 'Fingerprinting';

  @override
  String get acoustidApiKeyTitle => 'AcoustID API Key';

  @override
  String get acoustidApiKeyHelp =>
      'AcoustID is used for audio fingerprinting. We recommend using your own API key.';

  @override
  String get acoustidApiKeySaved => 'AcoustID API key saved';

  @override
  String get acoustidApiKeyDefault =>
      'The built-in default key is currently in use. We recommend replacing it with your own key.';

  @override
  String get applyForApiKey =>
      'Apply for API key: https://acoustid.org/new-application';

  @override
  String get queueTabBarFavoriteAdded => 'Added to favorites';

  @override
  String get queueTabBarFavoriteRemoved => 'Removed from favorites';

  @override
  String get tagCompletion => 'Tag completion';

  @override
  String get tagCompletionDescription =>
      'Match tags with AcoustID and MusicBrainz results';

  @override
  String get goToSettings => 'Go to Settings';

  @override
  String get searchReleaseTitles => 'Search release titles';

  @override
  String get closeSearch => 'Close search';

  @override
  String get refreshResults => 'Refresh results';

  @override
  String get filterMusicBrainzReleaseTitle =>
      'Filter MusicBrainz release titles';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get localTitle => 'Local title';

  @override
  String get queryConditions => 'Query conditions';

  @override
  String get musicBrainzLoading => 'MusicBrainz is loading';

  @override
  String get musicBrainzLoadingWithResults =>
      'Existing results will stay in the panel';

  @override
  String get musicBrainzLoadingHint => 'Please wait';

  @override
  String get musicBrainzQueryFailed => 'MusicBrainz query failed';

  @override
  String get musicBrainzNetworkErrorHint =>
      'The request failed, usually because of unstable network, timeout, or server rejection. Try again later.';

  @override
  String get musicBrainzFilteredEmptyHint =>
      'No release titles containing that keyword were found under the current filters.';

  @override
  String get musicBrainzEmptyHint =>
      'MusicBrainz returned no usable results. Try loosening the title, artist, or album filters.';

  @override
  String get musicBrainzEmptyMoreCompleteHint =>
      'Try again later, or confirm the current title or artist info is more complete.';

  @override
  String get retry => 'Retry';

  @override
  String get noMatchingRelease => 'No matching release found';

  @override
  String get noMatchingResults => 'No matching results found';

  @override
  String get searchAgain => 'Search again';

  @override
  String get acoustidRecognitionRecords => 'AcoustID recognition records';

  @override
  String get musicBrainzRecordings => 'MusicBrainz recordings';

  @override
  String get noExpandableReleaseGroups =>
      'No expandable release groups available';

  @override
  String get noExpandableReleases => 'No expandable releases available';

  @override
  String get noMatchingResultHint =>
      'Try again later, or confirm the current title or artist info is more complete.';

  @override
  String releaseCountLabel(int count) {
    return '$count release versions';
  }

  @override
  String recordingCountLabel(int count) {
    return '$count recordings';
  }

  @override
  String trackCountShort(int count) {
    return '$count tracks';
  }

  @override
  String scoreLabel(int score) {
    return 'Score $score';
  }

  @override
  String matchScoreLabel(int score) {
    return 'Match $score%';
  }

  @override
  String get editQueryCondition => 'Edit query condition';

  @override
  String get enterNewQueryText => 'Enter new query text';

  @override
  String get durationLabel => 'Duration';

  @override
  String get customShortcuts => 'Custom Shortcuts';

  @override
  String get pressShortcutCombo => 'Press the shortcut combination';

  @override
  String get clickToRecord => 'Click to record';

  @override
  String get searchingLyrics => 'Searching lyrics';

  @override
  String get noLyrics => 'No lyrics yet';

  @override
  String get providerLabel => 'Provider';

  @override
  String get modelLabel => 'Model';

  @override
  String get unspecified => 'Not specified';

  @override
  String targetTimeLabel(String duration) {
    return 'Target time $duration';
  }

  @override
  String get songDeletedSkipped => 'Song deleted, skipped';

  @override
  String get songDeleted => 'Song deleted';

  @override
  String get lyricsTaskUploading => 'Uploading';

  @override
  String get lyricsTaskWaiting => 'Waiting';

  @override
  String get lyricsTaskRequesting => 'Requesting';

  @override
  String get lyricsTaskGenerating => 'Generating';

  @override
  String get lyricsTaskRetrying => 'Retrying';

  @override
  String get lyricsTaskProcessing => 'Processing';

  @override
  String get unknownModel => 'Unknown model';

  @override
  String selectedFolders(int count) {
    return '$count folders selected';
  }

  @override
  String foldersDeleted(int count) {
    return '$count folders deleted';
  }

  @override
  String get persistentAccessDenied =>
      'Could not save access to that folder. Please select it again.';

  @override
  String get folderAddFailed => 'Failed to add the folder';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String sleepTimerRemaining(Object duration) {
    return 'Sleep timer $duration';
  }

  @override
  String get unknownArtistOrAlbum => 'Unknown';
}
