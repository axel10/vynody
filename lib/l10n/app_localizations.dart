import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// The title of the application
  ///
  /// In zh, this message translates to:
  /// **'Pure Player'**
  String get appTitle;

  /// System media library
  ///
  /// In zh, this message translates to:
  /// **'系统媒体库'**
  String get systemMediaLibrary;

  /// Scanning directory message
  ///
  /// In zh, this message translates to:
  /// **'正在扫描目录...'**
  String get scanningDirectory;

  /// Scanning progress toast message showing how many files have had text metadata preprocessed
  ///
  /// In zh, this message translates to:
  /// **'预处理 {count} '**
  String filesPreprocessed(Object count);

  /// Scanning progress toast message showing how many files have been discovered
  ///
  /// In zh, this message translates to:
  /// **'已发现 {count} '**
  String filesDiscovered(Object count);

  /// Scanning progress toast message showing how many songs have been fully processed with thumbnails and theme colors
  ///
  /// In zh, this message translates to:
  /// **'完整处理 {count} '**
  String filesFullyProcessed(Object count);

  /// Directory added successfully
  ///
  /// In zh, this message translates to:
  /// **'目录添加成功'**
  String get directoryAddedSuccess;

  /// Directory added but no audio files found
  ///
  /// In zh, this message translates to:
  /// **'目录已添加，但未发现可播放音频文件'**
  String get directoryAddedNoMusic;

  /// Scan directory button
  ///
  /// In zh, this message translates to:
  /// **'扫描目录'**
  String get scanDirectory;

  /// Sort option
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get sort;

  /// Add root directory
  ///
  /// In zh, this message translates to:
  /// **'添加根目录'**
  String get addRootDirectory;

  /// Go back to parent directory
  ///
  /// In zh, this message translates to:
  /// **'返回上一层'**
  String get goBack;

  /// No media library permission
  ///
  /// In zh, this message translates to:
  /// **'未获得媒体库访问权限'**
  String get noMediaLibraryPermission;

  /// Grant permission button
  ///
  /// In zh, this message translates to:
  /// **'给予权限'**
  String get grantPermission;

  /// Need permission to scan local music
  ///
  /// In zh, this message translates to:
  /// **'需授予权限以扫描本地音乐'**
  String get needPermissionToScan;

  /// Rebuild tag database
  ///
  /// In zh, this message translates to:
  /// **'重建标签数据库'**
  String get rebuildTagDatabase;

  /// Rebuild database
  ///
  /// In zh, this message translates to:
  /// **'重建数据库'**
  String get rebuildDatabase;

  /// Confirm rebuild database message
  ///
  /// In zh, this message translates to:
  /// **'确定要手动刷新所有歌曲的标签信息吗？这可能需要一些时间来重新加载封面和元数据。'**
  String get confirmRebuildDatabase;

  /// Cancel button
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// Confirm button
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// Rebuilding database message
  ///
  /// In zh, this message translates to:
  /// **'正在重建歌曲标签数据库...'**
  String get rebuildingDatabase;

  /// Sort by
  ///
  /// In zh, this message translates to:
  /// **'排序方式'**
  String get sortBy;

  /// No description provided for @sortScope.
  ///
  /// In zh, this message translates to:
  /// **'作用域'**
  String get sortScope;

  /// No description provided for @sortOrder.
  ///
  /// In zh, this message translates to:
  /// **'排序顺序'**
  String get sortOrder;

  /// Title
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get title;

  /// File name
  ///
  /// In zh, this message translates to:
  /// **'文件名'**
  String get fileName;

  /// Track number
  ///
  /// In zh, this message translates to:
  /// **'轨道号'**
  String get trackNumber;

  /// Ascending order
  ///
  /// In zh, this message translates to:
  /// **'升序'**
  String get ascending;

  /// Descending order
  ///
  /// In zh, this message translates to:
  /// **'降序'**
  String get descending;

  /// Current folder sort scope
  ///
  /// In zh, this message translates to:
  /// **'当前目录'**
  String get currentFolderScope;

  /// Global sort scope
  ///
  /// In zh, this message translates to:
  /// **'全局'**
  String get globalScope;

  /// Visualizer settings
  ///
  /// In zh, this message translates to:
  /// **'播放页设置'**
  String get visualizerSettings;

  /// Spectrum tab
  ///
  /// In zh, this message translates to:
  /// **'频谱'**
  String get algorithm;

  /// Appearance tab
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get appearance;

  /// Spectrum appearance group
  ///
  /// In zh, this message translates to:
  /// **'频谱外观'**
  String get spectrumAppearanceGroup;

  /// Spectrum advanced options
  ///
  /// In zh, this message translates to:
  /// **'频谱高级选项'**
  String get spectrumAdvancedOptions;

  /// Reset algorithm button
  ///
  /// In zh, this message translates to:
  /// **'重置算法'**
  String get resetAlgorithm;

  /// Reset appearance button
  ///
  /// In zh, this message translates to:
  /// **'重置外观'**
  String get resetAppearance;

  /// Smoothing coefficient
  ///
  /// In zh, this message translates to:
  /// **'平滑系数 (Smoothing)'**
  String get smoothing;

  /// Gravity coefficient
  ///
  /// In zh, this message translates to:
  /// **'重力系数 (Gravity)'**
  String get gravity;

  /// Log scale
  ///
  /// In zh, this message translates to:
  /// **'对数缩放 (Log Scale)'**
  String get logScale;

  /// Contrast
  ///
  /// In zh, this message translates to:
  /// **'对比度 (Contrast)'**
  String get contrast;

  /// Normalization
  ///
  /// In zh, this message translates to:
  /// **'归一化 (Normalization)'**
  String get normalization;

  /// Multiplier
  ///
  /// In zh, this message translates to:
  /// **'增益 (Multiplier)'**
  String get multiplier;

  /// Skip high frequency
  ///
  /// In zh, this message translates to:
  /// **'跳过高频'**
  String get skipHighFrequency;

  /// Frequency groups
  ///
  /// In zh, this message translates to:
  /// **'频率分组 (Frequency Groups)'**
  String get frequencyGroups;

  /// Aggregation mode
  ///
  /// In zh, this message translates to:
  /// **'聚合模式 (Aggregation Mode)'**
  String get aggregationMode;

  /// Opacity
  ///
  /// In zh, this message translates to:
  /// **'透明度 (Opacity)'**
  String get opacity;

  /// Enable gradient
  ///
  /// In zh, this message translates to:
  /// **'启用渐变色'**
  String get enableGradient;

  /// Start color
  ///
  /// In zh, this message translates to:
  /// **'起始颜色'**
  String get startColor;

  /// End color
  ///
  /// In zh, this message translates to:
  /// **'结束颜色'**
  String get endColor;

  /// Gradient range stop 1
  ///
  /// In zh, this message translates to:
  /// **'渐变范围 Stop 1'**
  String get gradientRangeStop1;

  /// Gradient range stop 2
  ///
  /// In zh, this message translates to:
  /// **'渐变范围 Stop 2'**
  String get gradientRangeStop2;

  /// Gradient repeat mode
  ///
  /// In zh, this message translates to:
  /// **'渐变重复模式 (TileMode)'**
  String get gradientRepeatMode;

  /// Color
  ///
  /// In zh, this message translates to:
  /// **'颜色'**
  String get color;

  /// Follow cover color
  ///
  /// In zh, this message translates to:
  /// **'跟随封面变色'**
  String get followCoverColor;

  /// Select color
  ///
  /// In zh, this message translates to:
  /// **'选择颜色'**
  String get selectColor;

  /// Volume
  ///
  /// In zh, this message translates to:
  /// **'音量'**
  String get volume;

  /// Clear queue
  ///
  /// In zh, this message translates to:
  /// **'清空队列'**
  String get clearQueue;

  /// Confirm clear queue message
  ///
  /// In zh, this message translates to:
  /// **'确定要清空当前队列吗？'**
  String get confirmClearQueue;

  /// Queue cleared message
  ///
  /// In zh, this message translates to:
  /// **'队列已清空'**
  String get queueCleared;

  /// Queue
  ///
  /// In zh, this message translates to:
  /// **'队列'**
  String get queue;

  /// Queue is empty
  ///
  /// In zh, this message translates to:
  /// **'队列为空'**
  String get queueEmpty;

  /// Selected songs count
  ///
  /// In zh, this message translates to:
  /// **'已选择 {count} 首'**
  String selectedSongs(int count);

  /// Unknown artist
  ///
  /// In zh, this message translates to:
  /// **'未知艺术家'**
  String get unknownArtist;

  /// Deleted songs count
  ///
  /// In zh, this message translates to:
  /// **'已删除 {count} 首歌曲'**
  String deletedSongs(int count);

  /// Delete button
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// Create playlist
  ///
  /// In zh, this message translates to:
  /// **'创建播放列表'**
  String get createPlaylist;

  /// Playlist name
  ///
  /// In zh, this message translates to:
  /// **'播放列表名称'**
  String get playlistName;

  /// Enter playlist name hint
  ///
  /// In zh, this message translates to:
  /// **'请输入播放列表名称'**
  String get enterPlaylistName;

  /// Rename playlist
  ///
  /// In zh, this message translates to:
  /// **'重命名播放列表'**
  String get renamePlaylist;

  /// Delete playlist
  ///
  /// In zh, this message translates to:
  /// **'删除播放列表'**
  String get deletePlaylist;

  /// Confirm delete playlist message
  ///
  /// In zh, this message translates to:
  /// **'确定要删除播放列表\"{name}\"吗？'**
  String confirmDeletePlaylist(String name);

  /// Add to playlist
  ///
  /// In zh, this message translates to:
  /// **'添加到播放列表'**
  String get addToPlaylist;

  /// Select all
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get selectAll;

  /// Add to queue
  ///
  /// In zh, this message translates to:
  /// **'添加到队列'**
  String get addToQueue;

  /// Added to queue
  ///
  /// In zh, this message translates to:
  /// **'已添加到队列'**
  String get addedToQueue;

  /// Song count
  ///
  /// In zh, this message translates to:
  /// **'{count} 首歌曲'**
  String songCount(int count);

  /// Added to playlist message
  ///
  /// In zh, this message translates to:
  /// **'已添加 {count} 首歌曲到{playlist}'**
  String addedToPlaylist(int count, String playlist);

  /// Create new list
  ///
  /// In zh, this message translates to:
  /// **'新建列表'**
  String get createNewList;

  /// Created playlist message
  ///
  /// In zh, this message translates to:
  /// **'已创建播放列表\"{name}\"并添加 {count} 首歌曲'**
  String createdPlaylist(String name, int count);

  /// Rename
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get rename;

  /// Playlist
  ///
  /// In zh, this message translates to:
  /// **'播放列表'**
  String get playlist;

  /// No description provided for @mostPlayed.
  ///
  /// In zh, this message translates to:
  /// **'最多播放'**
  String get mostPlayed;

  /// No description provided for @recentlyAdded.
  ///
  /// In zh, this message translates to:
  /// **'最近添加'**
  String get recentlyAdded;

  /// Albums tab and section label
  ///
  /// In zh, this message translates to:
  /// **'专辑'**
  String get albums;

  /// Artists tab and section label
  ///
  /// In zh, this message translates to:
  /// **'艺术家'**
  String get artists;

  /// No description provided for @mostPlayedDescription.
  ///
  /// In zh, this message translates to:
  /// **'按有效播放次数排序'**
  String get mostPlayedDescription;

  /// No description provided for @recentlyAddedDescription.
  ///
  /// In zh, this message translates to:
  /// **'按进入媒体库的时间排序'**
  String get recentlyAddedDescription;

  /// No description provided for @allTime.
  ///
  /// In zh, this message translates to:
  /// **'全部时间'**
  String get allTime;

  /// No description provided for @pastWeek.
  ///
  /// In zh, this message translates to:
  /// **'过去一周'**
  String get pastWeek;

  /// No description provided for @pastMonth.
  ///
  /// In zh, this message translates to:
  /// **'过去一个月'**
  String get pastMonth;

  /// No description provided for @past90Days.
  ///
  /// In zh, this message translates to:
  /// **'过去三个月'**
  String get past90Days;

  /// No description provided for @noPlayHistory.
  ///
  /// In zh, this message translates to:
  /// **'还没有播放记录'**
  String get noPlayHistory;

  /// No description provided for @noPlayHistoryInRange.
  ///
  /// In zh, this message translates to:
  /// **'这个时间范围内还没有播放记录'**
  String get noPlayHistoryInRange;

  /// No description provided for @noRecentlyAddedSongs.
  ///
  /// In zh, this message translates to:
  /// **'媒体库中还没有歌曲'**
  String get noRecentlyAddedSongs;

  /// No description provided for @noRecentlyAddedInRange.
  ///
  /// In zh, this message translates to:
  /// **'这个时间范围内没有新添加的歌曲'**
  String get noRecentlyAddedInRange;

  /// No description provided for @addedOn.
  ///
  /// In zh, this message translates to:
  /// **'添加时间'**
  String get addedOn;

  /// No description provided for @lastPlayed.
  ///
  /// In zh, this message translates to:
  /// **'最近播放'**
  String get lastPlayed;

  /// No description provided for @playCountLabel.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次'**
  String playCountLabel(int count);

  /// Play all songs in the current album
  ///
  /// In zh, this message translates to:
  /// **'播放全部'**
  String get playAll;

  /// Shuffle play songs in the current album
  ///
  /// In zh, this message translates to:
  /// **'随机播放'**
  String get shufflePlay;

  /// Empty state text when no albums are available
  ///
  /// In zh, this message translates to:
  /// **'还没有可显示的专辑'**
  String get noAlbums;

  /// Empty state text when no artists are available
  ///
  /// In zh, this message translates to:
  /// **'还没有可显示的艺术家'**
  String get noArtists;

  /// Search albums or artists placeholder
  ///
  /// In zh, this message translates to:
  /// **'搜索专辑或艺术家'**
  String get searchAlbums;

  /// Search artists placeholder
  ///
  /// In zh, this message translates to:
  /// **'搜索艺术家'**
  String get searchArtists;

  /// Album sort button label
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get albumSort;

  /// Sort albums by artist ascending
  ///
  /// In zh, this message translates to:
  /// **'艺术家 A-Z'**
  String get sortArtistAsc;

  /// Sort albums by album title ascending
  ///
  /// In zh, this message translates to:
  /// **'专辑名 A-Z'**
  String get sortTitleAsc;

  /// Sort albums by song count
  ///
  /// In zh, this message translates to:
  /// **'歌曲数量'**
  String get sortTrackCount;

  /// Sort albums by total duration
  ///
  /// In zh, this message translates to:
  /// **'总时长'**
  String get sortDuration;

  /// Sort albums by recent add time
  ///
  /// In zh, this message translates to:
  /// **'最近添加'**
  String get sortRecentAdded;

  /// Ascending sort order
  ///
  /// In zh, this message translates to:
  /// **'升序'**
  String get sortAscending;

  /// Descending sort order
  ///
  /// In zh, this message translates to:
  /// **'降序'**
  String get sortDescending;

  /// Play next action
  ///
  /// In zh, this message translates to:
  /// **'下一首播放'**
  String get playNext;

  /// Add current album or song to favorites
  ///
  /// In zh, this message translates to:
  /// **'加入收藏'**
  String get addToFavorites;

  /// No description provided for @removeFromFavorites.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get removeFromFavorites;

  /// View album details action
  ///
  /// In zh, this message translates to:
  /// **'查看专辑详情'**
  String get viewAlbumDetails;

  /// View artist details action
  ///
  /// In zh, this message translates to:
  /// **'查看艺术家详情'**
  String get viewArtistDetails;

  /// Open the file location action
  ///
  /// In zh, this message translates to:
  /// **'打开文件所在位置'**
  String get openFileLocation;

  /// Copy album title action
  ///
  /// In zh, this message translates to:
  /// **'复制专辑名'**
  String get copyAlbumTitle;

  /// Copy artist name action
  ///
  /// In zh, this message translates to:
  /// **'复制艺术家名'**
  String get copyArtistName;

  /// Album count summary
  ///
  /// In zh, this message translates to:
  /// **'{count} 张专辑'**
  String albumCount(int count);

  /// List is empty
  ///
  /// In zh, this message translates to:
  /// **'列表为空'**
  String get emptyList;

  /// Drag to add music hint
  ///
  /// In zh, this message translates to:
  /// **'拖入文件或文件夹以添加音乐'**
  String get dragToAddMusic;

  /// Unknown album
  ///
  /// In zh, this message translates to:
  /// **'未知专辑'**
  String get unknownAlbum;

  /// Manage playlists
  ///
  /// In zh, this message translates to:
  /// **'管理播放列表'**
  String get managePlaylists;

  /// Create new playlist
  ///
  /// In zh, this message translates to:
  /// **'创建新播放列表'**
  String get createNewPlaylist;

  /// Default playlist
  ///
  /// In zh, this message translates to:
  /// **'默认列表'**
  String get defaultList;

  /// Playback mode
  ///
  /// In zh, this message translates to:
  /// **'播放模式'**
  String get playbackMode;

  /// Playback options
  ///
  /// In zh, this message translates to:
  /// **'播放选项'**
  String get playbackOptions;

  /// Set visualizer display
  ///
  /// In zh, this message translates to:
  /// **'设置频谱显示'**
  String get setVisualizerDisplay;

  /// No playback content
  ///
  /// In zh, this message translates to:
  /// **'当前没有播放内容'**
  String get noPlaybackContent;

  /// File tab
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get file;

  /// Play tab
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get play;

  /// List tab
  ///
  /// In zh, this message translates to:
  /// **'媒体库'**
  String get list;

  /// Queue tab
  ///
  /// In zh, this message translates to:
  /// **'队列'**
  String get queueTab;

  /// More tab
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// Settings
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// Theme mode label
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get themeMode;

  /// Theme mode option for following the system theme
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeModeSystem;

  /// Theme mode option for light mode
  ///
  /// In zh, this message translates to:
  /// **'亮色'**
  String get themeModeLight;

  /// Theme mode option for dark mode
  ///
  /// In zh, this message translates to:
  /// **'暗色'**
  String get themeModeDark;

  /// Immersive Tab Bar label
  ///
  /// In zh, this message translates to:
  /// **'沉浸式标签栏'**
  String get immersiveTabBar;

  /// Immersive Tab Bar description
  ///
  /// In zh, this message translates to:
  /// **'鼠标移动时显示导航栏，3 秒无操作后隐藏'**
  String get immersiveTabBarDescription;

  /// Sample Stride label
  ///
  /// In zh, this message translates to:
  /// **'采样步长'**
  String get sampleStride;

  /// Sample Stride description
  ///
  /// In zh, this message translates to:
  /// **'值越大扫描越快但波形精度越低 (默认: 4)'**
  String get sampleStrideDescription;

  /// Waveform Segments label
  ///
  /// In zh, this message translates to:
  /// **'波形分段'**
  String get waveformSegments;

  /// Waveform Segments description
  ///
  /// In zh, this message translates to:
  /// **'要显示的波形柱数量 (默认: 80)'**
  String get waveformSegmentsDescription;

  /// Show developer options label
  ///
  /// In zh, this message translates to:
  /// **'显示开发人员选项'**
  String get showDeveloperOptions;

  /// No description provided for @playbackBackground.
  ///
  /// In zh, this message translates to:
  /// **'播放页背景'**
  String get playbackBackground;

  /// No description provided for @playbackRadialGradient.
  ///
  /// In zh, this message translates to:
  /// **'中心暗色渐变'**
  String get playbackRadialGradient;

  /// No description provided for @blurIntensity.
  ///
  /// In zh, this message translates to:
  /// **'模糊强度'**
  String get blurIntensity;

  /// No description provided for @blurredArtwork.
  ///
  /// In zh, this message translates to:
  /// **'模糊封面 (默认)'**
  String get blurredArtwork;

  /// No description provided for @dynamicMesh.
  ///
  /// In zh, this message translates to:
  /// **'动态流变 (Apple Music 效果)'**
  String get dynamicMesh;

  /// No description provided for @solidColor.
  ///
  /// In zh, this message translates to:
  /// **'纯色'**
  String get solidColor;

  /// No description provided for @customImage.
  ///
  /// In zh, this message translates to:
  /// **'自定义图片'**
  String get customImage;

  /// No description provided for @presetColors.
  ///
  /// In zh, this message translates to:
  /// **'预设颜色'**
  String get presetColors;

  /// No description provided for @customColor.
  ///
  /// In zh, this message translates to:
  /// **'自定义颜色'**
  String get customColor;

  /// No description provided for @uploadImage.
  ///
  /// In zh, this message translates to:
  /// **'上传图片'**
  String get uploadImage;

  /// No description provided for @normalOpacity.
  ///
  /// In zh, this message translates to:
  /// **'常规暗色层不透明度'**
  String get normalOpacity;

  /// No description provided for @lyricsOpacity.
  ///
  /// In zh, this message translates to:
  /// **'歌词暗色层不透明度'**
  String get lyricsOpacity;

  /// No description provided for @chooseImageError.
  ///
  /// In zh, this message translates to:
  /// **'选择图片失败'**
  String get chooseImageError;

  /// No description provided for @noImageSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择图片'**
  String get noImageSelected;

  /// No description provided for @unknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get unknown;

  /// No description provided for @playlistModeSingle.
  ///
  /// In zh, this message translates to:
  /// **'单曲播放'**
  String get playlistModeSingle;

  /// No description provided for @playlistModeSingleLoop.
  ///
  /// In zh, this message translates to:
  /// **'单曲循环'**
  String get playlistModeSingleLoop;

  /// No description provided for @playlistModeQueue.
  ///
  /// In zh, this message translates to:
  /// **'播放列表'**
  String get playlistModeQueue;

  /// No description provided for @playlistModeQueueLoop.
  ///
  /// In zh, this message translates to:
  /// **'列表循环'**
  String get playlistModeQueueLoop;

  /// No description provided for @playlistModeAutoQueueLoop.
  ///
  /// In zh, this message translates to:
  /// **'自动列表循环'**
  String get playlistModeAutoQueueLoop;

  /// No description provided for @visualizer.
  ///
  /// In zh, this message translates to:
  /// **'可视化'**
  String get visualizer;

  /// No description provided for @previous.
  ///
  /// In zh, this message translates to:
  /// **'上一首'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In zh, this message translates to:
  /// **'下一首'**
  String get next;

  /// No description provided for @pause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get pause;

  /// No description provided for @autoMode.
  ///
  /// In zh, this message translates to:
  /// **'自动模式'**
  String get autoMode;

  /// No description provided for @advancedOptions.
  ///
  /// In zh, this message translates to:
  /// **'高级选项'**
  String get advancedOptions;

  /// No description provided for @spectrumQuantity.
  ///
  /// In zh, this message translates to:
  /// **'频谱数量'**
  String get spectrumQuantity;

  /// No description provided for @speed.
  ///
  /// In zh, this message translates to:
  /// **'速度'**
  String get speed;

  /// No description provided for @quantityHigh.
  ///
  /// In zh, this message translates to:
  /// **'多'**
  String get quantityHigh;

  /// No description provided for @quantityMedium.
  ///
  /// In zh, this message translates to:
  /// **'中'**
  String get quantityMedium;

  /// No description provided for @quantityLow.
  ///
  /// In zh, this message translates to:
  /// **'少'**
  String get quantityLow;

  /// No description provided for @speedFast.
  ///
  /// In zh, this message translates to:
  /// **'快'**
  String get speedFast;

  /// No description provided for @speedMedium.
  ///
  /// In zh, this message translates to:
  /// **'中'**
  String get speedMedium;

  /// No description provided for @speedSlow.
  ///
  /// In zh, this message translates to:
  /// **'慢'**
  String get speedSlow;

  /// No description provided for @portraitFrequencyGroups.
  ///
  /// In zh, this message translates to:
  /// **'竖屏频谱数量'**
  String get portraitFrequencyGroups;

  /// No description provided for @landscapeFrequencyGroups.
  ///
  /// In zh, this message translates to:
  /// **'横屏频谱数量'**
  String get landscapeFrequencyGroups;

  /// No description provided for @portraitGap.
  ///
  /// In zh, this message translates to:
  /// **'竖屏频谱间距'**
  String get portraitGap;

  /// No description provided for @landscapeGap.
  ///
  /// In zh, this message translates to:
  /// **'横屏频谱间距'**
  String get landscapeGap;

  /// Enable Waveform Progress Bar label
  ///
  /// In zh, this message translates to:
  /// **'启用波形进度条'**
  String get enableWaveformProgressBar;

  /// No description provided for @enableWaveformProgressBarDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用整首歌的波形图代替标准滑块'**
  String get enableWaveformProgressBarDescription;

  /// No description provided for @randomMode.
  ///
  /// In zh, this message translates to:
  /// **'随机模式'**
  String get randomMode;

  /// No description provided for @randomHistory.
  ///
  /// In zh, this message translates to:
  /// **'随机历史'**
  String get randomHistory;

  /// No description provided for @randomRange.
  ///
  /// In zh, this message translates to:
  /// **'随机范围'**
  String get randomRange;

  /// No description provided for @randomMethod.
  ///
  /// In zh, this message translates to:
  /// **'随机方式'**
  String get randomMethod;

  /// No description provided for @currentQueue.
  ///
  /// In zh, this message translates to:
  /// **'当前队列'**
  String get currentQueue;

  /// No description provided for @globalRange.
  ///
  /// In zh, this message translates to:
  /// **'全局 (包含所有列表歌曲)'**
  String get globalRange;

  /// No description provided for @completeRandom.
  ///
  /// In zh, this message translates to:
  /// **'完全随机'**
  String get completeRandom;

  /// No description provided for @shuffleRandom.
  ///
  /// In zh, this message translates to:
  /// **'洗牌随机'**
  String get shuffleRandom;

  /// No description provided for @randomQueue.
  ///
  /// In zh, this message translates to:
  /// **'随机队列'**
  String get randomQueue;

  /// No description provided for @notSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择音乐'**
  String get notSelected;

  /// No description provided for @saveTagsToFile.
  ///
  /// In zh, this message translates to:
  /// **'保存标签到文件'**
  String get saveTagsToFile;

  /// No description provided for @saveCurrentTagsToFile.
  ///
  /// In zh, this message translates to:
  /// **'保存当前歌曲标签到文件'**
  String get saveCurrentTagsToFile;

  /// No description provided for @saveQueueTagsToFile.
  ///
  /// In zh, this message translates to:
  /// **'保存队列中所有标签到文件'**
  String get saveQueueTagsToFile;

  /// No description provided for @tagsSaved.
  ///
  /// In zh, this message translates to:
  /// **'标签保存成功'**
  String get tagsSaved;

  /// No description provided for @tagsSavedCount.
  ///
  /// In zh, this message translates to:
  /// **'标签已保存 ({count} 首)'**
  String tagsSavedCount(Object count);

  /// No description provided for @tagsSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存标签失败'**
  String get tagsSaveFailed;

  /// No description provided for @tagsSaveFailedCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 首保存失败'**
  String tagsSaveFailedCount(Object count);

  /// No description provided for @unsupportedFormat.
  ///
  /// In zh, this message translates to:
  /// **'{count} 首歌曲格式不支持保存标签 (OGG/Opus)'**
  String unsupportedFormat(Object count);

  /// No description provided for @unsupportedFormatSingle.
  ///
  /// In zh, this message translates to:
  /// **'此格式 (OGG/Opus) 不支持保存标签'**
  String get unsupportedFormatSingle;

  /// No description provided for @savingTags.
  ///
  /// In zh, this message translates to:
  /// **'正在保存标签...'**
  String get savingTags;

  /// No description provided for @noModifiedTagsToSave.
  ///
  /// In zh, this message translates to:
  /// **'没有需要保存的已修改标签'**
  String get noModifiedTagsToSave;

  /// No description provided for @clearPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'清空列表'**
  String get clearPlaylist;

  /// No description provided for @copyTitle.
  ///
  /// In zh, this message translates to:
  /// **'复制标题'**
  String get copyTitle;

  /// No description provided for @transcodeAction.
  ///
  /// In zh, this message translates to:
  /// **'转码'**
  String get transcodeAction;

  /// No description provided for @transcodeSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'音频转码'**
  String get transcodeSectionTitle;

  /// No description provided for @transcodeSectionDescription.
  ///
  /// In zh, this message translates to:
  /// **'设置默认输出格式、质量预设以及 ffmpeg 路径。'**
  String get transcodeSectionDescription;

  /// No description provided for @transcodeDefaultFormat.
  ///
  /// In zh, this message translates to:
  /// **'默认输出格式'**
  String get transcodeDefaultFormat;

  /// No description provided for @transcodeDefaultQuality.
  ///
  /// In zh, this message translates to:
  /// **'默认质量预设'**
  String get transcodeDefaultQuality;

  /// No description provided for @transcodeAutoScanOutput.
  ///
  /// In zh, this message translates to:
  /// **'自动扫描转码结果'**
  String get transcodeAutoScanOutput;

  /// No description provided for @transcodeAutoScanOutputDescription.
  ///
  /// In zh, this message translates to:
  /// **'转码成功后自动刷新媒体库。'**
  String get transcodeAutoScanOutputDescription;

  /// No description provided for @transcodeFfmpegPath.
  ///
  /// In zh, this message translates to:
  /// **'ffmpeg 路径'**
  String get transcodeFfmpegPath;

  /// No description provided for @transcodeFfmpegPathHint.
  ///
  /// In zh, this message translates to:
  /// **'留空则使用 PATH 中的 ffmpeg'**
  String get transcodeFfmpegPathHint;

  /// No description provided for @transcodeFfmpegPathDefault.
  ///
  /// In zh, this message translates to:
  /// **'使用 PATH 中的 ffmpeg'**
  String get transcodeFfmpegPathDefault;

  /// No description provided for @transcodeTitle.
  ///
  /// In zh, this message translates to:
  /// **'音频转码'**
  String get transcodeTitle;

  /// No description provided for @transcodeSongCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 首歌曲'**
  String transcodeSongCount(int count);

  /// No description provided for @transcodeCompletedCount.
  ///
  /// In zh, this message translates to:
  /// **'已完成 {count} 个转码任务'**
  String transcodeCompletedCount(int count);

  /// No description provided for @transcodeCompletedWithFailures.
  ///
  /// In zh, this message translates to:
  /// **'已完成 {success}/{total} 个转码任务，失败 {failed} 个'**
  String transcodeCompletedWithFailures(int success, int total, int failed);

  /// No description provided for @transcodeFailedGeneric.
  ///
  /// In zh, this message translates to:
  /// **'转码失败'**
  String get transcodeFailedGeneric;

  /// No description provided for @transcodePreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在准备转码...'**
  String get transcodePreparing;

  /// No description provided for @transcodeProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在转码 {current}/{total}'**
  String transcodeProgress(int current, int total);

  /// No description provided for @transcoding.
  ///
  /// In zh, this message translates to:
  /// **'转码中...'**
  String get transcoding;

  /// No description provided for @startTranscode.
  ///
  /// In zh, this message translates to:
  /// **'开始转码'**
  String get startTranscode;

  /// No description provided for @transcodeEngine.
  ///
  /// In zh, this message translates to:
  /// **'引擎：{engine}'**
  String transcodeEngine(Object engine);

  /// No description provided for @transcodeUsingSystemFfmpeg.
  ///
  /// In zh, this message translates to:
  /// **'使用系统 PATH 中的 ffmpeg。'**
  String get transcodeUsingSystemFfmpeg;

  /// No description provided for @transcodeUsingCustomFfmpeg.
  ///
  /// In zh, this message translates to:
  /// **'使用自定义 ffmpeg：{path}'**
  String transcodeUsingCustomFfmpeg(Object path);

  /// No description provided for @transcodeFormat.
  ///
  /// In zh, this message translates to:
  /// **'输出格式'**
  String get transcodeFormat;

  /// No description provided for @transcodeQualityPreset.
  ///
  /// In zh, this message translates to:
  /// **'质量预设'**
  String get transcodeQualityPreset;

  /// No description provided for @transcodeQualityLow.
  ///
  /// In zh, this message translates to:
  /// **'低'**
  String get transcodeQualityLow;

  /// No description provided for @transcodeQualityMedium.
  ///
  /// In zh, this message translates to:
  /// **'中'**
  String get transcodeQualityMedium;

  /// No description provided for @transcodeQualityHigh.
  ///
  /// In zh, this message translates to:
  /// **'高'**
  String get transcodeQualityHigh;

  /// No description provided for @transcodeQualityExtreme.
  ///
  /// In zh, this message translates to:
  /// **'最高'**
  String get transcodeQualityExtreme;

  /// No description provided for @transcodeLosslessPresetHint.
  ///
  /// In zh, this message translates to:
  /// **'当前无损格式不使用质量档位和码率控制模式。'**
  String get transcodeLosslessPresetHint;

  /// No description provided for @transcodeAdvancedOptions.
  ///
  /// In zh, this message translates to:
  /// **'高级选项'**
  String get transcodeAdvancedOptions;

  /// No description provided for @transcodeAdvancedCustomized.
  ///
  /// In zh, this message translates to:
  /// **'高级参数已被手动修改'**
  String get transcodeAdvancedCustomized;

  /// No description provided for @transcodeAdvancedFollowingPreset.
  ///
  /// In zh, this message translates to:
  /// **'高级参数跟随当前预设'**
  String get transcodeAdvancedFollowingPreset;

  /// No description provided for @transcodeLosslessAdvancedHint.
  ///
  /// In zh, this message translates to:
  /// **'当前无损格式仅保留与源文件相关的高级选项。'**
  String get transcodeLosslessAdvancedHint;

  /// No description provided for @transcodeBitRateInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的比特率'**
  String get transcodeBitRateInvalid;

  /// No description provided for @transcodeBitRate.
  ///
  /// In zh, this message translates to:
  /// **'比特率'**
  String get transcodeBitRate;

  /// No description provided for @transcodeBitRateMode.
  ///
  /// In zh, this message translates to:
  /// **'码率控制模式'**
  String get transcodeBitRateMode;

  /// No description provided for @transcodeEncodingEngine.
  ///
  /// In zh, this message translates to:
  /// **'编码引擎'**
  String get transcodeEncodingEngine;

  /// No description provided for @transcodeSystemEncoder.
  ///
  /// In zh, this message translates to:
  /// **'Media3 (系统)'**
  String get transcodeSystemEncoder;

  /// No description provided for @transcodeFfmpegRustEncoder.
  ///
  /// In zh, this message translates to:
  /// **'FFmpeg (Rust)'**
  String get transcodeFfmpegRustEncoder;

  /// No description provided for @transcodeAacEncoder.
  ///
  /// In zh, this message translates to:
  /// **'AAC 编码器'**
  String get transcodeAacEncoder;

  /// No description provided for @transcodeSampleRate.
  ///
  /// In zh, this message translates to:
  /// **'采样率'**
  String get transcodeSampleRate;

  /// No description provided for @transcodeChannels.
  ///
  /// In zh, this message translates to:
  /// **'声道'**
  String get transcodeChannels;

  /// No description provided for @transcodeResetToPreset.
  ///
  /// In zh, this message translates to:
  /// **'重置为当前预设'**
  String get transcodeResetToPreset;

  /// No description provided for @transcodeResetLosslessOptions.
  ///
  /// In zh, this message translates to:
  /// **'重置无损选项'**
  String get transcodeResetLosslessOptions;

  /// No description provided for @transcodeOutputDirectory.
  ///
  /// In zh, this message translates to:
  /// **'输出目录'**
  String get transcodeOutputDirectory;

  /// No description provided for @transcodeOutputPreview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get transcodeOutputPreview;

  /// No description provided for @transcodeChooseDirectory.
  ///
  /// In zh, this message translates to:
  /// **'选择目录'**
  String get transcodeChooseDirectory;

  /// No description provided for @transcodeUseSourceDirectory.
  ///
  /// In zh, this message translates to:
  /// **'使用源文件目录'**
  String get transcodeUseSourceDirectory;

  /// No description provided for @transcodeKeepSource.
  ///
  /// In zh, this message translates to:
  /// **'保持源文件'**
  String get transcodeKeepSource;

  /// No description provided for @transcodeMono.
  ///
  /// In zh, this message translates to:
  /// **'单声道'**
  String get transcodeMono;

  /// No description provided for @transcodeStereo.
  ///
  /// In zh, this message translates to:
  /// **'双声道'**
  String get transcodeStereo;

  /// No description provided for @openFolderLocation.
  ///
  /// In zh, this message translates to:
  /// **'打开文件夹所在位置'**
  String get openFolderLocation;

  /// No description provided for @songTagsSavedToSourceFileAndApp.
  ///
  /// In zh, this message translates to:
  /// **'歌曲标签已保存到源文件和 App'**
  String get songTagsSavedToSourceFileAndApp;

  /// No description provided for @songTagsSavedToApp.
  ///
  /// In zh, this message translates to:
  /// **'歌曲标签已保存到 App'**
  String get songTagsSavedToApp;

  /// No description provided for @durationZero.
  ///
  /// In zh, this message translates to:
  /// **'0:00'**
  String get durationZero;

  /// No description provided for @generateLyrics.
  ///
  /// In zh, this message translates to:
  /// **'生成歌词'**
  String get generateLyrics;

  /// No description provided for @generateTimeline.
  ///
  /// In zh, this message translates to:
  /// **'生成时间轴'**
  String get generateTimeline;

  /// No description provided for @queueGenerateLyrics.
  ///
  /// In zh, this message translates to:
  /// **'排队生成'**
  String get queueGenerateLyrics;

  /// No description provided for @pauseAutoScroll.
  ///
  /// In zh, this message translates to:
  /// **'暂停自动滚动'**
  String get pauseAutoScroll;

  /// No description provided for @resumeAutoScroll.
  ///
  /// In zh, this message translates to:
  /// **'恢复自动滚动'**
  String get resumeAutoScroll;

  /// No description provided for @translateLyrics.
  ///
  /// In zh, this message translates to:
  /// **'翻译歌词'**
  String get translateLyrics;

  /// No description provided for @clearLyricsCache.
  ///
  /// In zh, this message translates to:
  /// **'清除当前歌词缓存'**
  String get clearLyricsCache;

  /// No description provided for @clearTranslationCache.
  ///
  /// In zh, this message translates to:
  /// **'清除当前翻译缓存'**
  String get clearTranslationCache;

  /// No description provided for @requery.
  ///
  /// In zh, this message translates to:
  /// **'重新查询'**
  String get requery;

  /// No description provided for @sleepTimerTitle.
  ///
  /// In zh, this message translates to:
  /// **'睡眠定时器'**
  String get sleepTimerTitle;

  /// No description provided for @sleepTimerDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择倒计时，时间到后会暂停播放。'**
  String get sleepTimerDescription;

  /// No description provided for @sleepTimerRunningTitle.
  ///
  /// In zh, this message translates to:
  /// **'睡眠定时器运行中'**
  String get sleepTimerRunningTitle;

  /// No description provided for @sleepTimerRunningDescription.
  ///
  /// In zh, this message translates to:
  /// **'倒计时结束后会自动暂停当前播放。'**
  String get sleepTimerRunningDescription;

  /// No description provided for @remainingTime.
  ///
  /// In zh, this message translates to:
  /// **'剩余时间'**
  String get remainingTime;

  /// No description provided for @startCountdown.
  ///
  /// In zh, this message translates to:
  /// **'开始倒计时'**
  String get startCountdown;

  /// No description provided for @end.
  ///
  /// In zh, this message translates to:
  /// **'结束'**
  String get end;

  /// No description provided for @equalizer.
  ///
  /// In zh, this message translates to:
  /// **'均衡器'**
  String get equalizer;

  /// No description provided for @equalizerEnabledStatus.
  ///
  /// In zh, this message translates to:
  /// **'已启用高保真调节'**
  String get equalizerEnabledStatus;

  /// No description provided for @equalizerDisabledStatus.
  ///
  /// In zh, this message translates to:
  /// **'已禁用'**
  String get equalizerDisabledStatus;

  /// No description provided for @bassBoost.
  ///
  /// In zh, this message translates to:
  /// **'低音增强'**
  String get bassBoost;

  /// No description provided for @preampGain.
  ///
  /// In zh, this message translates to:
  /// **'前置增益'**
  String get preampGain;

  /// No description provided for @reset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get reset;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @timelineAdjustmentTitle.
  ///
  /// In zh, this message translates to:
  /// **'手动调整时间轴'**
  String get timelineAdjustmentTitle;

  /// No description provided for @timelineAdjustmentDescription.
  ///
  /// In zh, this message translates to:
  /// **'向右拖动会让歌词整体延后，向左拖动会让歌词整体提前。'**
  String get timelineAdjustmentDescription;

  /// No description provided for @timelineOffsetEarlier.
  ///
  /// In zh, this message translates to:
  /// **'提前 {seconds} 秒'**
  String timelineOffsetEarlier(Object seconds);

  /// No description provided for @timelineOffsetLater.
  ///
  /// In zh, this message translates to:
  /// **'延后 {seconds} 秒'**
  String timelineOffsetLater(Object seconds);

  /// No description provided for @timelineOffsetCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前偏移：0.0 秒'**
  String get timelineOffsetCurrent;

  /// No description provided for @enterAcoustidApiKeyTitle.
  ///
  /// In zh, this message translates to:
  /// **'填写 AcoustID API Key'**
  String get enterAcoustidApiKeyTitle;

  /// No description provided for @acoustidApiKeyDescription.
  ///
  /// In zh, this message translates to:
  /// **'用于音频指纹识别。留空后会恢复使用应用内置的默认 key。'**
  String get acoustidApiKeyDescription;

  /// No description provided for @acoustidApiKeyHint.
  ///
  /// In zh, this message translates to:
  /// **'粘贴你的 AcoustID API Key'**
  String get acoustidApiKeyHint;

  /// No description provided for @apiKey.
  ///
  /// In zh, this message translates to:
  /// **'API Key'**
  String get apiKey;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @enterLyricsTitle.
  ///
  /// In zh, this message translates to:
  /// **'填写歌词'**
  String get enterLyricsTitle;

  /// No description provided for @lyricsInputHint.
  ///
  /// In zh, this message translates to:
  /// **'在这里粘贴或输入歌词，支持多行文本'**
  String get lyricsInputHint;

  /// No description provided for @enterGoogleAiStudioApiKeyTitle.
  ///
  /// In zh, this message translates to:
  /// **'填写 Google AI Studio API Key'**
  String get enterGoogleAiStudioApiKeyTitle;

  /// No description provided for @googleAiStudioApiKeyDescription.
  ///
  /// In zh, this message translates to:
  /// **'用于 Google AI Studio 的歌词生成、时间轴生成和翻译。'**
  String get googleAiStudioApiKeyDescription;

  /// No description provided for @pasteGoogleAiStudioApiKey.
  ///
  /// In zh, this message translates to:
  /// **'粘贴 Google AI Studio API Key'**
  String get pasteGoogleAiStudioApiKey;

  /// No description provided for @enterOpenRouterApiKeyTitle.
  ///
  /// In zh, this message translates to:
  /// **'填写 OpenRouter API Key'**
  String get enterOpenRouterApiKeyTitle;

  /// No description provided for @openRouterApiKeyDescription.
  ///
  /// In zh, this message translates to:
  /// **'用于 OpenRouter 的歌词生成和时间轴生成，翻译始终走 Gemini。'**
  String get openRouterApiKeyDescription;

  /// No description provided for @pasteOpenRouterApiKey.
  ///
  /// In zh, this message translates to:
  /// **'粘贴 OpenRouter API Key'**
  String get pasteOpenRouterApiKey;

  /// No description provided for @enterGeminiApiKeyTitle.
  ///
  /// In zh, this message translates to:
  /// **'填写 Gemini API Key'**
  String get enterGeminiApiKeyTitle;

  /// No description provided for @geminiApiKeyDescription.
  ///
  /// In zh, this message translates to:
  /// **'用于歌词翻译。'**
  String get geminiApiKeyDescription;

  /// No description provided for @pasteGeminiApiKey.
  ///
  /// In zh, this message translates to:
  /// **'粘贴 Gemini API Key'**
  String get pasteGeminiApiKey;

  /// No description provided for @testConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get testConnection;

  /// No description provided for @enterApiKey.
  ///
  /// In zh, this message translates to:
  /// **'请输入 API key。'**
  String get enterApiKey;

  /// No description provided for @testingConnection.
  ///
  /// In zh, this message translates to:
  /// **'正在测试连接...'**
  String get testingConnection;

  /// No description provided for @getKey.
  ///
  /// In zh, this message translates to:
  /// **'获取key'**
  String get getKey;

  /// No description provided for @editSongTagsTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑歌曲标签'**
  String get editSongTagsTitle;

  /// No description provided for @editSongTagsDescription.
  ///
  /// In zh, this message translates to:
  /// **'修改后可以只保存到 App，也可以同步写回源文件。'**
  String get editSongTagsDescription;

  /// No description provided for @artistLabel.
  ///
  /// In zh, this message translates to:
  /// **'艺术家'**
  String get artistLabel;

  /// No description provided for @albumLabel.
  ///
  /// In zh, this message translates to:
  /// **'专辑'**
  String get albumLabel;

  /// No description provided for @trackNumberLabel.
  ///
  /// In zh, this message translates to:
  /// **'曲目号'**
  String get trackNumberLabel;

  /// No description provided for @trackNumberMustBeInteger.
  ///
  /// In zh, this message translates to:
  /// **'曲目号必须是整数'**
  String get trackNumberMustBeInteger;

  /// No description provided for @leaveBlankKeepsCurrentValue.
  ///
  /// In zh, this message translates to:
  /// **'留空则保留当前值'**
  String get leaveBlankKeepsCurrentValue;

  /// No description provided for @currentFileFormatCannotWriteBack.
  ///
  /// In zh, this message translates to:
  /// **'当前文件格式不支持写回源文件，只能保存到 App。'**
  String get currentFileFormatCannotWriteBack;

  /// No description provided for @leaveBlankDoesNotClearOriginalValue.
  ///
  /// In zh, this message translates to:
  /// **'提示：留空不会清空原值，而是沿用当前标签。'**
  String get leaveBlankDoesNotClearOriginalValue;

  /// No description provided for @saveToApp.
  ///
  /// In zh, this message translates to:
  /// **'保存到 App'**
  String get saveToApp;

  /// No description provided for @saveToSourceFileAndApp.
  ///
  /// In zh, this message translates to:
  /// **'保存到源文件和 App'**
  String get saveToSourceFileAndApp;

  /// No description provided for @saveToSourceFileFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存到源文件失败，请确认文件格式支持写入且文件未被占用'**
  String get saveToSourceFileFailed;

  /// No description provided for @saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败，请稍后重试'**
  String get saveFailed;

  /// No description provided for @apiKeySaved.
  ///
  /// In zh, this message translates to:
  /// **'{provider} API Key 已保存'**
  String apiKeySaved(Object provider);

  /// No description provided for @apiKeySavedAcoustid.
  ///
  /// In zh, this message translates to:
  /// **'AcoustID API Key 已保存'**
  String get apiKeySavedAcoustid;

  /// No description provided for @generalSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'界面'**
  String get generalSectionTitle;

  /// No description provided for @generalSectionDescription.
  ///
  /// In zh, this message translates to:
  /// **'这些选项会影响页面和播放界面的整体显示方式。'**
  String get generalSectionDescription;

  /// No description provided for @scanSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'扫描'**
  String get scanSectionTitle;

  /// No description provided for @scanSectionDescription.
  ///
  /// In zh, this message translates to:
  /// **'这些选项会控制媒体库扫描如何处理音频文件。'**
  String get scanSectionDescription;

  /// No description provided for @skipShortAudioDuringScan.
  ///
  /// In zh, this message translates to:
  /// **'扫描时跳过短音频'**
  String get skipShortAudioDuringScan;

  /// No description provided for @skipShortAudioDuringScanDescription.
  ///
  /// In zh, this message translates to:
  /// **'短于阈值的音频不会加入媒体库。'**
  String get skipShortAudioDuringScanDescription;

  /// No description provided for @shortAudioScanThreshold.
  ///
  /// In zh, this message translates to:
  /// **'短音频阈值'**
  String get shortAudioScanThreshold;

  /// No description provided for @shortAudioScanThresholdDescription.
  ///
  /// In zh, this message translates to:
  /// **'短于该时长的文件会被跳过。'**
  String get shortAudioScanThresholdDescription;

  /// No description provided for @shortAudioScanThresholdValue.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒'**
  String shortAudioScanThresholdValue(Object seconds);

  /// No description provided for @shortcutSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义快捷键'**
  String get shortcutSettingsTitle;

  /// No description provided for @shortcutSettingsDescription.
  ///
  /// In zh, this message translates to:
  /// **'点击后可以为播放器操作重新录制快捷键并保存。'**
  String get shortcutSettingsDescription;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @lyricsSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'歌词'**
  String get lyricsSectionTitle;

  /// No description provided for @lyricsSectionDescription.
  ///
  /// In zh, this message translates to:
  /// **'这里的配置只影响歌词生成和时间轴生成。'**
  String get lyricsSectionDescription;

  /// No description provided for @autoSwitchLyricsProvider.
  ///
  /// In zh, this message translates to:
  /// **'自动切换歌词供应商'**
  String get autoSwitchLyricsProvider;

  /// No description provided for @autoSwitchLyricsProviderEnabledDesc.
  ///
  /// In zh, this message translates to:
  /// **'开启后会先请求 Google AI Studio；主模型和备用模型都因 429 或 5xx 失败时，再自动切到 OpenRouter 继续请求。'**
  String get autoSwitchLyricsProviderEnabledDesc;

  /// No description provided for @autoSwitchLyricsProviderDisabledDesc.
  ///
  /// In zh, this message translates to:
  /// **'请先同时填写 Google AI Studio 和 OpenRouter 的 API Key，才可以开启自动切换。'**
  String get autoSwitchLyricsProviderDisabledDesc;

  /// No description provided for @lyricsAiProviderTitle.
  ///
  /// In zh, this message translates to:
  /// **'歌词生成 AI 提供方'**
  String get lyricsAiProviderTitle;

  /// No description provided for @lyricsAiProviderDescription.
  ///
  /// In zh, this message translates to:
  /// **'这里只影响歌词生成和时间轴生成。翻译始终走 Google AI Studio。'**
  String get lyricsAiProviderDescription;

  /// No description provided for @googleAiStudioApiKeySaved.
  ///
  /// In zh, this message translates to:
  /// **'Google AI Studio API Key 已保存'**
  String get googleAiStudioApiKeySaved;

  /// No description provided for @googleAiStudioApiKeyMissing.
  ///
  /// In zh, this message translates to:
  /// **'当前未保存 Google AI Studio key，歌词生成和时间轴生成会先弹窗提示。'**
  String get googleAiStudioApiKeyMissing;

  /// No description provided for @openRouterApiKeySaved.
  ///
  /// In zh, this message translates to:
  /// **'OpenRouter API Key 已保存'**
  String get openRouterApiKeySaved;

  /// No description provided for @openRouterApiKeyMissing.
  ///
  /// In zh, this message translates to:
  /// **'当前未保存 OpenRouter key，歌词生成和时间轴生成会先弹窗提示。'**
  String get openRouterApiKeyMissing;

  /// No description provided for @fill.
  ///
  /// In zh, this message translates to:
  /// **'填写'**
  String get fill;

  /// No description provided for @modify.
  ///
  /// In zh, this message translates to:
  /// **'修改'**
  String get modify;

  /// No description provided for @geminiModelsSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'Gemini 模型'**
  String get geminiModelsSectionTitle;

  /// No description provided for @geminiModelsSectionDescription.
  ///
  /// In zh, this message translates to:
  /// **'这些模型会用于 Google AI Studio 的歌词生成、时间轴生成以及歌词翻译。'**
  String get geminiModelsSectionDescription;

  /// No description provided for @primaryModelLabel.
  ///
  /// In zh, this message translates to:
  /// **'主模型'**
  String get primaryModelLabel;

  /// No description provided for @backupModelLabel.
  ///
  /// In zh, this message translates to:
  /// **'备用模型'**
  String get backupModelLabel;

  /// No description provided for @translationModelLabel.
  ///
  /// In zh, this message translates to:
  /// **'翻译模型'**
  String get translationModelLabel;

  /// No description provided for @fetching.
  ///
  /// In zh, this message translates to:
  /// **'获取中...'**
  String get fetching;

  /// No description provided for @fetchModelList.
  ///
  /// In zh, this message translates to:
  /// **'获取模型列表'**
  String get fetchModelList;

  /// No description provided for @restoreDefault.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get restoreDefault;

  /// No description provided for @acoustidSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'指纹识别'**
  String get acoustidSectionTitle;

  /// No description provided for @acoustidApiKeyTitle.
  ///
  /// In zh, this message translates to:
  /// **'AcoustID API Key'**
  String get acoustidApiKeyTitle;

  /// No description provided for @acoustidApiKeyHelp.
  ///
  /// In zh, this message translates to:
  /// **'AcoustID 用于音频指纹识别，建议使用你自己的 API Key。'**
  String get acoustidApiKeyHelp;

  /// No description provided for @acoustidApiKeySaved.
  ///
  /// In zh, this message translates to:
  /// **'AcoustID API Key 已保存'**
  String get acoustidApiKeySaved;

  /// No description provided for @acoustidApiKeyDefault.
  ///
  /// In zh, this message translates to:
  /// **'当前使用应用内置的默认 key，建议申请你自己的 key 后替换。'**
  String get acoustidApiKeyDefault;

  /// No description provided for @applyForApiKey.
  ///
  /// In zh, this message translates to:
  /// **'申请 API key: https://acoustid.org/new-application'**
  String get applyForApiKey;

  /// No description provided for @queueTabBarFavoriteAdded.
  ///
  /// In zh, this message translates to:
  /// **'已加入收藏'**
  String get queueTabBarFavoriteAdded;

  /// No description provided for @queueTabBarFavoriteRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已取消收藏'**
  String get queueTabBarFavoriteRemoved;

  /// No description provided for @tagCompletion.
  ///
  /// In zh, this message translates to:
  /// **'歌曲标签补全'**
  String get tagCompletion;

  /// No description provided for @tagCompletionDescription.
  ///
  /// In zh, this message translates to:
  /// **'根据 AcoustID 和 MusicBrainz 结果匹配标签'**
  String get tagCompletionDescription;

  /// No description provided for @goToSettings.
  ///
  /// In zh, this message translates to:
  /// **'去设置页'**
  String get goToSettings;

  /// No description provided for @searchReleaseTitles.
  ///
  /// In zh, this message translates to:
  /// **'搜索 release 标题'**
  String get searchReleaseTitles;

  /// No description provided for @closeSearch.
  ///
  /// In zh, this message translates to:
  /// **'关闭搜索'**
  String get closeSearch;

  /// No description provided for @refreshResults.
  ///
  /// In zh, this message translates to:
  /// **'刷新结果'**
  String get refreshResults;

  /// No description provided for @filterMusicBrainzReleaseTitle.
  ///
  /// In zh, this message translates to:
  /// **'过滤 MusicBrainz release 标题'**
  String get filterMusicBrainzReleaseTitle;

  /// No description provided for @clearSearch.
  ///
  /// In zh, this message translates to:
  /// **'清空搜索'**
  String get clearSearch;

  /// No description provided for @localTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地标题'**
  String get localTitle;

  /// No description provided for @queryConditions.
  ///
  /// In zh, this message translates to:
  /// **'查询条件'**
  String get queryConditions;

  /// No description provided for @musicBrainzLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在查询 MusicBrainz'**
  String get musicBrainzLoading;

  /// No description provided for @musicBrainzLoadingWithResults.
  ///
  /// In zh, this message translates to:
  /// **'现有结果会先保留在面板里'**
  String get musicBrainzLoadingWithResults;

  /// No description provided for @musicBrainzLoadingHint.
  ///
  /// In zh, this message translates to:
  /// **'请稍候'**
  String get musicBrainzLoadingHint;

  /// No description provided for @musicBrainzQueryFailed.
  ///
  /// In zh, this message translates to:
  /// **'MusicBrainz 查询失败'**
  String get musicBrainzQueryFailed;

  /// No description provided for @musicBrainzNetworkErrorHint.
  ///
  /// In zh, this message translates to:
  /// **'MusicBrainz 请求失败，通常是网络连接不稳定、超时或被服务端拒绝。可以稍后重试。'**
  String get musicBrainzNetworkErrorHint;

  /// No description provided for @musicBrainzFilteredEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'当前过滤条件下没有包含该关键词的 release 标题。'**
  String get musicBrainzFilteredEmptyHint;

  /// No description provided for @musicBrainzEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'MusicBrainz 没有返回可用结果。可以放宽标题、艺人或专辑条件后再试一次。'**
  String get musicBrainzEmptyHint;

  /// No description provided for @musicBrainzEmptyMoreCompleteHint.
  ///
  /// In zh, this message translates to:
  /// **'可以稍后重试，或者确认当前歌曲标题/艺人信息是否更完整。'**
  String get musicBrainzEmptyMoreCompleteHint;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @noMatchingRelease.
  ///
  /// In zh, this message translates to:
  /// **'没有找到匹配的 release'**
  String get noMatchingRelease;

  /// No description provided for @noMatchingResults.
  ///
  /// In zh, this message translates to:
  /// **'没有找到匹配结果'**
  String get noMatchingResults;

  /// No description provided for @searchAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新搜索'**
  String get searchAgain;

  /// No description provided for @acoustidRecognitionRecords.
  ///
  /// In zh, this message translates to:
  /// **'AcoustID 识别记录'**
  String get acoustidRecognitionRecords;

  /// No description provided for @musicBrainzRecordings.
  ///
  /// In zh, this message translates to:
  /// **'MusicBrainz 录音'**
  String get musicBrainzRecordings;

  /// No description provided for @noExpandableReleaseGroups.
  ///
  /// In zh, this message translates to:
  /// **'没有可展开的发行版分组'**
  String get noExpandableReleaseGroups;

  /// No description provided for @noExpandableReleases.
  ///
  /// In zh, this message translates to:
  /// **'没有可展开的发行版'**
  String get noExpandableReleases;

  /// No description provided for @noMatchingResultHint.
  ///
  /// In zh, this message translates to:
  /// **'可以稍后重试，或者确认当前歌曲标题/艺人信息是否更完整。'**
  String get noMatchingResultHint;

  /// No description provided for @releaseCountLabel.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个发行版'**
  String releaseCountLabel(int count);

  /// No description provided for @recordingCountLabel.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条录音'**
  String recordingCountLabel(int count);

  /// No description provided for @trackCountShort.
  ///
  /// In zh, this message translates to:
  /// **'{count} 首'**
  String trackCountShort(int count);

  /// No description provided for @scoreLabel.
  ///
  /// In zh, this message translates to:
  /// **'评分 {score}'**
  String scoreLabel(int score);

  /// No description provided for @matchScoreLabel.
  ///
  /// In zh, this message translates to:
  /// **'匹配度 {score}%'**
  String matchScoreLabel(int score);

  /// No description provided for @editQueryCondition.
  ///
  /// In zh, this message translates to:
  /// **'编辑查询条件'**
  String get editQueryCondition;

  /// No description provided for @enterNewQueryText.
  ///
  /// In zh, this message translates to:
  /// **'输入新的查询文字'**
  String get enterNewQueryText;

  /// No description provided for @durationLabel.
  ///
  /// In zh, this message translates to:
  /// **'时长'**
  String get durationLabel;

  /// No description provided for @customShortcuts.
  ///
  /// In zh, this message translates to:
  /// **'自定义快捷键'**
  String get customShortcuts;

  /// No description provided for @pressShortcutCombo.
  ///
  /// In zh, this message translates to:
  /// **'请按下组合键'**
  String get pressShortcutCombo;

  /// No description provided for @clickToRecord.
  ///
  /// In zh, this message translates to:
  /// **'点击录制'**
  String get clickToRecord;

  /// No description provided for @searchingLyrics.
  ///
  /// In zh, this message translates to:
  /// **'正在查找歌词'**
  String get searchingLyrics;

  /// No description provided for @noLyrics.
  ///
  /// In zh, this message translates to:
  /// **'暂无歌词'**
  String get noLyrics;

  /// No description provided for @providerLabel.
  ///
  /// In zh, this message translates to:
  /// **'提供商'**
  String get providerLabel;

  /// No description provided for @modelLabel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get modelLabel;

  /// No description provided for @unspecified.
  ///
  /// In zh, this message translates to:
  /// **'未指定'**
  String get unspecified;

  /// No description provided for @targetTimeLabel.
  ///
  /// In zh, this message translates to:
  /// **'目标时间 {duration}'**
  String targetTimeLabel(String duration);

  /// No description provided for @songDeletedSkipped.
  ///
  /// In zh, this message translates to:
  /// **'歌曲已删除，已跳过'**
  String get songDeletedSkipped;

  /// No description provided for @songDeleted.
  ///
  /// In zh, this message translates to:
  /// **'歌曲已删除'**
  String get songDeleted;

  /// No description provided for @lyricsTaskUploading.
  ///
  /// In zh, this message translates to:
  /// **'上传中'**
  String get lyricsTaskUploading;

  /// No description provided for @lyricsTaskWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待就绪'**
  String get lyricsTaskWaiting;

  /// No description provided for @lyricsTaskRequesting.
  ///
  /// In zh, this message translates to:
  /// **'请求中'**
  String get lyricsTaskRequesting;

  /// No description provided for @lyricsTaskGenerating.
  ///
  /// In zh, this message translates to:
  /// **'生成中'**
  String get lyricsTaskGenerating;

  /// No description provided for @lyricsTaskRetrying.
  ///
  /// In zh, this message translates to:
  /// **'重试中'**
  String get lyricsTaskRetrying;

  /// No description provided for @lyricsTaskProcessing.
  ///
  /// In zh, this message translates to:
  /// **'正在处理'**
  String get lyricsTaskProcessing;

  /// No description provided for @unknownModel.
  ///
  /// In zh, this message translates to:
  /// **'未知模型'**
  String get unknownModel;

  /// No description provided for @selectedFolders.
  ///
  /// In zh, this message translates to:
  /// **'已选中 {count} 个目录'**
  String selectedFolders(int count);

  /// No description provided for @foldersDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {count} 个目录'**
  String foldersDeleted(int count);

  /// No description provided for @persistentAccessDenied.
  ///
  /// In zh, this message translates to:
  /// **'无法保存该目录的访问权限，请重新选择一次'**
  String get persistentAccessDenied;

  /// No description provided for @folderAddFailed.
  ///
  /// In zh, this message translates to:
  /// **'目录添加失败'**
  String get folderAddFailed;

  /// No description provided for @sleepTimer.
  ///
  /// In zh, this message translates to:
  /// **'睡眠定时器'**
  String get sleepTimer;

  /// No description provided for @sleepTimerRemaining.
  ///
  /// In zh, this message translates to:
  /// **'睡眠定时器 {duration}'**
  String sleepTimerRemaining(Object duration);

  /// No description provided for @unknownArtistOrAlbum.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get unknownArtistOrAlbum;

  /// No description provided for @pressAgainToExit.
  ///
  /// In zh, this message translates to:
  /// **'再按一次退出应用'**
  String get pressAgainToExit;

  /// No description provided for @tagCompletionSuccessWithCover.
  ///
  /// In zh, this message translates to:
  /// **'标签已补全并保存，封面已下载到临时目录'**
  String get tagCompletionSuccessWithCover;

  /// No description provided for @tagCompletionSuccess.
  ///
  /// In zh, this message translates to:
  /// **'标签已补全并保存'**
  String get tagCompletionSuccess;

  /// No description provided for @selectOnlineLyrics.
  ///
  /// In zh, this message translates to:
  /// **'选择在线歌词'**
  String get selectOnlineLyrics;

  /// No description provided for @increaseLyricsFont.
  ///
  /// In zh, this message translates to:
  /// **'增大歌词文字'**
  String get increaseLyricsFont;

  /// No description provided for @decreaseLyricsFont.
  ///
  /// In zh, this message translates to:
  /// **'减小歌词文字'**
  String get decreaseLyricsFont;

  /// No description provided for @restoreDefaultSize.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认大小'**
  String get restoreDefaultSize;

  /// No description provided for @searchingOnlineLyrics.
  ///
  /// In zh, this message translates to:
  /// **'正在查询在线歌词'**
  String get searchingOnlineLyrics;

  /// No description provided for @onlineLyricsResults.
  ///
  /// In zh, this message translates to:
  /// **'在线歌词结果'**
  String get onlineLyricsResults;

  /// No description provided for @untitledLyrics.
  ///
  /// In zh, this message translates to:
  /// **'未命名歌词'**
  String get untitledLyrics;

  /// No description provided for @hasTimeline.
  ///
  /// In zh, this message translates to:
  /// **'带时间轴'**
  String get hasTimeline;

  /// No description provided for @viewLyricsDetails.
  ///
  /// In zh, this message translates to:
  /// **'查看歌词详情'**
  String get viewLyricsDetails;

  /// No description provided for @lyricsDetails.
  ///
  /// In zh, this message translates to:
  /// **'歌词详情'**
  String get lyricsDetails;

  /// No description provided for @lyricsContent.
  ///
  /// In zh, this message translates to:
  /// **'歌词内容'**
  String get lyricsContent;

  /// No description provided for @noLyricsContent.
  ///
  /// In zh, this message translates to:
  /// **'无歌词内容'**
  String get noLyricsContent;

  /// No description provided for @queryContentLabel.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get queryContentLabel;

  /// No description provided for @yes.
  ///
  /// In zh, this message translates to:
  /// **'是'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In zh, this message translates to:
  /// **'否'**
  String get no;

  /// No description provided for @dropAddedSongs.
  ///
  /// In zh, this message translates to:
  /// **'已添加 {addedCount} 首歌曲'**
  String dropAddedSongs(int addedCount);

  /// No description provided for @dropAddedSongsWithExisting.
  ///
  /// In zh, this message translates to:
  /// **'已添加 {addedCount} 首歌曲，{existingCount} 首已存在'**
  String dropAddedSongsWithExisting(int addedCount, int existingCount);

  /// No description provided for @copyCover.
  ///
  /// In zh, this message translates to:
  /// **'复制封面到剪贴板'**
  String get copyCover;

  /// No description provided for @copyCoverSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已成功复制封面'**
  String get copyCoverSuccess;

  /// No description provided for @searchLyricsPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入歌名、歌手或歌词进行搜索'**
  String get searchLyricsPlaceholder;

  /// Share tab label
  ///
  /// In zh, this message translates to:
  /// **'共享'**
  String get share;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
