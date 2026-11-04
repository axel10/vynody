# 长期项目笔记

> 只留「会反复咬人的不变量」：名字 + 唯一入口。逐条全文与失败现象见
> `MEMORY-archive-2026-11-01.md`；过程见同日 `YYYY-MM-DD.md`。
> **UI / 渲染类不变量（缩放、歌词行、封面、详情页、导航）见 `MEMORY-ui.md`。**

## 单一数据源（唯一入口 / 唯一开关）

| 主题 | 规则 |
|---|---|
| Rail 宽度 | `sidebarRailWidthFor()`（`layout_constants.dart`），禁 `80.0` |
| 队列抽屉窗口宽 | `minWindowWidthForDrawer()`：窗口 ≥ 抽屉宽 + `kMinMainContentWidth`(400)，WindowOptions/退出小窗/拖拽复位/最小窗口尺寸同源派生 |
| FFmpeg 版本 | `audio_core/ffmpeg_version.env`，禁脚本硬编码；flatpak 清单与 `build-ffmpeg.yml` tag 靠手同步 |
| Android 插件构建目录 | `android/build.gradle.kts:48` 钉死 `$TMPDIR/vynody_build/${project.name}`（无 pub 版本）。升级插件后该模块 Kotlin 增量缓存串味 → 「类能解析、顶层 const val 全 Unresolved」，`--rerun-tasks` 即过。修：`rm -rf $TMPDIR/vynody_build/<name>`（`flutter clean` 清不到，自定义 clean 只删根 buildDir） |
| 远程下载落盘 | `buildLocalTrackPath()` + `RemoteDownloadRequest.batches`。层级由**页面/栏目**定（`.album` 一层 / `.artist` 目录+专辑 / `.playlist` 无专辑层 / WebDAV·SMB 照抄远端），禁按单曲或多选区分。唯一入队口 `enqueue()`；多选 `fetchSelectedBatches`；单曲走 `downloadLayout`/`downloadCollectionFolder` |
| 载荷校验 | `RemotePayloadGuard.inspect()` 必须在「有字节就算成功」之前；只读头 2048B，禁按大小阈值。`_downloadTask` 与 `downloadRemoteTrackToTempFile` 共用 |
| 拒绝下载 / 临时下载 | Subsonic 禁用 `download.view` 回 200+失败 JSON(50) → `isDownloadsDisabled`；Jellyfin 走 `buildStreamUrl`，401/403/404 经 `_describeHttpFailure()`。临时下载先查 `AudioStreamCacheManager`，再按 server 分派（subsonic / jellyfin / smb / 其余 WebDav），**禁只判 subsonic** |
| Apple 安全作用域 | 唯一入口 `AppleFileAccessHolder`（scanner/playback/sharing/converter/fallback）。原生唯一协调器 `SecurityScopedFileAccessCoordinator` 按 `(scope key, holder)` 分账：`end` 只减自己那份、跨 holder 是 no-op、全 holder 归零才 `stopAccessing`，`forgetPersistentAccess` 才强制清零。begin/end 必须同 holder，禁裸 `beginScopedAccess(path)`。Dart 侧**未统一**：类型化 API（engine/controller）+ 裸 `audio_core.player` 通道（sharing / converter / file_selector）四门并存；playback holder 只 begin 不 end（2026-11-04 审计）。`sharing` 的 finally 只 end 真正 begin 成功的那条路径（分享目录与子文件同 scope key，两个都 end 会打掉 scanner 那份） |
| 曲库数据 | `libraryCatalogProvider` 是唯一订阅 `db.watchAllSongMetadata()` 处；新视图用 `catalogDerived(ref, ...)`。`songs` 排除 external/deletedAt，`visibleSongs` 再加根目录/来源 |
| 歌词进面板入口 | 唯一 `LyricsFetchCoordinator.ensureLyricsForSong`（队列内存 → SQLite → 分层查询；同曲 `lyricsFetchInFlightPath` 在途即忽略）。缓存键/查询**禁依赖 duration**（`lyricsCacheKeyForPath` / `readCachedLyricsRecordByPath` 只由 filePath 定）。来源优先级唯一 `kLyricsSourcePreferenceOrder`；fetch 落地与 watch 同步共用 `applyLyricsRecordToCurrent`；`result == null` 禁写空 lyrics |
| 翻译缓存写入 | `insertOrUpdateLyricsTranslationCache` **必须一条原子 upsert**（`DoUpdate(target: [cacheKey, languageCode])`），禁先 delete 再 insert：中间空快照会被订阅方当成真相，把内存流式译文整份覆盖成空（每行重播淡入）。`insertOnConflictUpdate()` 冲突目标是主键 `id`，命中不了 UNIQUE，并发写抛错。回归 `test/player/lyrics_translation_cache_watch_test.dart` |
| 译文快照不倒退 | 内存译文是流式期间唯一真相：`_mergeTranslationsWithoutRegression`（DB 非空行更少就沿用内存，翻译中空快照也沿用）+ `_mergeStreamingTranslatedLines`（同长度行网格新空补旧值）；收尾 `bumpLayoutRevision: true` 那次仍整份覆盖 |
| 返回键 | `MainLayout._handleBackPressed()`：Modal → 播放抽屉 → index 2 → index 0 回上级 → index 4 传输中拦 → `SystemNavigator.pop()` |
| 队列整体替换 | `PlaylistController.replaceActiveTracksAndSelect`（冷启动恢复同理），禁拆 `updatePlaylistTracks`+`playByIndex` |
| l10n / 设置项 | l10n：9 个 `app_*.arb` 同步，模板 `app_zh.arb`，改完 `flutter gen-l10n`。设置项：`settings_service.dart` 三段 → 6 处同步（key、`SettingProperty`、getter+setter、`resetXxx()`、`settings_search_registry.dart`、`sections/<组>_section.dart`） |
| 流派聚合键 | `normalizeGenreKey()`；派生 `queryKey` 与 `matchGenreAssetKey()` 同源；`_acronymDisplays` 吃 `raw.toLowerCase()` 不能跟着改；`_substringAssetRules` 连写 needle 必须留 |
| FFT 采集门 | 唯一决策点 `AudioService._updateEffectiveVisualizerState()` → `visualizer.setEnabled(_isFftCaptureAllowed)`（Pro 用缓存字段，禁热路径 `ref.read`）；采集与「画不画频谱」解耦，关开关禁 `setEnabled(false)`。Rust 侧 `setFftCaptureEnabled` no-op，靠 `get_latest_fft()` 开 1500ms 窗 |

## 硬性禁止（全文见 `MEMORY-rules.md`）

iOS security scope 禁标准化后再 start（判据是可读性探测）；宿主顶栏让位走 `onHasChildRouteChanged` → `hideTopNavBar`；嵌套 `AutoHideHeaderScope` 各管各自滚动；禁持二进制、禁按字节/identity 做 key；`IndexedStack` 常驻子页禁挂 `PopScope`；多选状态禁条件切换 root；`SongSelectionMixin` 必须串联书写；禁裸 `ref.watch(scannerServiceProvider)`；`MainLayout` 是 rebuild 放大器；Riverpod 3 禁在 `initState`/`dispose`/`build` 改 provider；Android 转场必须 `allowSnapshotting: false`；逐字歌词时钟禁直接对齐 `audioPositionProvider`；曲库派生页禁把 reload 当首次加载；长列表禁 `SliverToBoxAdapter > ListView(shrinkWrap: true)`；背景模糊 key 必须含封面内容指纹；`vsync: this` 的 controller 禁声明处 `late final`；视图切换禁换根 Widget 类型；写 `songs` 表只能基于 DB 记录 `copyWith`；`TagLibMetadata` 新增列要三处同步；排序写入走 `_markSortOrderChanged()`；`Slider.onChanged` 必须回流 `value`；`mesh_flow.time` 已含 speed。

## 其它约定 / 环境

见 `MEMORY-ops.md`：右键菜单三件套、流派年份封面、远程库「只看收藏」、定位当前播放、禁整仓 `dart format`；rg/fd、flutter PATH、`flutter test` 的代理变量、CRLF。
