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

  /// Visualizer settings
  ///
  /// In zh, this message translates to:
  /// **'可视化设置'**
  String get visualizerSettings;

  /// Algorithm tab
  ///
  /// In zh, this message translates to:
  /// **'算法'**
  String get algorithm;

  /// Appearance tab
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get appearance;

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
  /// **'列表'**
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

  /// Immersive Tab Bar label
  ///
  /// In zh, this message translates to:
  /// **'沉浸式标签栏'**
  String get immersiveTabBar;

  /// Immersive Tab Bar description
  ///
  /// In zh, this message translates to:
  /// **'空闲 3 秒后隐藏导航栏'**
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

  /// No description provided for @playbackBackground.
  ///
  /// In zh, this message translates to:
  /// **'播放页背景'**
  String get playbackBackground;

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

  /// Enable Waveform Progress Bar description
  ///
  /// In zh, this message translates to:
  /// **'使用整首歌的波形图代替标准滑块'**
  String get enableWaveformProgressBarDescription;

  /// No description provided for @randomMode.
  ///
  /// In zh, this message translates to:
  /// **'随机模式'**
  String get randomMode;

  /// No description provided for @randomQueue.
  ///
  /// In zh, this message translates to:
  /// **'随机队列'**
  String get randomQueue;
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
