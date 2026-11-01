# 长期项目笔记

> 只留「会反复咬人的不变量」：名字 + 唯一入口。逐条全文与失败现象见
> `MEMORY-archive-2026-11-01.md`（含 10-21 / 10-23 前身与本文件精简前快照）；过程见同日 `YYYY-MM-DD.md`。

## 单一数据源（唯一入口 / 唯一开关）

| 主题 | 规则 |
|---|---|
| Rail 宽度 | `sidebarRailWidthFor()`（`layout_constants.dart`），禁 `80.0` |
| 队列抽屉窗口宽 | `minWindowWidthForDrawer()`：窗口 ≥ 抽屉宽 + `kMinMainContentWidth`(400)。WindowOptions、退出小窗、拖拽/双击复位、最小窗口尺寸同源派生 |
| FFmpeg 版本 | `audio_core/ffmpeg_version.env`，禁脚本硬编码；flatpak 清单与 `build-ffmpeg.yml` tag 靠手同步 |
| 远程下载落盘 | `buildLocalTrackPath()` + `RemoteDownloadRequest.batches`。层级由**页面/栏目**定（`.album` 一层 / `.artist` 目录+专辑 / `.playlist` 无专辑层 / WebDAV·SMB 照抄远端），禁按单曲或是否多选区分。唯一入队口 `enqueue(RemoteDownloadRequest)`；多选 `fetchSelectedBatches`；单曲走 `downloadLayout`/`downloadCollectionFolder` |
| 载荷校验 | `RemotePayloadGuard.inspect()` 必须在「有字节就算成功」之前；只读头 2048B，禁按大小阈值。`_downloadTask` 与 `downloadRemoteTrackToTempFile` 共用 |
| 拒绝下载 / 临时下载 | Subsonic 禁用 `download.view` 回 200+失败 JSON(50) → `isDownloadsDisabled`；Jellyfin 走 `buildStreamUrl`，401/403/404 经 `_describeHttpFailure()`。临时下载先查 `AudioStreamCacheManager`，再按 server 分派（subsonic / jellyfin / smb / 其余 WebDav），**禁只判 subsonic、其余全落 WebDavClient** |
| 曲库数据 | `libraryCatalogProvider` 是唯一订阅 `db.watchAllSongMetadata()` 处；新视图用 `catalogDerived(ref, ...)`。`songs` 排除 external/deletedAt，`visibleSongs` 再加根目录/来源 |
| 返回键 | `MainLayout._handleBackPressed()`：Modal → 播放抽屉 → index 2 → index 0 回上级 → index 4 传输中拦 → `SystemNavigator.pop()` |
| 队列整体替换 | `PlaylistController.replaceActiveTracksAndSelect`（冷启动恢复同理），禁拆 `updatePlaylistTracks`+`playByIndex` |
| 浮动 Dock 收起 | `floatingDockCollapsed(Progress)Provider`；切页面/子分类**禁** `setCollapsed`，只 `helper.reset(ref)`；顶部缓冲展开必须边沿触发且只对同一 Scrollable 成立，底部无条件展开 |
| l10n / 设置项 | l10n：9 个 `app_*.arb` 同步，模板 `app_zh.arb`，改完 `flutter gen-l10n`。设置项：`settings_service.dart` 三段 → 6 处同步（key、`SettingProperty`、getter+setter、`resetXxx()`、`settings_search_registry.dart`、`sections/<组>_section.dart`） |
| 流派聚合键 | `normalizeGenreKey()`；派生 `queryKey` 与 `matchGenreAssetKey()` 同源；`_acronymDisplays` 吃 `raw.toLowerCase()` 不能跟着改；`_substringAssetRules` 连写 needle 必须留 |
| 详情三页 | `album_sections.dart`、`collection_detail_content.dart`、`collection_detail_header.dart`、`detail_page_shell.dart`；分组宽 ≥600 走「左封面右列表」 |
| 主从视图搜索 | 输入框唯一实现 `LibrarySearchField`；横屏左栏顶部唯一实现 `LibraryMasterPaneHeader`（搜索 + 排序同排），排序**禁**留在横跨两栏的页头（`showSortActionInWide: false`）；详情内统一 `filterAlbumSections()`，**过滤后必须重算 `startIndex`**；复位按 `source.id`/`artist.queryKey`；开关固定操作区行尾最右 |
| 洞察页 | 视图状态 `LibraryInsightFilterNotifier`（复位点唯一 `_LibrarySubHostPageState.dispose`）；列表唯一 `library_insight_list.dart`，行内边距唯一 `_insightRowPadding` + `kInsightListHorizontalInset` |
| 子分类导航域 | `library_tab_navigator.dart`（每分类一条 `Navigator` + `HeroController`）挂宿主 `IndexedStack`；切分类只改 provider/索引，**禁 popUntil** |
| 远程封面组件 | `remote_artwork_widget.dart`：落盘后**禁** `setState` 切 `Image.file`；`gaplessPlayback = _renderedImageUrl == imageUrl`；`coverArtId` 变必须 `_localDiskPath = null` |
| 远程目录封面 | 唯一实现 `remote_folder_cover_service.dart`：`folder_entries` → `songs` 表（`getFirstSongWithArtworkUnderPath`，**禁** `getRepresentativeSongUnderPath`）→ 目录 `cover.jpg` → 首曲内嵌标签。**只有查到才写 `folder_entries`**（负结果留进程内 `_negativeCache`），`FolderCoverSnapshot.songPath` 可空；`failed` 禁写跳过标记。页面侧 `_folderCoverSongs` 用 `ValueNotifier`，并发固定 2 |
| 远程播放写回缓存 | `StreamCacheWriter`：0 起连续前缀且 `written == expectedTotal` 才 rename，否则 `abort()`；同 key 单写入者靠 `_pendingStreamWriteKeys` 同步占位。`writer.complete()`（rename + `onTrackCached`）**必须在 `response.close()` 之前**，否则波形/音频信息整首不显示、只有 seek 才出。`unawaited` prefetch 必须带 `onError` |
| FFT 采集门 | 唯一决策点 `AudioService._updateEffectiveVisualizerState()` → `visualizer.setEnabled(_isFftCaptureAllowed)`（Pro 用缓存字段，禁热路径 `ref.read`）；采集与「画不画频谱」解耦，关开关**禁** `setEnabled(false)`。Rust 侧 `setFftCaptureEnabled` no-op，靠 `get_latest_fft()` 开 1500ms 窗 |
| 缩放内容侧 | 网格↔列表只渲染一份：`_resolveContentHandoff()`，滞回 0.55/0.45 → `renderAsGrid` + `contentReveal`；禁退回 `gridMorph >= 0.99` 分点 |
| 缩放几何/视口 | 格子位置只在确定档位布局间加权，禁插值列数（`_effectiveGeometryLayers()`/`_collapseGeometry()`）。上界唯一 `FolderZoomViewportTracker.maxViewportTopFor()`，禁拿 `maxScrollOffsetFor()` 直接夹；判「贴底」不得要求内容比视口高 |
| 缩放实现来源 | 引擎/脚手架/捏合/档位图标唯一实现在 path 包 `zoomable_sliver_grid/`；`lib/widgets/folder_layout_utils.dart` 只是薄壳，**禁**写第二份引擎。`hoverable_card.dart`、`cover_play_button.dart` 均为 `export`；档位图标名 `ZoomTierIcon` |
| 缩放档位范围 | 锁档位只在 `Extension LibraryZoomScopeRange.zoomTierRange`（`settings_service.dart`）**加一行 record**：`album` 锁网格三档（4/6~1.0）、`queue` 锁列表四档（0~3/6），其余走默认全七档。设置读写/弹窗滑杆与预设按钮/滚轮步进与捏合全部派生自它（`clampZoomScale()`、`allowedZoomTiers`、`min/maxZoomTier`），**禁**在别处写 `scope == queue` 式判断 |
| **缩放网格宽度** | `width` / `crossAxisExtent:` 只认外层 `LayoutBuilder` 的 `maxWidth`，禁退回 `MediaQuery`（会算出负原点，条目压到 rail 底下） |
| 一页多段缩放 | 一个滚动视图**只能有一个** `FolderZoomSliverBuilder`（`FolderZoomGestureLayer` 与 `ScrollView` 之间）；各段用 `section` 区分 + `ZoomSectionHost`（`width` 仍要传）。**禁**加 `metrics` 字段、**禁**段内自建 builder。**按状态切换 ScrollView 祖先结构（loading/error 裸 view、有内容套 `RefreshIndicator`）的页面禁传 `controller`**：切分支那帧断言炸在 sliver 布局里 = 整页空白 |
| 缩放段间距 | 网格外层 `SliverPadding` 必须与档位无关，禁 `lerp(0→8, gridMorph)`；回归 `zoom_section_gap_test.dart` |
| 条目包装层常驻 | `ZoomItemScaffold` 的 `Opacity`/`Transform.scale`/`ZoomItemEffectiveMetrics` 三层**必须常驻**，禁按 `isFadeScale` 增删：根类型一变整条子树重建 → `SongThumbnail` 丢 State |
| 缩略图淡入时钟 | 只有「就位的是封面」才套 `kArtworkFadeInDuration`；落定为**默认图标**（null/异常）必须 `_needsFadeIn = false`。`artworkPath`/`thumbnailPath` 是 UI 懒生成，为空 ≠ 没封面 |
| **封面同步缓存** | `ArtworkResolver.peekCachedThumbnail()` 是「已解析过」的同步入口（`resolveForThumbnail` 命中缓存也要隔一个微任务，首帧仍空白）。`SongThumbnail._checkOrQueryArtwork` 必须在置待解析之前探一次：命中即 `_artworkFilePath` + `_isGenerating=false` + `fromInitState` 时 `_needsFadeIn=false`。否则任何重建/行回收都会让远程封面「空白 + 280ms 淡入」= 闪。回归 `song_thumbnail_fade_in_test.dart` 末条 |

## 硬性禁止（全文见 `MEMORY-rules.md`）

iOS security scope 禁标准化后再 start（判据是可读性探测）；宿主顶栏让位走 `onHasChildRouteChanged` → `hideTopNavBar`；嵌套 `AutoHideHeaderScope` 各管自己的滚动；禁持二进制、禁按字节/identity 做 key；`IndexedStack` 常驻子页禁挂 `PopScope`；多选状态禁条件切换 root；`SongSelectionMixin` 必须串联书写；禁裸 `ref.watch(scannerServiceProvider)`；`MainLayout` 是 rebuild 放大器；Riverpod 3 禁在 `initState`/`dispose`/`build` 改 provider；Android 转场必须 `allowSnapshotting: false`；逐字歌词时钟禁直接对齐 `audioPositionProvider`；曲库派生页禁把 reload 当首次加载；长列表禁 `SliverToBoxAdapter > ListView(shrinkWrap: true)`；背景模糊 key 必须含封面内容指纹；`vsync: this` 的 controller 禁声明处 `late final`；视图切换禁换根 Widget 类型；写 `songs` 表只能基于 DB 记录 `copyWith`；`TagLibMetadata` 新增列要三处同步；排序写入走 `_markSortOrderChanged()`；`Slider.onChanged` 必须回流 `value`；`mesh_flow.time` 已含 speed。

## 其它约定 / 环境

见 `MEMORY-ops.md`：右键菜单三件套、流派年份封面、远程库「只看收藏」、定位当前播放、禁整仓 `dart format`；rg/fd、flutter PATH、`flutter test` 的代理变量、CRLF。
