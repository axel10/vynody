# 长期项目笔记

> 只留「会反复咬人的不变量」。完整措辞、踩坑经过与被否方案见
> `MEMORY-archive-2026-10-21.md`；过程见同日 `YYYY-MM-DD.md`。

## 单一数据源

| 主题 | 唯一来源 / 规则 |
|---|---|
| Rail 宽度 | `layout_constants.dart` 的 `sidebarRailWidthFor()`，禁 `80.0`；连带 `main_layout.dart` 的 `railWidth`/`leftPadding`、`library_page.dart` |
| FFmpeg 版本 | `audio_core/ffmpeg_version.env`，禁脚本硬编码；flatpak 清单与 `build-ffmpeg.yml` 的 tag 无硬校验，靠手同步 |
| 远程下载落盘 | `buildLocalTrackPath()` + `RemoteDownloadRequest.batches`：`.album`=专辑一层；`.artist`=`collectionFolder`+专辑（无名回落 `albumArtist ?? artist`）；`.playlist`=`collectionFolder` 无专辑层；WebDAV/SMB 照抄远端层级。层级由**页面/栏目**决定，禁按「单曲/多选」区分。唯一入队口 `enqueue(RemoteDownloadRequest)`，多选走 `fetchSelectedBatches`（禁退化成 `List<MusicFile>` 让 UI 猜），单曲走 `showRemoteSongContextMenu` 的 `downloadLayout`/`downloadCollectionFolder`，禁按单曲 `artist` 分层（合辑被拆散） |
| 下载落盘前载荷校验 | `remote_payload_guard.dart` 的 `RemotePayloadGuard.inspect(file, contentType, parseSubsonicError)`，必须在「有字节就算成功」之前调用。只读文件头 2048B（反代错误页可能几 MB，禁按大小阈值）；音频魔数优先放行 → Subsonic 失败 JSON（`parseErrorBody`）→ `text/*`/json/xml 或首字节 `<`/`{`/`[` 判非媒体（`RemotePayloadException`，code=-1）。两个入口 `_downloadTask`、`downloadRemoteTrackToTempFile` 共用，禁各写一份 |
| 下载反馈 | `showRemoteDownloadQueuedFeedback(context, ref, count)`：单曲 `addedToDownloadQueue`，批量 `batchAddedToDownloadQueue`；禁手抄 SnackBar +「查看进度」push |
| Jellyfin 拒绝下载 | 走 `buildStreamUrl`（`/Audio/{id}/stream?static=true`），不受用户策略「允许下载」约束 → 无 code 50 场景；拒绝是标准 401/403/404，由 `_describeHttpFailure()` 映射为 `remoteDownloadUnauthorized`（每 server 提示一次）/ `remoteDownloadTrackMissing`（只落任务 error） |
| 曲库数据 | `libraryCatalogProvider` 是唯一订阅 `db.watchAllSongMetadata()` 处；新视图用 `catalogDerived(ref, ...)`，禁自己 `await for`；派生 provider 保持 `StreamProvider` 与原名（测试 override）。`songs` 排除 external/deletedAt，`visibleSongs` 再加根目录/来源 |
| 返回键 | `MainLayout._handleBackPressed()`：Modal → 播放抽屉 → index 2 → index 0 回上级 → index 4 传输中拦 → `SystemNavigator.pop()` |
| 队列整体替换 | `PlaylistController.replaceActiveTracksAndSelect`。禁拆成 `updatePlaylistTracks`+`playByIndex`（中间 `currentMusic` 瞬时 null，Dock 重播收起动画）；冷启动恢复同理禁拆 `addTracksToPlaylist`+`setActivePlaylist` |
| 浮动 Dock 收起 | `floatingDockCollapsed(Progress)Provider`，开关 `enableFloatingDockScrollCollapse`；`mini_player_wrapper` 与 `main_layout` 各一 helper。切主页面/子分类**禁** `setCollapsed`，只 `helper.reset(ref)`。顶部缓冲区展开必须边沿触发，且边沿只对同一 Scrollable 成立（`notification.context` 判同源）；底部无条件展开 |
| l10n | 9 个 `lib/l10n/app_*.arb` 同步，模板 `app_zh.arb`；缺 key 静默回退中文只记 stdout；改完 `flutter gen-l10n` |
| 设置项 | `settings_service.dart` 三段 → 6 处同步：key 常量、`SettingProperty`、getter+setter、`resetXxx()`、`settings_search_registry.dart`、`sections/<组>_section.dart` |
| 流派聚合键 | `normalizeGenreKey()`（`_genreKeyEquivalents` 收敛连写 `JPop`→`j pop`）；派生 `queryKey` 与 `matchGenreAssetKey()` 同源；`_acronymDisplays` 吃 `raw.toLowerCase()` 不能跟着改；`_substringAssetRules` 连写 needle 必须留 |
| 详情三页 | `album_sections.dart`、`collection_detail_content.dart`、`collection_detail_header.dart`、`detail_page_shell.dart`；禁再各写分组排序/曲目行；分组宽 ≥600 走「左封面右列表」，否则小封面 + 下方列表 |
| 洞察页视图状态 | `LibraryInsightFilterNotifier`（单曲/专辑 + 时间跨度）；复位点唯一 `_LibrarySubHostPageState.dispose`（微任务 `reset()`）；切子分类/主页面不销毁宿主 → 保留，回仪表盘（`libraryActiveTabIndexProvider` 置 null）才复位 |
| 子分类导航域 | `library_tab_navigator.dart`（每分类一条 `Navigator` + 自己的 `HeroController`）挂宿主 `IndexedStack`；9 个 key 由 `LibraryPageState` 持有。切分类只改 provider/索引，**禁 popUntil**；返回键：多选 → 3D → 当前分类栈 → 宿主栈；tab 根内边距在路由 builder 里重算 |
| 洞察页列表 | `library_insight_list.dart`（单曲/专辑同一 widget，只换 body sliver）、`library_insight_tab.dart`、`insight_metric_text.dart`；禁再写 `LibraryRankedSongList`/`AlbumList`；切视图根节点 runtimeType 不变；行内边距唯一来源 `_insightRowPadding` + `kInsightListHorizontalInset` |
| 远程封面 | `lib/widgets/remote_artwork_widget.dart`：磁盘落盘后**禁** `setState` 切 `Image.file`（换源重解码 → 空白帧）；`gaplessPlayback = _renderedImageUrl == imageUrl`；`didUpdateWidget` 里 coverArtId 变化必须 `_localDiskPath = null`；`_checkLocalDiskCache` 的 await 返回后复核 URL 未变。判「同一张图」只能比 path/URL，禁 `bytes.hashCode`/identity |
| 远程库二次请求反馈 | `RemoteLibraryReloadingOverlay` + 页面级 `_isReloadingContent`，叠在 `body` 的 Stack 里；触发点只有真实发请求的三处：专辑排序、歌曲/艺术家「只看收藏」补齐收藏集合；首屏仍走各 tab 的 `isLoading && list.isEmpty` 空白视图 |

## 硬性禁止

- **宿主顶栏给三级页让位**：详情在子分类 Navigator 里，宿主 `AppTopNavBar` 后画会盖住它 → `LibraryTabNavigator.onHasChildRouteChanged` → `_tabsWithChildRoutes` → `hideTopNavBar`（`Duration.zero`）。测试取 `library_subhost_top_bar` 外层 `AnimatedOpacity` 用 `.at(1)`。
- **嵌套 `AutoHideHeaderScope` 各管自己的滚动**：`_ownsNotification()` 按「来源往上数最近一个 scope 是否自己」判定，外层不收内层通知。回归 `test/widgets/auto_hide_header_test.dart` 的 Nested scope 用例。
- **禁持二进制、禁按字节做 key**：blob 列（`themeColorsBlob`/`waveformBlob`/`artworkBytes`）禁进 `MusicFolder.files` 与 `representativeSongCache`（执行点 `scanner_tree_builder` 三工厂、`ScannerMetadataStore._updateMusicFileInFolder`；数据源永远 SQLite）。播放态封面每次 `Uint8List` 新实例，key 只能用品内容指纹。
- **IndexedStack 常驻子页禁挂 PopScope**：PopScope 注册在路由上、与可见性无关，`canPop:false` 会让整条路由 `doNotPop` 并派发给全部 PopEntry。共用 tab 写进 `_handleBackPressed()`；艺术家/流派/年份页面层套 `library_selection_back_guard.dart`。
- **多选状态禁条件切换 widget 根节点**：runtimeType 一变子树重建，dispose 微任务清掉刚建的多选状态。唯一状态 `librarySelectionStateProvider`。
- **禁裸 `ref.watch(scannerServiceProvider)`**：缩略图每张都 `notifyListeners()`。取实例用 `ref.read`，树变化用 `.select((s) => s.structureRevision)`；`rootFolders` 返回缓存 `_rootFoldersView`（别现写 `List.unmodifiable`，新实例让 `select` 永不判等）；`ScanProgressInfo` 无 `==`，`build()` 只能 select `isScanning`。
- **MainLayout 是 rebuild 放大器**：`_buildCurrentPage()` 每次 build 新建非 const 的 `FoldersPage`/`LibraryPage`，任何 `setState` 都 rebuild 全部已访问页。别随手加 `ref.watch`。
- **Riverpod 3 禁在 `initState`/`dispose`/`build` 改 provider**：要复位 → `initState` 存 `ref.read(x.notifier)`，`dispose` 里 `Future.microtask(() => notifier.reset())`；`reset()` 先判 `ref.mounted` 与 `isDefault`。
- **Android 转场**：必须 `ZoomPageTransitionsBuilder(allowSnapshotting: false)`，否则返回时下层被快照、ink 高亮残留。
- **逐字歌词时钟禁直接对齐 `audioPositionProvider`**：250ms 阶梯值 + 墙钟插值领先约 100ms，硬对齐 = 每句回跳。`WordWordLyricsWidget._syncBaseline` 只取锚点 + `_correction`（240ms 摊入，>900ms 才硬对齐），靠静态 `_resumeLineKeyMs/_resumePositionMs` 让重建的 State 续接位置；`audio_core._advanceLocalPosition` 回退 >400ms 才算 seek，小幅回退每轮最多回拉 6ms。
- **曲库派生页禁把 reload 当首次加载**：`AsyncValue.when` 默认 `skipLoadingOnReload: false` 会整页加载圈。判 loading 只认「没有旧值」，统一用 `library_overview_providers.dart` 的 `_needsFullPageLoad()`/`_isFatalError()`（`isLoading && !hasValue`）。
- **长列表禁 `SliverToBoxAdapter > ListView(shrinkWrap: true)`**：一律 `SliverList.builder`/`SliverFixedExtentList.builder`，逐行 `Align + ConstrainedBox(maxWidth: kSingleColumnContentMaxWidth)`。
- **播放页背景模糊是预光栅化静态位图，key 必须含封面内容指纹**：`blurred_artwork_rasterizer.dart` → 160px `ui.Image`，LRU 6 首。key = `songKey + sigma + 指纹`（`fingerprintOf()` 采样 FNV-1a）；禁只用 `songKey`（换封面不刷新），禁 `bytes.hashCode`/identity。小窗 `small_*`、小窗面板 `BackdropFilter`、自定义图片背景仍实时模糊。
- **视图切换禁换根 Widget 类型**：两视图共用同一 StatefulWidget，只换 body sliver，否则 Element 无法复用（切 tab 整页闪）。
- **写 `songs` 表只能基于 DB 记录 `copyWith`**：`_songCompanion` 整行写入。`SongMetadata(...)` 再整行写会把未列出的列（year/genres/bitrate/sampleRate/format/codec/albumArtist/sourceFlags/fileRating/hasArtwork/waveformBlob/deletedAt/createdAt）清成 null——已因此让歌从年份/流派页消失。新记录才用最小兜底构造；`id/mediaId/isAppModified/waveformBlob/deletedAt` 永不出现在读标签路径的 copyWith 里；封面四列用 `artworkProbed = generateThumbnail && (!tagReadFailed || 有产出)`。
- **`TagLibMetadata` 新增标签列要三处同步**：字段 → 四个 reader（`readMetadataIsolate`/`readMetadataWithImageIsolate`/两个 `_readMetadata*IsolateEntryPoint`）赋值 → `processMetadata` 里 `值 ?? base.值` 回落。
- **诊断钩子 `_debugWarnColumnWipe`**：写库时「库里某列非空 → 本次写成空」会打 `[ColumnWipe]` + 调用栈（13 列）。看到它 = 有调用方还在拼整行。
- **排序写入必须显式推进结构版本**：走 `_markSortOrderChanged()`（`_structureRevision++` + `_rootFoldersView = null`），否则列表停在旧顺序、顶栏「仅此目录」不刷新。默认排序 = 音轨号升序（`_defaultSortCriteria`）；`SortCriteriaX.fromStorageValue` 兜底仍是 `filename`（WebDAV 共用）。UI 唯一写入口 `applySortSettings()`。
- **`Slider` 是受控组件，`onChanged` 必须回流到 `value`**：否则拇指停在按下位置、只随进度抖跳。参照 `_StandardProgressSlider`、`WaveformProgressBar`、`MiniPlayerProgressInfo`。

## 其它约定

- 新增实体右键菜单三件套：`lib/widgets/<entity>_context_menu.dart`（`show<Entity>ContextMenu` + `show<Entity>BottomSheet` + 共用 `_handle...`）；条目根挂 `GestureDetector(behavior: opaque, onSecondaryTapDown, onLongPress)`；l10n 加 `view<Entity>Details`/`copy<Entity>Name`。首页卡片不传 `onMultiSelect`。
- 流派/年份封面统一 `GenreSummary.representativeArtworkPath/ThumbnailPath` + `SongThumbnail`（列表 44、详情 96/116），兜底 `surfaceContainerHighest` + `Icons.music_note_rounded`；只剩 `normalizeGenreKey()` 与 `pickGenreDisplayName()`。**两套「代表曲」规则不可混用**（集合摘要取 DB 顺序第一首带封面的歌 vs `buildAlbumSections` 的首组），故列表页/详情页头都不显示集合级封面，封面只在专辑分组里。

## 环境

- 搜索用 `rg`/`fd`：PATH 里的 grep/find 是 toybox shim，会漏匹配。
- `flutter` 不在 PATH：`export PATH="/d/flutter/3.44.9/bin:$PATH"`；`~/.pub-cache` 被沙箱拦写 → `flutter analyze --no-pub`。
- 跑 `flutter test` 前必须 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy GLOBAL_AGENT_HTTP_PROXY` 并 `export NO_PROXY=127.0.0.1,localhost`，否则全部加载失败。
- 无 `groovy`/`pwsh`；验证 Groovy 片段用 Gradle 自带 jar。
