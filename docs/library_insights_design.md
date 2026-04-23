# 媒体库「最多播放 / 最近添加」设计方案

## 目标

在现有媒体库页 [library_page.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/pages/library_page.dart) 中新增两个一级 Tab：

1. `最多播放`
2. `最近添加`

并支持统一时间过滤：

1. `全部时间`
2. `过去 7 天`
3. `过去 30 天`
4. `过去 90 天`

其中：

- `最近添加` 基于歌曲入库时间 `songs.createdAt`
- `最多播放` 基于新增的播放事件表统计

---

## 一、页面结构设计

### 1. 一级 Tab 结构

当前媒体库是 3 个一级 Tab：

1. 播放列表
2. 专辑
3. 艺人

建议扩成 5 个：

1. 播放列表
2. 最多播放
3. 最近添加
4. 专辑
5. 艺人

原因：

- 用户视角里“最多播放 / 最近添加”都属于媒体库的浏览入口，和歌单、专辑、艺人同级最自然
- 不需要再先进歌单或专辑才能切二级视图
- 与 Apple Music / Spotify / Navidrome 一类信息架构更接近

### 2. 二级筛选条

`最多播放` 和 `最近添加` 两个页面共用一个顶部筛选条：

- 左侧：页面标题 + 描述文案
- 右侧：时间范围切换 `SegmentedButton` 或 `ChoiceChip`

建议文案：

- 最多播放：`按播放次数排序`
- 最近添加：`按入库时间排序`

建议时间范围枚举：

```dart
enum LibraryTimeRange {
  allTime,
  last7Days,
  last30Days,
  last90Days,
}
```

### 3. 列表样式

两个页面都建议使用“可直接播放的歌曲榜单”样式，而不是卡片宫格：

- 左侧：封面
- 中间：标题 / 艺术家 / 专辑
- 右侧：
  - 最多播放：播放次数 + 最近播放时间
  - 最近添加：添加时间 + 可选时长

原因：

- 这两个页面本质是排序榜单
- 列表更适合展示次要指标
- 与当前 [playlist_tab.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/pages/playlist_tab.dart) 交互更一致，复用成本更低

### 4. 交互

每一行建议支持：

1. 点击：播放该歌曲，并以当前筛选结果作为播放队列
2. 长按 / 右键：复用现有歌曲上下文菜单
3. 顶部按钮：
   - `播放全部`
   - `随机播放`

空状态建议：

- 最多播放：
  - 全部时间为空：`还没有播放记录`
  - 指定时间为空：`这个时间范围内还没有播放记录`
- 最近添加：
  - 全部时间为空：`媒体库中还没有歌曲`
  - 指定时间为空：`这个时间范围内没有新添加的歌曲`

---

## 二、数据层设计

## 1. 现状

当前 `songs` 表定义在：

- [metadata_drift_database.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/player/metadata_drift_database.dart)
- [metadata_database.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/player/metadata_database.dart)

已有字段里和本需求相关的是：

- `path`
- `title`
- `artist`
- `album`
- `duration`
- `createdAt`

其中 `createdAt` 已能满足“最近添加”。

不足之处：

- 没有 `playCount`
- 没有 `lastPlayedAt`
- 没有“每次播放事件”的历史表

仅增加 `playCount` 和 `lastPlayedAt` 不够，因为你要支持：

- 过去一周内最多播放
- 过去一个月内最多播放

这类按时间窗口聚合的需求必须保留原始播放事件，或者维护分桶统计表。

## 2. 推荐方案：新增播放历史表

新增表：`song_play_history`

字段建议：

```dart
class SongPlayHistories extends Table {
  @override
  String get tableName => 'song_play_history';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get songPath => text().named('songPath')();
  IntColumn get playedAt => integer().named('playedAt')();
  IntColumn get playedDurationMillis =>
      integer().nullable().named('playedDurationMillis')();
  IntColumn get songDurationMillis =>
      integer().nullable().named('songDurationMillis')();
  TextColumn get source =>
      text().nullable().named('source')(); // queue / playlist / album / artist / manual
}
```

说明：

- `songPath`：与 `songs.path` 对应，保持当前项目最稳定的歌曲主标识
- `playedAt`：本次播放开始或达成计数阈值的时间
- `playedDurationMillis`：实际听了多久，可选
- `songDurationMillis`：事件发生时歌曲总时长，可选
- `source`：后续可以分析播放来源，现在先可选

建议索引：

```sql
CREATE INDEX idx_song_play_history_song_path_played_at
ON song_play_history(songPath, playedAt DESC);

CREATE INDEX idx_song_play_history_played_at
ON song_play_history(playedAt DESC);
```

## 3. 是否要把 `playCount` 冗余到 songs 表

建议：`可以加，但不是必需`

如果你想让“全部时间最多播放”列表更快，可以在 `songs` 表上增加：

- `playCount`
- `lastPlayedAt`

这样：

- `全部时间最多播放` 可直接查 `songs`
- `过去 7 天 / 30 天 / 90 天` 仍然查 `song_play_history`

建议字段：

```dart
IntColumn get playCount => integer().withDefault(const Constant(0))();
IntColumn get lastPlayedAt => integer().nullable()();
```

如果先想减少改动，也可以先不加，全部都从 `song_play_history` 聚合。

我的建议是：

1. 第一阶段只加 `song_play_history`
2. 如果后面性能不够，再给 `songs` 加冗余统计字段

这样迁移风险最低。

---

## 三、播放埋点设计

## 1. 埋点位置

推荐在 [audio_service.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/player/audio_service.dart) 中做“播放计数确认”。

不建议在以下时机直接计数：

- 点击歌曲瞬间
- `playPlaylist()` / `playFile()` 调用瞬间

因为这些只能说明“尝试播放”，不代表用户真的听了。

## 2. 推荐记一次播放的判定

建议规则：

满足以下任一条件，写入一次 `song_play_history`：

1. 播放超过 30 秒
2. 或播放进度超过歌曲时长的 50%

这样可以避免：

- 用户快速切歌导致虚高
- 列表点开就计数

## 3. 去重策略

同一首歌单次连续播放只记一次。

可在 `AudioService` 内维护：

```dart
String? _playbackTrackedSongPath;
bool _hasLoggedCurrentPlayback = false;
```

当切到新歌时重置。

达到阈值后：

1. 插入 `song_play_history`
2. 标记当前播放已记录，避免重复写入

---

## 四、查询设计

## 1. 最近添加

排序逻辑：

- 主排序：`songs.createdAt DESC`
- 次排序：`title ASC`

时间过滤：

- `allTime`: 不过滤
- `last7Days`: `createdAt >= now - 7d`
- `last30Days`: `createdAt >= now - 30d`
- `last90Days`: `createdAt >= now - 90d`

示例 SQL：

```sql
SELECT *
FROM songs
WHERE createdAt IS NOT NULL
  AND (:startAt IS NULL OR createdAt >= :startAt)
ORDER BY createdAt DESC, title COLLATE NOCASE ASC;
```

## 2. 最多播放

排序逻辑：

- 主排序：播放次数降序
- 次排序：最近播放时间降序
- 再次排序：标题升序

示例 SQL：

```sql
SELECT
  s.*,
  COUNT(h.id) AS playCountInRange,
  MAX(h.playedAt) AS lastPlayedAtInRange
FROM songs s
JOIN song_play_history h ON h.songPath = s.path
WHERE (:startAt IS NULL OR h.playedAt >= :startAt)
GROUP BY s.path
ORDER BY playCountInRange DESC, lastPlayedAtInRange DESC, s.title COLLATE NOCASE ASC;
```

如果以后需要“最近添加但按专辑聚合”或“最多播放专辑”，这套事件表也能继续复用。

---

## 五、Riverpod / 服务层设计

建议新增一个单独服务：

- `lib/player/library_insights_service.dart`

职责：

1. 记录播放事件
2. 查询时间范围内的最多播放
3. 查询时间范围内的最近添加

建议模型：

```dart
enum LibraryTimeRange { allTime, last7Days, last30Days, last90Days }

class RankedSongEntry {
  final MusicFile song;
  final int playCount;
  final int? lastPlayedAt;
  final int? createdAt;
}
```

建议 Provider：

```dart
final libraryTimeRangeProvider =
    StateProvider<LibraryTimeRange>((ref) => LibraryTimeRange.allTime);

final mostPlayedSongsProvider =
    StreamProvider.family<List<RankedSongEntry>, LibraryTimeRange>((ref, range) {
  return ref.read(libraryInsightsServiceProvider).watchMostPlayed(range);
});

final recentlyAddedSongsProvider =
    StreamProvider.family<List<RankedSongEntry>, LibraryTimeRange>((ref, range) {
  return ref.read(libraryInsightsServiceProvider).watchRecentlyAdded(range);
});
```

这样 UI 逻辑会比较干净，`library_page.dart` 只负责切 tab，不直接写查询。

---

## 六、页面拆分建议

建议新增两个页面文件：

1. `lib/pages/most_played_tab.dart`
2. `lib/pages/recently_added_tab.dart`

同时抽一个可复用榜单组件：

3. `lib/widgets/library_ranked_song_list.dart`

### 1. `most_played_tab.dart`

结构建议：

- 顶部：
  - 标题 `最多播放`
  - 时间筛选
  - `播放全部 / 随机播放`
- 主体：
  - 榜单列表
- 行尾展示：
  - `12 次`
  - `最近播放 2 天前`

### 2. `recently_added_tab.dart`

结构建议：

- 顶部：
  - 标题 `最近添加`
  - 时间筛选
  - `播放全部 / 随机播放`
- 主体：
  - 按添加时间倒序列表
- 行尾展示：
  - `2026-04-23`

### 3. 公共组件 `library_ranked_song_list.dart`

参数建议：

```dart
class LibraryRankedSongList extends ConsumerWidget {
  final String title;
  final List<RankedSongEntry> items;
  final Widget Function(BuildContext context, RankedSongEntry item) trailingBuilder;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffle;
}
```

这样两个页面只需要换数据源和 trailing 展示。

---

## 七、迁移方案

## 1. Drift schemaVersion

当前版本是 `22`，在
[metadata_drift_database.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/player/metadata_drift_database.dart)

建议升到 `23`。

## 2. 迁移内容

`from < 23` 时：

1. 创建 `song_play_history`
2. 创建索引
3. 如果决定做冗余字段，再给 `songs` 增加：
   - `playCount`
   - `lastPlayedAt`

建议第一版迁移只做：

1. `CREATE TABLE song_play_history`
2. `CREATE INDEX ...`

因为这不会影响现有扫描逻辑，也不需要回填旧数据。

## 3. 历史数据处理

旧用户升级后：

- `最近添加` 可以立刻生效
- `最多播放` 从升级后开始累计

这是可接受的，因为历史播放事件本来不存在，无法准确补算。

可以在空状态文案里说明：

- `播放统计会从此版本开始累计`

---

## 八、实施顺序建议

建议按下面顺序做，风险最低：

1. 数据库增加 `song_play_history`
2. 新增 `LibraryInsightsService`
3. 在 `AudioService` 增加播放埋点
4. 实现 `RecentlyAddedTab`
5. 实现 `MostPlayedTab`
6. 把 `library_page.dart` Tab 数从 3 改到 5
7. 增加中英文文案

---

## 九、与现有代码的衔接点

### 1. 媒体库入口

- [library_page.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/pages/library_page.dart)

这里需要：

- `TabController(length: 5, ...)`
- `IndexedStack` 扩成 5 项
- AppBar 标题逻辑支持新 tab

### 2. 歌曲元数据来源

- [metadata_database.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/player/metadata_database.dart)
- [metadata_drift_database.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/player/metadata_drift_database.dart)

这里新增播放历史表和查询接口。

### 3. 播放埋点

- [audio_service.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/player/audio_service.dart)

建议在：

- 新歌开始播放时重置当前播放计数状态
- 位置更新或播放状态更新时判断是否达到计数阈值

### 4. 列表样式参考

- [playlist_tab.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/pages/playlist_tab.dart)
- [albums_tab.dart](C:/Users/Administrator/Desktop/projects/player_project/vibe_flow/lib/pages/albums_tab.dart)

`最多播放 / 最近添加` 更接近 `playlist_tab.dart` 的歌曲列表形态，但可以借 `albums_tab.dart` 的顶部工具栏结构。

---

## 十、推荐结论

最终推荐方案：

1. 媒体库新增两个一级 Tab：`最多播放`、`最近添加`
2. 两个页面共用时间范围筛选：`全部时间 / 7 天 / 30 天 / 90 天`
3. `最近添加` 直接基于 `songs.createdAt`
4. `最多播放` 新增 `song_play_history` 表统计
5. 播放次数在“播放超过 30 秒或超过 50%”后才记一次
6. 第一阶段不强制给 `songs` 增加 `playCount` 冗余字段，先用事件表实现

如果后面准备正式开做，实现优先级我建议先上：

1. `最近添加`
2. 播放历史表 + 埋点
3. `最多播放`

这样能最快把一半功能先交付出来。
