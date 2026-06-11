// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Pure Player';

  @override
  String get systemMediaLibrary => '系统媒体库';

  @override
  String get scanningDirectory => '正在扫描目录...';

  @override
  String filesPreprocessed(Object count) {
    return '预处理 $count ';
  }

  @override
  String filesDiscovered(Object count) {
    return '已发现 $count ';
  }

  @override
  String filesFullyProcessed(Object count) {
    return '完整处理 $count ';
  }

  @override
  String get directoryAddedSuccess => '目录添加成功';

  @override
  String get directoryAddedNoMusic => '目录已添加，但未发现可播放音频文件';

  @override
  String get scanDirectory => '扫描目录';

  @override
  String get sort => '排序';

  @override
  String get addRootDirectory => '添加根目录';

  @override
  String get goBack => '返回上一层';

  @override
  String get noMediaLibraryPermission => '未获得媒体库访问权限';

  @override
  String get grantPermission => '给予权限';

  @override
  String get needPermissionToScan => '需授予权限以扫描本地音乐';

  @override
  String get rebuildTagDatabase => '重建标签数据库';

  @override
  String get rebuildDatabase => '重建数据库';

  @override
  String get confirmRebuildDatabase =>
      '确定要手动刷新所有歌曲的标签信息吗？这可能需要一些时间来重新加载封面和元数据。';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确定';

  @override
  String get rebuildingDatabase => '正在重建歌曲标签数据库...';

  @override
  String get sortBy => '排序方式';

  @override
  String get sortScope => '作用域';

  @override
  String get sortOrder => '排序顺序';

  @override
  String get title => '标题';

  @override
  String get fileName => '文件名';

  @override
  String get trackNumber => '轨道号';

  @override
  String get ascending => '升序';

  @override
  String get descending => '降序';

  @override
  String get currentFolderScope => '当前目录';

  @override
  String get globalScope => '全局';

  @override
  String get visualizerSettings => '播放页设置';

  @override
  String get algorithm => '频谱';

  @override
  String get appearance => '外观';

  @override
  String get spectrumAppearanceGroup => '频谱外观';

  @override
  String get spectrumAdvancedOptions => '频谱高级选项';

  @override
  String get resetAlgorithm => '重置算法';

  @override
  String get resetAppearance => '重置外观';

  @override
  String get smoothing => '平滑系数 (Smoothing)';

  @override
  String get gravity => '重力系数 (Gravity)';

  @override
  String get logScale => '对数缩放 (Log Scale)';

  @override
  String get contrast => '对比度 (Contrast)';

  @override
  String get normalization => '归一化 (Normalization)';

  @override
  String get multiplier => '增益 (Multiplier)';

  @override
  String get skipHighFrequency => '跳过高频';

  @override
  String get frequencyGroups => '频率分组 (Frequency Groups)';

  @override
  String get aggregationMode => '聚合模式 (Aggregation Mode)';

  @override
  String get opacity => '透明度 (Opacity)';

  @override
  String get enableGradient => '启用渐变色';

  @override
  String get startColor => '起始颜色';

  @override
  String get endColor => '结束颜色';

  @override
  String get gradientRangeStop1 => '渐变范围 Stop 1';

  @override
  String get gradientRangeStop2 => '渐变范围 Stop 2';

  @override
  String get gradientRepeatMode => '渐变重复模式 (TileMode)';

  @override
  String get color => '颜色';

  @override
  String get followCoverColor => '跟随封面变色';

  @override
  String get selectColor => '选择颜色';

  @override
  String get volume => '音量';

  @override
  String get clearQueue => '清空队列';

  @override
  String get confirmClearQueue => '确定要清空当前队列吗？';

  @override
  String get queueCleared => '队列已清空';

  @override
  String get queue => '队列';

  @override
  String get queueEmpty => '队列为空';

  @override
  String selectedSongs(int count) {
    return '已选择 $count 首';
  }

  @override
  String get unknownArtist => '未知艺术家';

  @override
  String deletedSongs(int count) {
    return '已删除 $count 首歌曲';
  }

  @override
  String get delete => '删除';

  @override
  String get createPlaylist => '创建播放列表';

  @override
  String get playlistName => '播放列表名称';

  @override
  String get enterPlaylistName => '请输入播放列表名称';

  @override
  String get renamePlaylist => '重命名播放列表';

  @override
  String get deletePlaylist => '删除播放列表';

  @override
  String confirmDeletePlaylist(String name) {
    return '确定要删除播放列表\"$name\"吗？';
  }

  @override
  String get addToPlaylist => '添加到播放列表';

  @override
  String get selectAll => '全选';

  @override
  String get addToQueue => '添加到队列';

  @override
  String get addedToQueue => '已添加到队列';

  @override
  String songCount(int count) {
    return '$count 首歌曲';
  }

  @override
  String addedToPlaylist(int count, String playlist) {
    return '已添加 $count 首歌曲到$playlist';
  }

  @override
  String get createNewList => '新建列表';

  @override
  String createdPlaylist(String name, int count) {
    return '已创建播放列表\"$name\"并添加 $count 首歌曲';
  }

  @override
  String get rename => '重命名';

  @override
  String get playlist => '播放列表';

  @override
  String get mostPlayed => '最多播放';

  @override
  String get recentlyAdded => '最近添加';

  @override
  String get albums => '专辑';

  @override
  String get artists => '艺术家';

  @override
  String get mostPlayedDescription => '按有效播放次数排序';

  @override
  String get recentlyAddedDescription => '按进入媒体库的时间排序';

  @override
  String get allTime => '全部时间';

  @override
  String get pastWeek => '过去一周';

  @override
  String get pastMonth => '过去一个月';

  @override
  String get past90Days => '过去三个月';

  @override
  String get noPlayHistory => '还没有播放记录';

  @override
  String get noPlayHistoryInRange => '这个时间范围内还没有播放记录';

  @override
  String get noRecentlyAddedSongs => '媒体库中还没有歌曲';

  @override
  String get noRecentlyAddedInRange => '这个时间范围内没有新添加的歌曲';

  @override
  String get addedOn => '添加时间';

  @override
  String get lastPlayed => '最近播放';

  @override
  String playCountLabel(int count) {
    return '$count 次';
  }

  @override
  String get playAll => '播放全部';

  @override
  String get shufflePlay => '随机播放';

  @override
  String get noAlbums => '还没有可显示的专辑';

  @override
  String get noArtists => '还没有可显示的艺术家';

  @override
  String get searchAlbums => '搜索专辑或艺术家';

  @override
  String get searchArtists => '搜索艺术家';

  @override
  String get albumSort => '排序';

  @override
  String get sortArtistAsc => '艺术家 A-Z';

  @override
  String get sortTitleAsc => '专辑名 A-Z';

  @override
  String get sortTrackCount => '歌曲数量';

  @override
  String get sortDuration => '总时长';

  @override
  String get sortRecentAdded => '最近添加';

  @override
  String get sortAscending => '升序';

  @override
  String get sortDescending => '降序';

  @override
  String get playNext => '下一首播放';

  @override
  String get addToFavorites => '加入收藏';

  @override
  String get removeFromFavorites => '取消收藏';

  @override
  String get viewAlbumDetails => '查看专辑详情';

  @override
  String get viewArtistDetails => '查看艺术家详情';

  @override
  String get openFileLocation => '打开文件所在位置';

  @override
  String get copyAlbumTitle => '复制专辑名';

  @override
  String get copyArtistName => '复制艺术家名';

  @override
  String albumCount(int count) {
    return '$count 张专辑';
  }

  @override
  String get emptyList => '列表为空';

  @override
  String get dragToAddMusic => '拖入文件或文件夹以添加音乐';

  @override
  String get unknownAlbum => '未知专辑';

  @override
  String get managePlaylists => '管理播放列表';

  @override
  String get createNewPlaylist => '创建新播放列表';

  @override
  String get defaultList => '默认列表';

  @override
  String get playbackMode => '播放模式';

  @override
  String get playbackOptions => '播放选项';

  @override
  String get setVisualizerDisplay => '设置频谱显示';

  @override
  String get noPlaybackContent => '当前没有播放内容';

  @override
  String get file => '文件';

  @override
  String get play => '播放';

  @override
  String get list => '媒体库';

  @override
  String get queueTab => '队列';

  @override
  String get more => '更多';

  @override
  String get settings => '设置';

  @override
  String get themeMode => '主题';

  @override
  String get themeModeSystem => '跟随系统';

  @override
  String get themeModeLight => '亮色';

  @override
  String get themeModeDark => '暗色';

  @override
  String get immersiveTabBar => '沉浸式标签栏';

  @override
  String get immersiveTabBarDescription => '鼠标移动时显示导航栏，3 秒无操作后隐藏';

  @override
  String get sampleStride => '采样步长';

  @override
  String get sampleStrideDescription => '值越大扫描越快但波形精度越低 (默认: 4)';

  @override
  String get waveformSegments => '波形分段';

  @override
  String get waveformSegmentsDescription => '要显示的波形柱数量 (默认: 80)';

  @override
  String get showDeveloperOptions => '显示开发人员选项';

  @override
  String get playbackBackground => '播放页背景';

  @override
  String get playbackRadialGradient => '中心暗色渐变';

  @override
  String get blurIntensity => '模糊强度';

  @override
  String get blurredArtwork => '模糊封面 (默认)';

  @override
  String get dynamicMesh => '动态流变 (Apple Music 效果)';

  @override
  String get solidColor => '纯色';

  @override
  String get customImage => '自定义图片';

  @override
  String get presetColors => '预设颜色';

  @override
  String get customColor => '自定义颜色';

  @override
  String get uploadImage => '上传图片';

  @override
  String get normalOpacity => '常规暗色层不透明度';

  @override
  String get lyricsOpacity => '歌词暗色层不透明度';

  @override
  String get chooseImageError => '选择图片失败';

  @override
  String get noImageSelected => '未选择图片';

  @override
  String get unknown => '未知';

  @override
  String get playlistModeSingle => '单曲播放';

  @override
  String get playlistModeSingleLoop => '单曲循环';

  @override
  String get playlistModeQueue => '播放列表';

  @override
  String get playlistModeQueueLoop => '列表循环';

  @override
  String get playlistModeAutoQueueLoop => '自动列表循环';

  @override
  String get visualizer => '可视化';

  @override
  String get previous => '上一首';

  @override
  String get next => '下一首';

  @override
  String get pause => '暂停';

  @override
  String get autoMode => '自动模式';

  @override
  String get advancedOptions => '高级选项';

  @override
  String get spectrumQuantity => '频谱数量';

  @override
  String get speed => '速度';

  @override
  String get quantityHigh => '多';

  @override
  String get quantityMedium => '中';

  @override
  String get quantityLow => '少';

  @override
  String get speedFast => '快';

  @override
  String get speedMedium => '中';

  @override
  String get speedSlow => '慢';

  @override
  String get portraitFrequencyGroups => '竖屏频谱数量';

  @override
  String get landscapeFrequencyGroups => '横屏频谱数量';

  @override
  String get portraitGap => '竖屏频谱间距';

  @override
  String get landscapeGap => '横屏频谱间距';

  @override
  String get enableWaveformProgressBar => '启用波形进度条';

  @override
  String get enableWaveformProgressBarDescription => '使用整首歌的波形图代替标准滑块';

  @override
  String get randomMode => '随机模式';

  @override
  String get randomHistory => '随机历史';

  @override
  String get randomRange => '随机范围';

  @override
  String get randomMethod => '随机方式';

  @override
  String get currentQueue => '当前队列';

  @override
  String get globalRange => '全局 (包含所有列表歌曲)';

  @override
  String get completeRandom => '完全随机';

  @override
  String get shuffleRandom => '洗牌随机';

  @override
  String get randomQueue => '随机队列';

  @override
  String get notSelected => '未选择音乐';

  @override
  String get saveTagsToFile => '保存标签到文件';

  @override
  String get saveCurrentTagsToFile => '保存当前歌曲标签到文件';

  @override
  String get saveQueueTagsToFile => '保存队列中所有标签到文件';

  @override
  String get tagsSaved => '标签保存成功';

  @override
  String tagsSavedCount(Object count) {
    return '标签已保存 ($count 首)';
  }

  @override
  String get tagsSaveFailed => '保存标签失败';

  @override
  String tagsSaveFailedCount(Object count) {
    return '$count 首保存失败';
  }

  @override
  String unsupportedFormat(Object count) {
    return '$count 首歌曲格式不支持保存标签 (OGG/Opus)';
  }

  @override
  String get unsupportedFormatSingle => '此格式 (OGG/Opus) 不支持保存标签';

  @override
  String get savingTags => '正在保存标签...';

  @override
  String get noModifiedTagsToSave => '没有需要保存的已修改标签';

  @override
  String get clearPlaylist => '清空列表';

  @override
  String get copyTitle => '复制标题';

  @override
  String get transcodeAction => '转码';

  @override
  String get transcodeSectionTitle => '音频转码';

  @override
  String get transcodeSectionDescription => '设置默认输出格式和质量预设。';

  @override
  String get transcodeDefaultFormat => '默认输出格式';

  @override
  String get transcodeDefaultQuality => '默认质量预设';

  @override
  String get transcodeTitle => '音频转码';

  @override
  String transcodeSongCount(int count) {
    return '$count 首歌曲';
  }

  @override
  String transcodeCompletedCount(int count) {
    return '已完成 $count 个转码任务';
  }

  @override
  String transcodeCompletedWithFailures(int success, int total, int failed) {
    return '已完成 $success/$total 个转码任务，失败 $failed 个';
  }

  @override
  String get transcodeFailedGeneric => '转码失败';

  @override
  String get transcodePreparing => '正在准备转码...';

  @override
  String transcodeProgress(int current, int total) {
    return '正在转码 $current/$total';
  }

  @override
  String get transcoding => '转码中...';

  @override
  String get startTranscode => '开始转码';

  @override
  String transcodeEngine(Object engine) {
    return '引擎：$engine';
  }

  @override
  String get transcodeUsingSystemFfmpeg => '使用系统 PATH 中的 ffmpeg。';

  @override
  String transcodeUsingCustomFfmpeg(Object path) {
    return '使用自定义 ffmpeg：$path';
  }

  @override
  String get transcodeFormat => '输出格式';

  @override
  String get transcodeQualityPreset => '质量预设';

  @override
  String get transcodeQualityLow => '低';

  @override
  String get transcodeQualityMedium => '中';

  @override
  String get transcodeQualityHigh => '高';

  @override
  String get transcodeQualityExtreme => '最高';

  @override
  String get transcodeLosslessPresetHint => '当前无损格式不使用质量档位和码率控制模式。';

  @override
  String get transcodeAdvancedOptions => '高级选项';

  @override
  String get transcodeAdvancedCustomized => '高级参数已被手动修改';

  @override
  String get transcodeAdvancedFollowingPreset => '高级参数跟随当前预设';

  @override
  String get transcodeLosslessAdvancedHint => '当前无损格式仅保留与源文件相关的高级选项。';

  @override
  String get transcodeBitRateInvalid => '请输入有效的比特率';

  @override
  String get transcodeBitRate => '比特率';

  @override
  String get transcodeBitRateMode => '码率控制模式';

  @override
  String get transcodeEncodingEngine => '编码引擎';

  @override
  String get transcodeSystemEncoder => 'Media3 (系统)';

  @override
  String get transcodeFfmpegRustEncoder => 'FFmpeg (Rust)';

  @override
  String get transcodeAacEncoder => 'AAC 编码器';

  @override
  String get transcodeSampleRate => '采样率';

  @override
  String get transcodeChannels => '声道';

  @override
  String get transcodeResetToPreset => '重置为当前预设';

  @override
  String get transcodeResetLosslessOptions => '重置无损选项';

  @override
  String get transcodeOutputDirectory => '输出目录';

  @override
  String get transcodeOutputPreview => '预览';

  @override
  String get transcodeChooseDirectory => '选择目录';

  @override
  String get transcodeUseSourceDirectory => '使用源文件目录';

  @override
  String get transcodeKeepSource => '保持源文件';

  @override
  String get transcodeMono => '单声道';

  @override
  String get transcodeStereo => '双声道';

  @override
  String get openFolderLocation => '打开文件夹所在位置';

  @override
  String get songTagsSavedToSourceFileAndApp => '歌曲标签已保存到源文件和 App';

  @override
  String get songTagsSavedToApp => '歌曲标签已保存到 App';

  @override
  String get durationZero => '0:00';

  @override
  String get generateLyrics => '生成歌词';

  @override
  String get generateTimeline => '生成时间轴';

  @override
  String get queueGenerateLyrics => '排队生成';

  @override
  String get pauseAutoScroll => '暂停自动滚动';

  @override
  String get resumeAutoScroll => '恢复自动滚动';

  @override
  String get translateLyrics => '翻译歌词';

  @override
  String get clearLyricsCache => '清除当前歌词缓存';

  @override
  String get clearTranslationCache => '清除当前翻译缓存';

  @override
  String get requery => '重新查询';

  @override
  String get sleepTimerTitle => '睡眠定时器';

  @override
  String get sleepTimerDescription => '选择倒计时，时间到后会暂停播放。';

  @override
  String get sleepTimerRunningTitle => '睡眠定时器运行中';

  @override
  String get sleepTimerRunningDescription => '倒计时结束后会自动暂停当前播放。';

  @override
  String get remainingTime => '剩余时间';

  @override
  String get startCountdown => '开始倒计时';

  @override
  String get end => '结束';

  @override
  String get equalizer => '均衡器';

  @override
  String get equalizerEnabledStatus => '已启用高保真调节';

  @override
  String get equalizerDisabledStatus => '已禁用';

  @override
  String get bassBoost => '低音增强';

  @override
  String get preampGain => '前置增益';

  @override
  String get reset => '重置';

  @override
  String get close => '关闭';

  @override
  String get timelineAdjustmentTitle => '手动调整时间轴';

  @override
  String get timelineAdjustmentDescription => '向右拖动会让歌词整体延后，向左拖动会让歌词整体提前。';

  @override
  String timelineOffsetEarlier(Object seconds) {
    return '提前 $seconds 秒';
  }

  @override
  String timelineOffsetLater(Object seconds) {
    return '延后 $seconds 秒';
  }

  @override
  String get timelineOffsetCurrent => '当前偏移：0.0 秒';

  @override
  String get enterAcoustidApiKeyTitle => '填写 AcoustID API Key';

  @override
  String get acoustidApiKeyDescription => '用于音频指纹识别。留空后会恢复使用应用内置的默认 key。';

  @override
  String get acoustidApiKeyHint => '粘贴你的 AcoustID API Key';

  @override
  String get apiKey => 'API Key';

  @override
  String get save => '保存';

  @override
  String get enterLyricsTitle => '填写歌词';

  @override
  String get lyricsInputHint => '在这里粘贴或输入歌词，支持多行文本';

  @override
  String get enterGoogleAiStudioApiKeyTitle => '填写 Google AI Studio API Key';

  @override
  String get googleAiStudioApiKeyDescription =>
      '用于 Google AI Studio 的歌词生成、时间轴生成和翻译。';

  @override
  String get pasteGoogleAiStudioApiKey => '粘贴 Google AI Studio API Key';

  @override
  String get enterOpenRouterApiKeyTitle => '填写 OpenRouter API Key';

  @override
  String get openRouterApiKeyDescription =>
      '用于 OpenRouter 的歌词生成和时间轴生成，翻译始终走 Gemini。';

  @override
  String get pasteOpenRouterApiKey => '粘贴 OpenRouter API Key';

  @override
  String get enterGeminiApiKeyTitle => '填写 Gemini API Key';

  @override
  String get geminiApiKeyDescription => '用于歌词翻译。';

  @override
  String get pasteGeminiApiKey => '粘贴 Gemini API Key';

  @override
  String get testConnection => '测试连接';

  @override
  String get enterApiKey => '请输入 API key。';

  @override
  String get testingConnection => '正在测试连接...';

  @override
  String get getKey => '获取key';

  @override
  String get editSongTagsTitle => '编辑歌曲标签';

  @override
  String get editSongTagsDescription => '修改后可以只保存到 App，也可以同步写回源文件。';

  @override
  String get artistLabel => '艺术家';

  @override
  String get albumLabel => '专辑';

  @override
  String get trackNumberLabel => '曲目号';

  @override
  String get trackNumberMustBeInteger => '曲目号必须是整数';

  @override
  String get leaveBlankKeepsCurrentValue => '留空则保留当前值';

  @override
  String get currentFileFormatCannotWriteBack => '当前文件格式不支持写回源文件，只能保存到 App。';

  @override
  String get leaveBlankDoesNotClearOriginalValue => '提示：留空不会清空原值，而是沿用当前标签。';

  @override
  String get saveToApp => '保存到 App';

  @override
  String get saveToSourceFileAndApp => '保存到源文件和 App';

  @override
  String get saveToSourceFileFailed => '保存到源文件失败，请确认文件格式支持写入且文件未被占用';

  @override
  String get saveFailed => '保存失败，请稍后重试';

  @override
  String apiKeySaved(Object provider) {
    return '$provider API Key 已保存';
  }

  @override
  String get apiKeySavedAcoustid => 'AcoustID API Key 已保存';

  @override
  String get generalSectionTitle => '界面';

  @override
  String get generalSectionDescription => '这些选项会影响页面和播放界面的整体显示方式。';

  @override
  String get scanSectionTitle => '扫描';

  @override
  String get scanSectionDescription => '这些选项会控制媒体库扫描如何处理音频文件。';

  @override
  String get skipShortAudioDuringScan => '扫描时跳过短音频';

  @override
  String get skipShortAudioDuringScanDescription => '短于阈值的音频不会加入媒体库。';

  @override
  String get shortAudioScanThreshold => '短音频阈值';

  @override
  String get shortAudioScanThresholdDescription => '短于该时长的文件会被跳过。';

  @override
  String shortAudioScanThresholdValue(Object seconds) {
    return '$seconds 秒';
  }

  @override
  String get shortcutSettingsTitle => '自定义快捷键';

  @override
  String get shortcutSettingsDescription => '点击后可以为播放器操作重新录制快捷键并保存。';

  @override
  String get edit => '编辑';

  @override
  String get lyricsSectionTitle => '歌词';

  @override
  String get lyricsSectionDescription => '这里的配置只影响歌词生成和时间轴生成。';

  @override
  String get lyricsTranslationTargetLanguageLabel => '翻译目标语言';

  @override
  String get lyricsTranslationTargetLanguageDescription => '默认跟随系统语言，也可以单独指定。';

  @override
  String get followSystemLanguage => '跟随系统';

  @override
  String get autoSwitchLyricsProvider => '自动切换歌词供应商';

  @override
  String get autoSwitchLyricsProviderEnabledDesc =>
      '开启后会先请求 Google AI Studio；主模型和备用模型都因 429 或 5xx 失败时，再自动切到 OpenRouter 继续请求。';

  @override
  String get autoSwitchLyricsProviderDisabledDesc =>
      '请先同时填写 Google AI Studio 和 OpenRouter 的 API Key，才可以开启自动切换。';

  @override
  String get lyricsAiProviderTitle => '歌词生成 AI 提供方';

  @override
  String get lyricsAiProviderDescription =>
      '这里只影响歌词生成和时间轴生成。翻译始终走 Google AI Studio。';

  @override
  String get googleAiStudioApiKeySaved => 'Google AI Studio API Key 已保存';

  @override
  String get googleAiStudioApiKeyMissing =>
      '当前未保存 Google AI Studio key，歌词生成和时间轴生成会先弹窗提示。';

  @override
  String get openRouterApiKeySaved => 'OpenRouter API Key 已保存';

  @override
  String get openRouterApiKeyMissing =>
      '当前未保存 OpenRouter key，歌词生成和时间轴生成会先弹窗提示。';

  @override
  String get apiKeySavedStatus => '已保存';

  @override
  String get apiKeyMissingStatus => '未填写';

  @override
  String get platformApiKeysSectionTitle => '平台 API Key';

  @override
  String get fill => '填写';

  @override
  String get modify => '修改';

  @override
  String get geminiModelsSectionTitle => '选择模型';

  @override
  String get geminiModelsSectionDescription =>
      '这些模型会用于 Google AI Studio 的歌词生成、时间轴生成以及歌词翻译。';

  @override
  String get primaryModelLabel => '主模型';

  @override
  String get backupModelLabel => '备用模型';

  @override
  String get translationModelLabel => '翻译模型';

  @override
  String get fetching => '获取中...';

  @override
  String get fetchModelList => '获取模型列表';

  @override
  String get restoreDefault => '恢复默认';

  @override
  String get acoustidSectionTitle => '指纹识别';

  @override
  String get acoustidApiKeyTitle => 'AcoustID API Key';

  @override
  String get acoustidApiKeyHelp => 'AcoustID 用于音频指纹识别，建议使用你自己的 API Key。';

  @override
  String get acoustidApiKeySaved => 'AcoustID API Key 已保存';

  @override
  String get acoustidApiKeyDefault => '当前使用应用内置的默认 key，建议申请你自己的 key 后替换。';

  @override
  String get applyForApiKey =>
      '申请 API key: https://acoustid.org/new-application';

  @override
  String get queueTabBarFavoriteAdded => '已加入收藏';

  @override
  String get queueTabBarFavoriteRemoved => '已取消收藏';

  @override
  String get tagCompletion => '歌曲标签补全';

  @override
  String get tagCompletionDescription => '根据 AcoustID 和 MusicBrainz 结果匹配标签';

  @override
  String get goToSettings => '去设置页';

  @override
  String get searchReleaseTitles => '搜索 release 标题';

  @override
  String get closeSearch => '关闭搜索';

  @override
  String get refreshResults => '刷新结果';

  @override
  String get filterMusicBrainzReleaseTitle => '过滤 MusicBrainz release 标题';

  @override
  String get clearSearch => '清空搜索';

  @override
  String get localTitle => '本地标题';

  @override
  String get queryConditions => '查询条件';

  @override
  String get musicBrainzLoading => '正在查询 MusicBrainz';

  @override
  String get musicBrainzLoadingWithResults => '现有结果会先保留在面板里';

  @override
  String get musicBrainzLoadingHint => '请稍候';

  @override
  String get musicBrainzQueryFailed => 'MusicBrainz 查询失败';

  @override
  String get musicBrainzNetworkErrorHint =>
      'MusicBrainz 请求失败，通常是网络连接不稳定、超时或被服务端拒绝。可以稍后重试。';

  @override
  String get musicBrainzFilteredEmptyHint => '当前过滤条件下没有包含该关键词的 release 标题。';

  @override
  String get musicBrainzEmptyHint =>
      'MusicBrainz 没有返回可用结果。可以放宽标题、艺人或专辑条件后再试一次。';

  @override
  String get musicBrainzEmptyMoreCompleteHint => '可以稍后重试，或者确认当前歌曲标题/艺人信息是否更完整。';

  @override
  String get retry => '重试';

  @override
  String get noMatchingRelease => '没有找到匹配的 release';

  @override
  String get noMatchingResults => '没有找到匹配结果';

  @override
  String get searchAgain => '重新搜索';

  @override
  String get acoustidRecognitionRecords => 'AcoustID 识别记录';

  @override
  String get musicBrainzRecordings => 'MusicBrainz 录音';

  @override
  String get noExpandableReleaseGroups => '没有可展开的发行版分组';

  @override
  String get noExpandableReleases => '没有可展开的发行版';

  @override
  String get noMatchingResultHint => '可以稍后重试，或者确认当前歌曲标题/艺人信息是否更完整。';

  @override
  String releaseCountLabel(int count) {
    return '$count 个发行版';
  }

  @override
  String recordingCountLabel(int count) {
    return '$count 条录音';
  }

  @override
  String trackCountShort(int count) {
    return '$count 首';
  }

  @override
  String scoreLabel(int score) {
    return '评分 $score';
  }

  @override
  String matchScoreLabel(int score) {
    return '匹配度 $score%';
  }

  @override
  String get editQueryCondition => '编辑查询条件';

  @override
  String get enterNewQueryText => '输入新的查询文字';

  @override
  String get durationLabel => '时长';

  @override
  String get customShortcuts => '自定义快捷键';

  @override
  String get pressShortcutCombo => '请按下组合键';

  @override
  String get clickToRecord => '点击录制';

  @override
  String get searchingLyrics => '正在查找歌词';

  @override
  String get noLyrics => '暂无歌词';

  @override
  String get providerLabel => '提供商';

  @override
  String get modelLabel => '模型';

  @override
  String get unspecified => '未指定';

  @override
  String targetTimeLabel(String duration) {
    return '目标时间 $duration';
  }

  @override
  String get songDeletedSkipped => '歌曲已删除，已跳过';

  @override
  String get songDeleted => '歌曲已删除';

  @override
  String get lyricsTaskUploading => '上传中';

  @override
  String get lyricsTaskWaiting => '等待就绪';

  @override
  String get lyricsTaskRequesting => '请求中';

  @override
  String get lyricsTaskGenerating => '生成中';

  @override
  String get lyricsTaskRetrying => '重试中';

  @override
  String get lyricsTaskProcessing => '正在处理';

  @override
  String get unknownModel => '未知模型';

  @override
  String selectedFolders(int count) {
    return '已选中 $count 个目录';
  }

  @override
  String foldersDeleted(int count) {
    return '已删除 $count 个目录';
  }

  @override
  String get persistentAccessDenied => '无法保存该目录的访问权限，请重新选择一次';

  @override
  String get folderAddFailed => '目录添加失败';

  @override
  String get sleepTimer => '睡眠定时器';

  @override
  String sleepTimerRemaining(Object duration) {
    return '睡眠定时器 $duration';
  }

  @override
  String get unknownArtistOrAlbum => '未知';

  @override
  String get pressAgainToExit => '再按一次退出应用';

  @override
  String get tagCompletionSuccessWithCover => '标签已补全并保存，封面已下载到临时目录';

  @override
  String get tagCompletionSuccess => '标签已补全并保存';

  @override
  String get selectOnlineLyrics => '选择在线歌词';

  @override
  String get increaseLyricsFont => '增大歌词文字';

  @override
  String get decreaseLyricsFont => '减小歌词文字';

  @override
  String get restoreDefaultSize => '恢复默认大小';

  @override
  String get searchingOnlineLyrics => '正在查询在线歌词';

  @override
  String get onlineLyricsResults => '在线歌词结果';

  @override
  String get untitledLyrics => '未命名歌词';

  @override
  String get hasTimeline => '带时间轴';

  @override
  String get viewLyricsDetails => '查看歌词详情';

  @override
  String get lyricsDetails => '歌词详情';

  @override
  String get lyricsContent => '歌词内容';

  @override
  String get noLyricsContent => '无歌词内容';

  @override
  String get queryContentLabel => '内容';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String dropAddedSongs(int addedCount) {
    return '已添加 $addedCount 首歌曲';
  }

  @override
  String dropAddedSongsWithExisting(int addedCount, int existingCount) {
    return '已添加 $addedCount 首歌曲，$existingCount 首已存在';
  }

  @override
  String get copyCover => '复制封面到剪贴板';

  @override
  String get copyCoverSuccess => '已成功复制封面';

  @override
  String get searchLyricsPlaceholder => '输入歌名、歌手或歌词进行搜索';

  @override
  String get share => '共享';

  @override
  String get windowsSettingsTitle => 'Windows 专属设置';

  @override
  String get fileAssociationTitle => '文件打开方式关联';

  @override
  String get fileAssociationDescription =>
      '将常见的音乐格式（mp3, flac, wav 等）关联到此应用，支持双击直接打开播放。';

  @override
  String get associateButton => '一键关联';

  @override
  String get disassociateButton => '取消关联';

  @override
  String get associationSuccess =>
      '关联成功！若双击文件未生效，请在 Windows 系统设置的【默认应用】中选择 VibeFlow。';

  @override
  String get disassociationSuccess => '已成功清除文件关联。';

  @override
  String associationFailed(Object error) {
    return '关联失败：$error';
  }

  @override
  String get onboardingTitle => '欢迎使用 VibeFlow';

  @override
  String get onboardingSubtitle => '只需几个简单步骤，即可开启你的音乐之旅。';

  @override
  String get onboardingStepFileAssociation => '关联文件打开方式';

  @override
  String get onboardingFileAssociationDesc =>
      '将常见的音乐格式（mp3, flac, wav 等）与 VibeFlow 关联，在文件管理器中双击即可直接播放。';

  @override
  String get onboardingFileAssociationTip =>
      '关联后，系统可能会弹出选择默认打开程序的对话框。请务必在列表中选择「VibeFlow」并设为始终使用。';

  @override
  String get onboardingStepRootDirectory => '添加音乐根目录';

  @override
  String get onboardingRootDirectoryDesc =>
      '选择存储音乐文件的文件夹。VibeFlow 会自动扫描并建立你的本地音乐库。';

  @override
  String get onboardingSelectDirectory => '选择文件夹';

  @override
  String get onboardingSuccessTitle => '一切准备就绪！';

  @override
  String get onboardingSuccessDesc => '已成功添加媒体库。让我们开始享受音乐吧！';

  @override
  String get onboardingStartButton => '进入 VibeFlow';

  @override
  String get onboardingSkip => '稍后设置';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingBack => '上一步';

  @override
  String get resetOnboarding => '重置新手引导';

  @override
  String get resetOnboardingDesc => '清除首次启动引导状态，下次启动应用时重新显示新手引导。';
}
