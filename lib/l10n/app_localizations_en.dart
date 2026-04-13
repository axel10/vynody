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
  String get list => 'List';

  @override
  String get queueTab => 'Queue';

  @override
  String get more => 'More';

  @override
  String get settings => 'Settings';

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
}
