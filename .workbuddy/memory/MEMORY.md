# 长期项目笔记

> 只留「会反复咬人的不变量」。完整措辞与被否方案见 `MEMORY-archive-2026-10-21.md`；过程见同日 `YYYY-MM-DD.md`。

## 单一数据源

| 主题 | 唯一来源 / 规则 |
|---|---|
| Rail 宽度 | `layout_constants.dart` 的 `sidebarRailWidthFor()`，禁 `80.0` |
| FFmpeg 版本 | `audio_core/ffmpeg_version.env`，禁脚本硬编码；flatpak 清单与 `build-ffmpeg.yml` 的 tag 靠手同步 |
| 远程下载落盘 | `buildLocalTrackPath()` + `RemoteDownloadRequest.batches`：`.album`=专辑一层；`.artist`=`collectionFolder`+专辑（无名回落 `albumArtist ?? artist`）；`.playlist`=`collectionFolder` 无专辑层；WebDAV/SMB 照抄远端层级。层级由**页面/栏目**决定，禁按单曲/多选区分。唯一入队口 `enqueue(RemoteDownloadRequest)`；多选 `fetchSelectedBatches`（禁退化成 `List<MusicFile>`）；单曲走 `downloadLayout`/`downloadCollectionFolder`，禁按单曲 `artist` 分层（合辑被拆散） |
| 下载落盘前载荷校验 | `RemotePayloadGuard.inspect(file, contentType, parseSubsonicError)`，必须在「有字节就算成功」之前。只读文件头 2048B（禁按大小阈值，反代错误页可几 MB）：音频魔数放行 → Subsonic 失败 JSON（`parseErrorBody`）→ `text/*`/json/xml 或首字节 `<`/`{`/`[` 判非媒体（`RemotePayloadException`，code=-1）。`_downloadTask` 与 `downloadRemoteTrackToTempFile` 共用 |
| 下载反馈 | `showRemoteDownloadQueuedFeedback(context, ref, count)`：单曲 `addedToDownloadQueue`，批量 `batchAddedToDownloadQueue`；禁手抄 SnackBar +「查看进度」push |
| 服务端拒绝下载 | Subsonic：`download.view` 禁止时回 200 + 失败 JSON（code 50）→ `isDownloadsDisabled`，任务 failed + 每 server 提示一次。Jellyfin：走 `buildStreamUrl`（`/Audio/{id}/stream`），不受「允许下载」策略约束；拒绝是 401/403/404 → `_describeHttpFailure()` → `remoteDownloadUnauthorized`（每 server 一次）/ `remoteDownloadTrackMissing`（只落任务 error） |
| 临时下载分支 | `downloadRemoteTrackToTempFile` 必须先查 `AudioStreamCacheManager`（命中即拷本地，不走网络），未命中再按协议分派：subsonic→`buildDownloadUrl`、jellyfin→`authenticate()`+`buildStreamUrl(maxBitRate:0)`、smb→`LocalStreamProxy.buildSmbStreamUrl`、其余→`WebDavClient`。**禁只判 subsonic、其余全落 WebDavClient**（Jellyfin/SMB 的 id 不是路径，必然 404；实机「正常」只因缓存命中） |
| 曲库数据 | `libraryCatalogProvider` 是唯一订阅 `db.watchAllSongMetadata()` 处；新视图用 `catalogDerived(ref, ...)`，禁自己 `await for`；派生 provider 保持 `StreamProvider` 与原名单（测试 override）。`songs` 排除 external/deletedAt，`visibleSongs` 再加根目录/来源 |
| 返回键 | `MainLayout._handleBackPressed()`：Modal → 播放抽屉 → index 2 → index 0 回上级 → index 4 传输中拦 → `SystemNavigator.pop()` |
| 队列整体替换 | `PlaylistController.replaceActiveTracksAndSelect`。禁拆成 `updatePlaylistTracks`+`playByIndex`（`currentMusic` 瞬时 null，Dock 重播收起动画）；冷启动恢复同理禁拆 `addTracksToPlaylist`+`setActivePlaylist` |
| 浮动 Dock 收起 | `floatingDockCollapsed(Progress)Provider`，开关 `enableFloatingDockScrollCollapse`；切主页面/子分类**禁** `setCollapsed`，只 `helper.reset(ref)`。顶部缓冲展开必须边沿触发，且边沿只对同一 Scrollable 成立（`notification.context` 判同源）；底部无条件展开 |
| l10n | 9 个 `lib/l10n/app_*.arb` 同步，模板 `app_zh.arb`；缺 key 静默回退中文只记 stdout；改完 `flutter gen-l10n` |
| 设置项 | `settings_service.dart` 三段 → 6 处同步：key 常量、`SettingProperty`、getter+setter、`resetXxx()`、`settings_search_registry.dart`、`sections/<组>_section.dart` |
| 流派聚合键 | `normalizeGenreKey()`（`_genreKeyEquivalents` 收敛 `JPop`→`j pop`）；派生 `queryKey` 与 `matchGenreAssetKey()` 同源；`_acronymDisplays` 吃 `raw.toLowerCase()` 不能跟着改；`_substringAssetRules` 连写 needle 必须留 |
| 详情三页 | `album_sections.dart`、`collection_detail_content.dart`、`collection_detail_header.dart`、`detail_page_shell.dart`；禁各写分组排序/曲目行；分组宽 ≥600 走「左封面右列表」 |
| 洞察页视图状态 | `LibraryInsightFilterNotifier`；复位点唯一 `_LibrarySubHostPageState.dispose`（微任务 `reset()`）；切子分类不销毁宿主 → 保留，回仪表盘才复位 |
| 子分类导航域 | `library_tab_navigator.dart`（每分类一条 `Navigator` + `HeroController`）挂宿主 `IndexedStack`。切分类只改 provider/索引，**禁 popUntil**；tab 根内边距在路由 builder 重算 |
| 洞察页列表 | `library_insight_list.dart`（单曲/专辑同一 widget，只换 body sliver）、`insight_metric_text.dart`；禁再写 `LibraryRankedSongList`/`AlbumList`；行内边距唯一来源 `_insightRowPadding` + `kInsightListHorizontalInset` |
| 远程封面 | `remote_artwork_widget.dart`：磁盘落盘后**禁** `setState` 切 `Image.file`（换源重解码 → 空白帧）；`gaplessPlayback = _renderedImageUrl == imageUrl`；`didUpdateWidget` 里 coverArtId 变必须 `_localDiskPath = null`。判「同一张图」只能比 path/URL，禁 `bytes.hashCode`/identity |
| 远程库二次请求反馈 | `RemoteLibraryReloadingOverlay` + 页面级 `_isReloadingContent`，叠在 `body` 的 Stack；触发点只有真实发请求的三处：专辑排序、歌曲/艺术家「只看收藏」补齐；首屏走各 tab 的 `isLoading && list.isEmpty` |
| 远程播放写回缓存 | `AudioStreamCacheProxy` 把转发给播放器的 chunk 同步 append 到 `<cache>.part`（`StreamCacheWriter`），不再无条件另开第二条全量下载。`.part` 必须是 0 起**连续前缀**且 `written == expectedTotal` 才 rename；不完整就 `abort()` 删掉（`isTrackCached` 只看存在且 >0，半截文件绝不能占正式名）。同 key 单写入者：`beginStreamWrite` 用 `_pendingStreamWriteKeys` **同步**占位（内部有 await），`ensureTrackCached` 先 `await writer.done` 再决定是否真下载。只在 200 / 206-from-0 且有总长度时生效，chunked（Subsonic 转码、Jellyfin 非 static）退化为「转发 + 第二条下载」；tee 失败同样回退，故最坏等于旧行为 |
| 写回收尾时机 | `writer.complete()`（rename + `onTrackCached`）必须在 `request.response.close()` **之前**，结构上靠 `try { ...完成... } finally { await close(); }` 固化。`close()` 要等播放器把缓冲排空，即**整首歌的播放时长**；而 `onTrackCached` 是波形 / 封面 / 元数据的唯一触发点（`_handleRemoteTrackCacheReady` → `getWaveformData(localFilePath:)`），放 `close()` 之后会让波形与音频信息整首不显示，**只有 seek 才显示**（seek 中断 tee → 回退第二条下载 → 缓存秒好）。另：所有 `unawaited` 的 prefetch 必须带 `onError`，否则连接失败会漏成调用方 zone 的未捕获异步错误 |

## 硬性禁止

- **宿主顶栏给三级页让位**：详情在子分类 Navigator 里，宿主 `AppTopNavBar` 后画会盖住 → `onHasChildRouteChanged` → `hideTopNavBar`（`Duration.zero`）。测试取 `library_subhost_top_bar` 外层 `AnimatedOpacity` 用 `.at(1)`。
- **嵌套 `AutoHideHeaderScope` 各管自己的滚动**：`_ownsNotification()` 按「来源往上最近一个 scope 是否自己」判定，外层不收内层通知。
- **禁持二进制、禁按字节做 key**：blob 列禁进 `MusicFolder.files` 与 `representativeSongCache`（执行点 `scanner_tree_builder` 三工厂、`_updateMusicFileInFolder`；数据源永远 SQLite）。播放态封面每次新 `Uint8List`，key 只能用品内容指纹。
- **IndexedStack 常驻子页禁挂 PopScope**：`canPop:false` 会让整条路由 `doNotPop` 并派发给全部 PopEntry。共用 tab 写进 `_handleBackPressed()`；艺术家/流派/年份套 `library_selection_back_guard.dart`。
- **多选状态禁条件切换 widget 根节点**：runtimeType 一变子树重建，dispose 微任务清掉刚建的多选状态。唯一状态 `librarySelectionStateProvider`。
- **禁裸 `ref.watch(scannerServiceProvider)`**：缩略图每张 `notifyListeners()`。用 `ref.read` + `.select((s) => s.structureRevision)`；`rootFolders` 返回缓存的 `_rootFoldersView`（别现写 `List.unmodifiable`）；`build()` 只能 select `isScanning`。
- **MainLayout 是 rebuild 放大器**：`_buildCurrentPage()` 每次 build 新建非 const 页，任何 `setState` 都 rebuild 全部已访问页。别随手加 `ref.watch`。
- **Riverpod 3 禁在 `initState`/`dispose`/`build` 改 provider**：`dispose` 里 `Future.microtask(() => notifier.reset())`；`reset()` 先判 `ref.mounted` 与 `isDefault`。
- **Android 转场**：必须 `ZoomPageTransitionsBuilder(allowSnapshotting: false)`。
- **逐字歌词时钟禁直接对齐 `audioPositionProvider`**：250ms 阶梯 + 墙钟插值领先约 100ms。`_syncBaseline` 只取锚点 + `_correction`（240ms 摊入，>900ms 硬对齐），靠静态 `_resumeLineKeyMs/_resumePositionMs` 续接；`_advanceLocalPosition` 回退 >400ms 才算 seek，小幅回退每轮最多回拉 6ms。
- **曲库派生页禁把 reload 当首次加载**：判 loading 只认「没有旧值」，统一用 `library_overview_providers.dart` 的 `_needsFullPageLoad()`/`_isFatalError()`。
- **长列表禁 `SliverToBoxAdapter > ListView(shrinkWrap: true)`**：一律 `SliverList.builder`/`SliverFixedExtentList.builder`，逐行 `Align + ConstrainedBox(maxWidth: kSingleColumnContentMaxWidth)`。
- **播放页背景模糊是预光栅化位图，key 必须含封面内容指纹**：`blurred_artwork_rasterizer.dart`，LRU 6 首；key = `songKey + sigma + 指纹`；禁只用 `songKey`，禁 `bytes.hashCode`。小窗 `small_*`、`BackdropFilter`、自定义图片仍实时模糊。
- **背景层身份禁靠新建 `_SwitcherItem` 更新**：`_SafeBackgroundSwitcher` 的 Stack 子节点用 `ObjectKey(item)` 匹配，换 item 实例 = 换 key，整棵背景子树重建 → `_blurredImage` 归零 → 黑帧（观感「闪一下」）。只改 `item.child`（可变字段）。所有层统一 `FadeTransition(opacity: item.animation)`，禁给非最后一层换 `KeyedSubtree`（runtimeType 变同样重建）。`StaticBlurredArtwork` cache miss 时**禁清空** `_blurredImage`，换图走 260ms 交叉淡化。`flutter_taglib` 的 `AudioInfo` 无 `bitDepth`（`flutter_taglib_metadata_bridge.dart:572`）→ `flutter test` 全包编译不过，需先用 `flutter analyze` 或临时置 null 验证。
- **视图切换禁换根 Widget 类型**：两视图共用同一 StatefulWidget，只换 body sliver。
- **写 `songs` 表只能基于 DB 记录 `copyWith`**：`_songCompanion` 整行写入。`SongMetadata(...)` 整行写会把未列出列（year/genres/bitrate/format/codec/albumArtist/hasArtwork/waveformBlob/deletedAt…）清 null——已因此让歌从年份/流派页消失。`id/mediaId/isAppModified/waveformBlob/deletedAt` 永不进读标签路径的 copyWith；封面四列用 `artworkProbed = generateThumbnail && (!tagReadFailed || 有产出)`。
- **`TagLibMetadata` 新增标签列要三处同步**：字段 → 四个 reader 赋值 → `processMetadata` 的 `值 ?? base.值` 回落。
- **诊断钩子 `_debugWarnColumnWipe`**：打 `[ColumnWipe]` = 有调用方还在拼整行。
- **排序写入必须显式推进结构版本**：走 `_markSortOrderChanged()`，否则列表停旧顺序。默认排序 = 音轨号升序；`SortCriteriaX.fromStorageValue` 兜底仍 `filename`（WebDAV 共用）。UI 唯一写入口 `applySortSettings()`。
- **`Slider` 是受控组件，`onChanged` 必须回流到 `value`**，否则拇指停在按下位置。参照 `_StandardProgressSlider`、`WaveformProgressBar`。

## 其它约定

- 新增实体右键菜单三件套：`lib/widgets/<entity>_context_menu.dart`（`show<Entity>ContextMenu` + `show<Entity>BottomSheet` + 共用 `_handle...`）；条目根挂 `GestureDetector(behavior: opaque, onSecondaryTapDown, onLongPress)`；l10n 加 `view<Entity>Details`/`copy<Entity>Name`。
- 流派/年份封面统一 `GenreSummary.representativeArtworkPath/ThumbnailPath` + `SongThumbnail`（列表 44、详情 96/116）。**两套「代表曲」规则不可混用**（集合摘要取 DB 顺序第一首带封面的歌 vs `buildAlbumSections` 的首组），故列表页/详情页头都不显示集合级封面。
- 远程库工具栏：「只看收藏」永远是**独立开关**（`RemoteStarFilterButton`，行内顺序 搜索 → 心形 → 排序下拉），**禁写进排序下拉**，也**禁把它做成 `getAlbumList(type:'starred')` 的服务端请求**（会顶掉排序、闪遮罩、每次切换都发请求）。三个 Tab 统一：收藏集单独取一次（`getStarredSongs/Artists/Albums`）存在内存 Set，`_getFiltered*()` 里本地过滤；切开关只 setState，只有 Set 为空才补一次请求；专辑可用列表项自带的 `starred`／`isFavorite` 预填充。
- 「定位当前播放」唯一决策点 `SongLocatorHelper.locateCurrentPlayingSong`：Subsonic/Jellyfin 只走 `_openAlbumForRemoteSong`（`getSong` → `albumId`/`parent` 非空 → 开专辑详情页 + 高亮），**禁回落到本地扫描树**、**禁再用 `songNotInScannedFolders` 描述远程失败**（统一 `remoteAlbumUnavailable`）；albumId 必须 `isNotEmpty`（Jellyfin 恒输出空串）；服务器列表要 `await` 而非读 `asData`。WebDAV/SMB 分支另有自己的一套，未动。
- **禁对整仓跑 `dart format`**：新格式化器会重排 `remote_library_page.dart` 等整份文件（数百行噪声）。改完只跑 `flutter analyze lib`。

## 环境

- 搜索用 `rg`/`fd`：PATH 里的 grep/find 是 toybox shim，会漏匹配。
- `flutter` 不在 PATH：`export PATH="/d/flutter/3.44.9/bin:$PATH"`。
- 跑 `flutter test` 前必须 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy GLOBAL_AGENT_HTTP_PROXY` 并 `export NO_PROXY=127.0.0.1,localhost`，否则全部加载失败。
- 无 `groovy`/`pwsh`；验证 Groovy 片段用 Gradle 自带 jar。
- 仓库源文件是 **CRLF**（`lib/l10n/app_*.arb` 等）：用 Python/脚本批量改必须显式保留行尾，否则整份文件 EOL 翻转。
