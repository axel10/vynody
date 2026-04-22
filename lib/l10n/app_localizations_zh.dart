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
  String get albums => '专辑';

  @override
  String get playAll => '播放全部';

  @override
  String get shufflePlay => '随机播放';

  @override
  String get noAlbums => '还没有可显示的专辑';

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
  String get list => '列表';

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
  String get playbackBackground => '播放页背景';

  @override
  String get blurredArtwork => '模糊封面 (默认)';

  @override
  String get dynamicMesh => '动态流变 (Apple Music 效果)';

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
}
