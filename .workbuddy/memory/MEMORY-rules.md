# 硬性禁止（全文）

> `MEMORY.md` 主文件只放索引，条目全文在这里。遇到相关领域（iOS 目录、歌词、扫描、播放页背景、写库）时先读本文件对应条。

- **iOS security-scoped URL 禁止先标准化再 start**：picker 返回的 URL 一旦过 `standardizedFileURL` / `resolvingSymlinksInPath()` 就丢 scope token，`startAccessingSecurityScopedResource()` 必回 false。start / `bookmarkData` 只能用原始 URL；iOS 持久化 bookmark 必须 `.minimalBookmark`（空 options 跨启动无 scope）。scope 状态只能取 start 返回值，禁止假设成功（`beginScopedAccess` 曾恒返回 true → 目录添加成功但扫描 0 首、EPERM）。**根目录可用性的最终判据是可读性探测，不是 scope 标志**（macOS `~/Music` 无 scope 但可读）。

- **宿主顶栏给三级页让位**：详情在子分类 Navigator 里，宿主 `AppTopNavBar` 后画会盖住 → `onHasChildRouteChanged` → `hideTopNavBar`（`Duration.zero`）。测试取 `library_subhost_top_bar` 外层 `AnimatedOpacity` 的 `.at(1)`。
- **嵌套 `AutoHideHeaderScope` 各管自己的滚动**：`_ownsNotification()` 按「来源往上最近一个 scope 是否自己」判定，外层不收内层通知。
- **禁持二进制、禁按字节做 key**：blob 列禁进 `MusicFolder.files` 与 `representativeSongCache`（执行点 `scanner_tree_builder` 三工厂、`_updateMusicFileInFolder`；数据源永远 SQLite）。播放态封面每次新 `Uint8List`，key 只能用品内容指纹（禁 `bytes.hashCode` / identity）。
- **IndexedStack 常驻子页禁挂 PopScope**：`canPop:false` 会让整条路由 `doNotPop` 并派发给全部 PopEntry。共用 tab 写进 `_handleBackPressed()`；艺术家/流派/年份套 `library_selection_back_guard.dart`。
- **多选状态禁条件切换 widget 根节点**：runtimeType 一变子树重建，dispose 微任务清掉刚建的多选状态。唯一状态 `librarySelectionStateProvider`。`SongSelectionMixin` 只是 `SelectionStateMixin<T, String>` 的薄壳（`on SelectionStateMixin<T, String>`），使用方**必须串联书写**：`with SelectionStateMixin<X, String>, SongSelectionMixin<X>`；禁再往 Song 版里抄一份状态/手势逻辑。
- **禁裸 `ref.watch(scannerServiceProvider)`**：缩略图每张 `notifyListeners()`。用 `ref.read` + `.select((s) => s.structureRevision)`；`rootFolders` 返回缓存的 `_rootFoldersView`；`build()` 只能 select `isScanning`。
- **MainLayout 是 rebuild 放大器**：`_buildCurrentPage()` 每次 build 新建非 const 页，任何 `setState` 都 rebuild 全部已访问页。别随手加 `ref.watch`。
- **Riverpod 3 禁在 `initState`/`dispose`/`build` 改 provider**：`dispose` 里 `Future.microtask(() => notifier.reset())`；`reset()` 先判 `ref.mounted` 与 `isDefault`。
- **Android 转场**：必须 `ZoomPageTransitionsBuilder(allowSnapshotting: false)`。
- **逐字歌词时钟禁直接对齐 `audioPositionProvider`**：250ms 阶梯 + 墙钟插值领先约 100ms。`_syncBaseline` 只取锚点 + `_correction`（240ms 摊入，>900ms 硬对齐），靠静态 `_resumeLineKeyMs/_resumePositionMs` 续接；`_advanceLocalPosition` 回退 >400ms 才算 seek，小幅回退每轮最多回拉 6ms。
- **曲库派生页禁把 reload 当首次加载**：判 loading 只认「没有旧值」，统一用 `library_overview_providers.dart` 的 `_needsFullPageLoad()`/`_isFatalError()`。
- **长列表禁 `SliverToBoxAdapter > ListView(shrinkWrap: true)`**：一律 `SliverList.builder`/`SliverFixedExtentList.builder`，逐行 `Align + ConstrainedBox(maxWidth: kSingleColumnContentMaxWidth)`。
- **播放页背景模糊是预光栅化位图，key 必须含封面内容指纹**：`blurred_artwork_rasterizer.dart`，LRU 6 首；key = `songKey + sigma + 指纹`；禁只用 `songKey`，禁 `bytes.hashCode`。小窗 `small_*`、`BackdropFilter`、自定义图片仍实时模糊。
- **背景层身份禁靠新建 `_SwitcherItem` 更新**：`_SafeBackgroundSwitcher` 的 Stack 子节点用 `ObjectKey(item)` 匹配，换 item 实例 = 换 key → 背景子树重建 → `_blurredImage` 归零 → 黑帧（「闪一下」）。只改 `item.child`。所有层统一 `FadeTransition(opacity: item.animation)`，禁给非最后一层换 `KeyedSubtree`。`StaticBlurredArtwork` cache miss 时**禁清空** `_blurredImage`，换图走 260ms 交叉淡化。
- **`vsync: this` 的 `AnimationController` 禁声明处初始化 `late final`**：首次求值发生在 `dispose()` 时 → 在 deactivate 的 element 上 `createTicker` → `Looking up a deactivated widget's ancestor is unsafe`（`_StaticBlurredArtworkState._crossFade` 踩过，8afc8301）。一律 `late final` 声明 + `initState` 赋值。该异常在 `_InactiveElements._unmountAll` 中抛出会中断整批 unmount（表现为别的 State 的 ticker 仍在跳）。
- **视图切换禁换根 Widget 类型**：两视图共用同一 StatefulWidget，只换 body sliver。
- **写 `songs` 表只能基于 DB 记录 `copyWith`**：`_songCompanion` 整行写入。`SongMetadata(...)` 整行写会把未列出列（year/genres/bitrate/format/codec/albumArtist/hasArtwork/waveformBlob/deletedAt…）清 null——已因此让歌从年份/流派页消失。`id/mediaId/isAppModified/waveformBlob/deletedAt` 永不进读标签路径的 copyWith；封面四列用 `artworkProbed = generateThumbnail && (!tagReadFailed || 有产出)`。
- **`TagLibMetadata` 新增标签列要三处同步**：字段 → 四个 reader 赋值 → `processMetadata` 的 `值 ?? base.值` 回落。诊断钩子 `_debugWarnColumnWipe` 打 `[ColumnWipe]` = 还有调用方在拼整行。
- **排序写入必须显式推进结构版本**：走 `_markSortOrderChanged()`。默认排序 = 音轨号升序；`SortCriteriaX.fromStorageValue` 兜底仍 `filename`（WebDAV 共用）。UI 唯一写入口 `applySortSettings()`。
- **`Slider` 是受控组件，`onChanged` 必须回流到 `value`**，否则拇指停在按下位置。参照 `_StandardProgressSlider`、`WaveformProgressBar`。
- **播放页动态流变背景 = `mesh_flow` 包**（`lib/widgets/dynamic_mesh_background.dart`，旧的 `mesh_gradient`/`il` 依赖已摘除）。`MeshFlowPainter.time` 已按 `speed` 缩放，**禁再乘 `flowSpeed`**（平方级把 0.05 压成不动）；`WarpGrid` 的 `time` 是可选项，不传则几何完全静态（只有贴图在转）。给 `MeshFlow` 传 `palette` 会让主题色异步刷新被判定为「封面变了」而反复重启过渡，有真封面时一律传 null。
- **网格 ↔ 列表条目内容禁双份渲染**：`SongZoomItem` 跨「网格↔列表」时曾同时构建两套布局 + 双层 `Opacity` 交叉淡化（每可见条目每帧两份文字排版 + 两次 saveLayer）。现在唯一决策点 `_FolderZoomSliverBuilderState._resolveContentHandoff()`，滞回 0.55/0.45，`metrics.renderAsGrid` 只选一份，交接处靠 `contentReveal` 压暗。禁退回「只在 `gridMorph >= 0.99` 才用网格布局」的分点判定。
