# 长期项目笔记

> 只留「会反复咬人的不变量」。逐条全文与现实原因见 `MEMORY-archive-2026-10-23.md`；过程见同日 `YYYY-MM-DD.md`。

## 单一数据源（唯一入口 / 唯一开关）

| 主题 | 规则 |
|---|---|
| Rail 宽度 | `layout_constants.dart` 的 `sidebarRailWidthFor()`，禁 `80.0` |
| 队列抽屉窗口宽度 | 抽屉展开时窗口宽 ≥ 抽屉宽 + `kMinMainContentWidth`(400)，唯一公式 `minWindowWidthForDrawer()`（`right_queue_drawer_controller.dart`）。最小窗口尺寸必须同源派生，禁另写常量；初始化 `main.dart` WindowOptions、退出小窗模式、拖拽结束/双击复位都要过这个函数 |
| FFmpeg 版本 | `audio_core/ffmpeg_version.env`，禁脚本硬编码；flatpak 清单与 `build-ffmpeg.yml` tag 靠手同步 |
| 远程下载落盘 | `buildLocalTrackPath()` + `RemoteDownloadRequest.batches`：`.album`=专辑一层；`.artist`=`collectionFolder`+专辑（无名回落 `albumArtist ?? artist`）；`.playlist`=`collectionFolder` 无专辑层；WebDAV/SMB 照抄远端层级。层级由**页面/栏目**定，禁按单曲/多选区分。唯一入队口 `enqueue(RemoteDownloadRequest)`；多选 `fetchSelectedBatches`（禁退化成 `List<MusicFile>`）；单曲走 `downloadLayout`/`downloadCollectionFolder`，禁按单曲 `artist` 分层（合辑被拆散） |
| 落盘前载荷校验 | `RemotePayloadGuard.inspect(file, contentType, parseSubsonicError)`，必须在「有字节就算成功」之前。只读头 2048B（禁按大小阈值，反代错误页可几 MB）：音频魔数放行 → Subsonic 失败 JSON（`parseErrorBody`）→ `text/*`/json/xml 或首字节 `<`/`{`/`[` 判非媒体（`RemotePayloadException`，code=-1）。`_downloadTask` 与 `downloadRemoteTrackToTempFile` 共用 |
| 下载反馈 | `showRemoteDownloadQueuedFeedback(context, ref, count)`：单曲 `addedToDownloadQueue`，批量 `batchAddedToDownloadQueue`；禁手抄 SnackBar |
| 服务端拒绝下载 | Subsonic：`download.view` 禁用回 200 + 失败 JSON（code 50）→ `isDownloadsDisabled`。Jellyfin：走 `buildStreamUrl`（`/Audio/{id}/stream`），不受「允许下载」约束；拒绝是 401/403/404 → `_describeHttpFailure()` → `remoteDownloadUnauthorized`（每 server 一次）/`remoteDownloadTrackMissing`（只落任务 error） |
| 临时下载分支 | `downloadRemoteTrackToTempFile` 先查 `AudioStreamCacheManager`（命中即拷本地），未命中再分派：subsonic→`buildDownloadUrl`、jellyfin→`authenticate()`+`buildStreamUrl(maxBitRate:0)`、smb→`LocalStreamProxy.buildSmbStreamUrl`、其余→`WebDavClient`。**禁只判 subsonic、其余全落 WebDavClient**（Jellyfin/SMB 的 id 不是路径，必然 404；实机「正常」只因缓存命中） |
| 曲库数据 | `libraryCatalogProvider` 是唯一订阅 `db.watchAllSongMetadata()` 处；新视图用 `catalogDerived(ref, ...)`，禁自己 `await for`；派生 provider 保持 `StreamProvider` 与原名单（测试 override）。`songs` 排除 external/deletedAt，`visibleSongs` 再加根目录/来源 |
| 返回键 | `MainLayout._handleBackPressed()`：Modal → 播放抽屉 → index 2 → index 0 回上级 → index 4 传输中拦 → `SystemNavigator.pop()` |
| 队列整体替换 | `PlaylistController.replaceActiveTracksAndSelect`。禁拆成 `updatePlaylistTracks`+`playByIndex`（`currentMusic` 瞬时 null，Dock 重播收起动画）；冷启动恢复同理禁拆 `addTracksToPlaylist`+`setActivePlaylist` |
| 浮动 Dock 收起 | `floatingDockCollapsed(Progress)Provider`，开关 `enableFloatingDockScrollCollapse`；切主页面/子分类**禁** `setCollapsed`，只 `helper.reset(ref)`。顶部缓冲展开必须边沿触发，且边沿只对同一 Scrollable 成立（`notification.context` 判同源）；底部无条件展开 |
| l10n | 9 个 `lib/l10n/app_*.arb` 同步，模板 `app_zh.arb`；缺 key 静默回退中文只记 stdout；改完 `flutter gen-l10n` |
| 设置项 | `settings_service.dart` 三段 → 6 处同步：key 常量、`SettingProperty`、getter+setter、`resetXxx()`、`settings_search_registry.dart`、`sections/<组>_section.dart` |
| 流派聚合键 | `normalizeGenreKey()`（`_genreKeyEquivalents` 收敛 `JPop`→`j pop`）；派生 `queryKey` 与 `matchGenreAssetKey()` 同源；`_acronymDisplays` 吃 `raw.toLowerCase()` 不能跟着改；`_substringAssetRules` 连写 needle 必须留 |
| 详情三页 | `album_sections.dart`、`collection_detail_content.dart`、`collection_detail_header.dart`、`detail_page_shell.dart`；禁各写分组排序/曲目行；分组宽 ≥600 走「左封面右列表」 |
| 主从视图搜索 | 输入框唯一实现 `LibrarySearchField`；横屏左栏搜索走 `MasterDetailScaffold.masterPaneHeaderBuilder`（页头传 `LibraryCategoryHeader(showSearch: false)`），禁把列表搜索留在跨两栏的页头里；详情内搜索统一 `filterAlbumSections()`，**过滤后必须重算 `AlbumSection.startIndex`**；复位按 `source.id`/`artist.queryKey`，禁按歌曲列表 identity（播放写入会让曲库快照重算，会清掉正在输入的词）；**开关固定在操作区行尾最右端**（本地艺术家/流派/年份 + 远程艺术家/流派），禁再单独占一行右对齐 |
| 洞察页视图状态 | `LibraryInsightFilterNotifier`；复位点唯一 `_LibrarySubHostPageState.dispose`（微任务 `reset()`）；切子分类不销毁宿主 → 保留，回仪表盘才复位 |
| 子分类导航域 | `library_tab_navigator.dart`（每分类一条 `Navigator` + `HeroController`）挂宿主 `IndexedStack`。切分类只改 provider/索引，**禁 popUntil**；tab 根内边距在路由 builder 重算 |
| 洞察页列表 | `library_insight_list.dart`（单曲/专辑同一 widget，只换 body sliver）、`insight_metric_text.dart`；禁再写 `LibraryRankedSongList`/`AlbumList`；行内边距唯一来源 `_insightRowPadding` + `kInsightListHorizontalInset` |
| 远程封面 | `remote_artwork_widget.dart`：落盘后**禁** `setState` 切 `Image.file`（换源重解码 → 空白帧）；`gaplessPlayback = _renderedImageUrl == imageUrl`；`didUpdateWidget` 里 coverArtId 变必须 `_localDiskPath = null`。判「同一张图」只能比 path/URL |
| 远程库二次请求遮罩 | `RemoteLibraryReloadingOverlay` + 页面级 `_isReloadingContent`，叠在 `body` 的 Stack；触发点只有真正发请求的三处：专辑排序、歌曲/艺术家「只看收藏」补齐；首屏走各 tab 的 `isLoading && list.isEmpty` |
| 远程播放写回缓存 | `AudioStreamCacheProxy` 把转发给播放器的 chunk 同步 append 到 `<cache>.part`（`StreamCacheWriter`）。`.part` 必须 0 起**连续前缀**且 `written == expectedTotal` 才 rename，否则 `abort()` 删掉（`isTrackCached` 只看存在且 >0，半截文件不能占正式名）。同 key 单写入者：`beginStreamWrite` 用 `_pendingStreamWriteKeys` **同步**占位，`ensureTrackCached` 先 `await writer.done`。只在 200/206-from-0 且有总长度时生效，chunked 退化为「转发 + 第二条下载」 |
| 写回收尾 | `writer.complete()`（rename + `onTrackCached`）必须在 `request.response.close()` **之前**（`try { …完成… } finally { await close(); }`）。`close()` 要等播放器排空缓冲 = 整首歌时长；`onTrackCached` 是波形/封面/元数据的唯一触发点（`_handleRemoteTrackCacheReady` → `getWaveformData(localFilePath:)`），放到 `close()` 之后 → 波形与音频信息整首不显示、**只有 seek 才显示**。所有 `unawaited` 的 prefetch 必须带 `onError` |
| FFT 采集门 | 唯一决策点 `AudioService._updateEffectiveVisualizerState()` → `visualizer.setEnabled(_isFftCaptureAllowed)`，`_isFftCaptureAllowed = _isProUnlocked && !_isAppBackgrounded && !_isWindowMinimized`（Pro 用缓存字段 `_isProUnlocked`，禁在热路径 `ref.read`）。**采集与「播放页是否画频谱」解耦**：`_userVisualizerEnabled = isProUnlocked && settings.isVisualizerEnabled`（默认：桌面 true、移动 false）只管 `isVisualizerEnabled` / `audioIsVisualizerEnabledProvider` → 播放页 `shouldDrawVisualizer`。关开关**禁** `setEnabled(false)`：那会 `resetState()` + `stopAll()`，迷你播放器 `mini_player` 的 `_currentRawBins` 一起断（非 Pro 无频谱是有意的）。引擎侧 Rust `setFftCaptureEnabled` no-op，靠 `get_latest_fft()` 的 `record_fft_request()` 开 1500ms 计算窗；Android `setFftCaptureEnabled(false)` → `FFTAudioProcessor.isPaused`。Android 推送按 Dart 30Hz 节流：`fftEmitIntervalMs = 33L`，且每轮 **drain 全队列、每个 player 只留最新一帧**（禁一次 poll 一帧：hop ≈86Hz 会把队列堆到 20 条上限 = 频谱滞后 200ms+） |
| 缩放条目内容侧 | 网格↔列表只渲染一份：唯一决策点 `_FolderZoomSliverBuilderState._resolveContentHandoff()`，滞回 0.55/0.45 → `metrics.renderAsGrid` + `contentReveal`。禁退回「`gridMorph >= 0.99` 才算网格」的分点判定 |

## 硬性禁止（条目全文见 `MEMORY-rules.md`）

- iOS security scope：禁标准化后再 start；可用性判据是可读性探测
- 宿主顶栏让位：`onHasChildRouteChanged` → `hideTopNavBar`
- 嵌套 `AutoHideHeaderScope` 各管自己的滚动
- 禁持二进制、禁按字节/identity 做 key
- `IndexedStack` 常驻子页禁挂 `PopScope`
- 多选状态禁条件切换 widget 根节点；`SongSelectionMixin` 必须串联书写
- 禁裸 `ref.watch(scannerServiceProvider)`
- `MainLayout` 是 rebuild 放大器
- Riverpod 3 禁在 `initState`/`dispose`/`build` 改 provider
- Android 转场必须 `allowSnapshotting: false`
- 逐字歌词时钟禁直接对齐 `audioPositionProvider`
- 曲库派生页禁把 reload 当首次加载
- 长列表禁 `SliverToBoxAdapter > ListView(shrinkWrap: true)`
- 背景模糊 key 必须含封面内容指纹
- 背景层身份禁靠新建 `_SwitcherItem` 更新
- `vsync: this` 的 `AnimationController` 禁声明处 `late final`
- 视图切换禁换根 Widget 类型
- 写 `songs` 表只能基于 DB 记录 `copyWith`
- `TagLibMetadata` 新增标签列要三处同步
- 排序写入必须走 `_markSortOrderChanged()`
- `Slider` 的 `onChanged` 必须回流到 `value`
- `mesh_flow` 的 `time` 已含 speed，禁再乘 `flowSpeed`

## 其它约定 / 环境

见 `MEMORY-ops.md`：右键菜单三件套、流派年份封面、远程库「只看收藏」、定位当前播放、禁整仓 `dart format`；rg/fd、flutter PATH、`flutter test` 的代理变量、CRLF。
