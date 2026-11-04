# UI / 渲染不变量

> 从 `MEMORY.md` 拆出（正文过长导致注入被截断）。全文与失败现象见
> `MEMORY-archive-2026-11-01.md`；每次新增前先确认这里没有同源条目。

| 主题 | 规则 |
|---|---|
| 返回图标 | 全局唯一 `kAppBackIcon`（`lib/utils/app_icons.dart` = `chevron_left_rounded`），禁 `Icons.arrow_back*`；折角只有带杆箭头约 40% 宽，尺寸须抬一档（导航栏/胶囊/面包屑 22、圆钮 20、工具栏 20、AppBar 24） |
| 浮动 Dock 收起 | `floatingDockCollapsed(Progress)Provider`；切页面/子分类禁 `setCollapsed`，只 `helper.reset(ref)`；顶部缓冲展开必须边沿触发且只对同一 Scrollable 成立，底部无条件展开 |
| 详情三页 | `album_sections.dart`、`collection_detail_content.dart`、`collection_detail_header.dart`、`detail_page_shell.dart`；分组宽 ≥600 走「左封面右列表」 |
| 主从视图搜索 | 输入框唯一 `LibrarySearchField`；横屏左栏顶部唯一 `LibraryMasterPaneHeader`（搜索+排序同排），排序禁留跨两栏页头（`showSortActionInWide: false`）；详情内统一 `filterAlbumSections()`，**过滤后必须重算 `startIndex`**；复位按 `source.id`/`artist.queryKey`；开关固定操作区行尾最右 |
| 洞察页 | 视图状态 `LibraryInsightFilterNotifier`（复位点唯一 `_LibrarySubHostPageState.dispose`）；列表唯一 `library_insight_list.dart`，行内边距唯一 `_insightRowPadding` + `kInsightListHorizontalInset` |
| 子分类导航域 | `library_tab_navigator.dart`（每分类一条 `Navigator` + `HeroController`）挂宿主 `IndexedStack`；切分类只改 provider/索引，禁 popUntil |
| 远程封面组件 | `remote_artwork_widget.dart`：落盘后禁 `setState` 切 `Image.file`；`gaplessPlayback = _renderedImageUrl == imageUrl`；`coverArtId` 变必须 `_localDiskPath = null` |
| 远程目录封面 | 唯一实现 `remote_folder_cover_service.dart`：`folder_entries` → `songs`（`getFirstSongWithArtworkUnderPath`，禁 `getRepresentativeSongUnderPath`）→ 目录 `cover.jpg` → 首曲内嵌标签。只有查到才写 `folder_entries`（负结果留进程内 `_negativeCache`）；`FolderCoverSnapshot.songPath` 可空；`failed` 禁写跳过标记。页面侧 `_folderCoverSongs` 用 `ValueNotifier`，并发固定 2 |
| 缩略图淡入时钟 | 只有「就位的是封面」才套 `kArtworkFadeInDuration`；落定为默认图标（null/异常）必须 `_needsFadeIn = false`。`artworkPath`/`thumbnailPath` 是 UI 懒生成，为空 ≠ 没封面 |
| **封面同步缓存** | `ArtworkResolver.peekCachedThumbnail()` 是「已解析过」的同步入口（`resolveForThumbnail` 命中缓存也要隔一个微任务）。`SongThumbnail._checkOrQueryArtwork` 必须在置待解析前探一次：命中即 `_artworkFilePath` + `_isGenerating=false` + `fromInitState` 时 `_needsFadeIn=false`，否则任何重建/行回收都会「空白 + 280ms 淡入」= 闪。回归 `song_thumbnail_fade_in_test.dart` 末条 |
| **目录页 banner 分支** | `isWideOrSquare`（阈值 `_kAspectRatioWideOrSquareThreshold`）同时决定「背景模糊层」与「前景内联封面块」，两条路径高度差一整个内联封面 → 比例必须首帧定：`_aspectRatioFromMetadata()` 读 `metadataMap[path].artworkWidth/Height`（原始封面宽高）。异步解码只走 `_applyAspectRatio()`（含 `_kAspectRatioTolerance` 容差），禁直接 `setState` 覆盖。内联封面块定高 `_kPortraitInlineCoverHeight`，禁靠 image intrinsic size（解码前 0 → 顶动列表） |
| 播放页流变背景 | `playbackBackgroundType`：`1` = `mesh_gradient`→`DynamicMeshBackground`、`4` = `mesh_flow`→`MeshFlowBackground`，同文件共用 `_PlaybackMeshPaletteMixin`；流速各用各的项（`playbackMeshGradientSpeed` 0.05 / `playbackMeshBackgroundSpeed` 0.4），禁合并。新增类型同步点：弹窗下拉 + `effectivePlaybackBackgroundTypeProvider` + `_buildBackgroundWidget` + `_buildBackgroundScrim` |
| 歌词行动画层常驻 | `StaggeredAppleLyricsScrollWrapper` 必须每行常驻，错峰窗口只作为 `enabled` 传（窗口跟 `firstVisibleIndex` 走；按条件增删包裹层 → 整行重建 → 译文淡入重播）。controller 惰性创建、禁用时释放，mixin 用 `TickerProviderStateMixin`；build 恒定 `ExcludeSemantics > AnimatedBuilder > Transform > child`（未启用用 `AlwaysStoppedAnimation` 占位，禁省 Transform 层）。回归 `lyrics_staggered_wrapper_test.dart` |
| 歌词行滤镜层恒定 | 焦点模式模糊的 `TweenAnimationBuilder` builder 必须恒定返回 `ImageFiltered`（sigma 0 也留），禁 `blurSigma <= 0` 时 `return child`：跳行时跨过这一步即换父级类型 → 整行重建 → 译文重播。判据日志：`trans-init idx=N active=N` 却没有对应 `slot ∅->有`。回归 `lyrics_line_blur_stability_test.dart` |
| 缩放内容侧 | 网格↔列表只渲染一份：`_resolveContentHandoff()`，滞回 0.55/0.45 → `renderAsGrid` + `contentReveal`；禁退回 `gridMorph >= 0.99` 分点 |
| 缩放几何/视口 | 格子位置只在确定档位布局间加权，禁插值列数（`_effectiveGeometryLayers()`/`_collapseGeometry()`）。上界唯一 `FolderZoomViewportTracker.maxViewportTopFor()`，禁拿 `maxScrollOffsetFor()` 直接夹；判「贴底」不得要求内容比视口高 |
| 缩放实现来源 | 引擎/脚手架/捏合/档位图标唯一实现在 path 包 `zoomable_sliver_grid/`；`lib/widgets/folder_layout_utils.dart` 只是薄壳，禁写第二份引擎。`hoverable_card.dart`、`cover_play_button.dart` 均为 `export`；档位图标名 `ZoomTierIcon` |
| 缩放档位范围 | 锁档位只在 `Extension LibraryZoomScopeRange.zoomTierRange`（`settings_service.dart`）加一行 record：`album` 锁网格三档（4/6~1.0）、`queue` 锁列表四档（0~3/6），其余全七档。读写/滑杆/预设/滚轮/捏合全部派生自它（`clampZoomScale()`、`allowedZoomTiers`、`min/maxZoomTier`），禁别处写 `scope == queue` 式判断 |
| 缩放修饰键 | 标签 `zoomModifierKeyLabel` 与判定 `isZoomModifierPressed` 同处 `folder_layout_utils.dart`（macOS `⌘`/也认 Ctrl，其余 `Ctrl`）；`zoomTierShortcutHint({modifier})` 只吃这个标签，禁在手势层另写平台判断 |
| **缩放网格宽度** | `width` / `crossAxisExtent:` 只认外层 `LayoutBuilder` 的 `maxWidth`，禁退回 `MediaQuery`（负原点，条目压到 rail 下） |
| 一页多段缩放 | 一个滚动视图只能有一个 `FolderZoomSliverBuilder`（`FolderZoomGestureLayer` 与 `ScrollView` 之间）；各段用 `section` 区分 + `ZoomSectionHost`（`width` 仍要传）。禁加 `metrics` 字段、禁段内自建。**按状态切换 ScrollView 祖先结构（loading/error 裸 view、有内容套 `RefreshIndicator`）的页面禁传 `controller`**：切分支那帧断言炸在 sliver 布局里 = 整页空白 |
| 缩放段间距 | 网格外层 `SliverPadding` 必须与档位无关，禁 `lerp(0→8, gridMorph)`；回归 `zoom_section_gap_test.dart` |
| 条目包装层常驻 | `ZoomItemScaffold` 的 `Opacity`/`Transform.scale`/`ZoomItemEffectiveMetrics` 三层必须常驻，禁按 `isFadeScale` 增删：根类型一变整条子树重建 → `SongThumbnail` 丢 State |
