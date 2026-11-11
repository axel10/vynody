# 远程媒体库全库播放与随机播放改造计划

## 一、现状是什么

1. **歌曲页数据加载机制**：
   - 远程媒体库的歌曲页（`RemoteLibrarySongsView`）采用分页增量拉取机制，单批次数量固定为 500 首（`pageSize = 500`）。
   - 首次进入加载第一页，后续通过触底滑动触发 `onLoadMore` 追加下一页。

2. **播放动作现状**：
   - 歌曲页工具栏的“播放全部”与“随机播放”（`_playAll`）直接读取当前页面已加载的 `widget.songs`。
   - 若曲库有数千甚至上万首歌曲，只要用户未手动滑到底部，“播放全部”就仅仅播放已经拉到本地的局部切片；“随机播放”也仅仅是对该局部切片调用本地 `playlist.shuffle()`。

3. **客户端接口抽象现状**：
   - `RemoteMediaLibraryClient` 统一抽象层中仅有 `getSongs({query, count, offset})`，缺乏获取全库随机歌曲的统一接口。
   - `SubsonicClient` 内部虽已实现 `getRandomSongs.view`，但未在抽象接口中暴露，UI 无法调用。
   - `JellyfinClient` 虽然支持 `sortBy` 参数，但未封装针对全库随机抽取（`SortBy=Random`）的标准端点。

4. **元数据与封面管理现状**：
   - 歌曲模型 `MusicFile` 仅在内存中保存歌曲文本元数据（标题、艺术家、专辑、时长等），`artworkBytes` 为空，封面以虚拟 URI（`subsonic-cover://` / `jellyfin-cover://`）记录。
   - 封面图片采用 `RemoteArtworkWidget` + `SliverGrid(builder)` 进行视口懒加载与磁盘二进制文件缓存（`thumbnails/remote_*.bin`），离开视口后受 Flutter 原生 `imageCache` 的 LRU 机制自动回收。内存中不存在全量常驻位图的问题。

---

## 二、痛点是什么

1. **“假·随机播放”体验割裂**：
   - 无法覆盖整个远程曲库，无论曲库有多大，随机播放永远只能随机到排在最前面的几百首，后面的曲目永远无法被随机播放。

2. **“假·播放全部”功能名不副实**：
   - 用户期望点击“播放全部”能够按顺序听完整个曲库，但目前受限于分页，实际上成了“播放当前已显示的所有歌曲”。

3. **批量拉取缺乏进度管控与防阻塞保障**：
   - 若直接无脑循环拉取全库数万条数据，缺乏可取消的进度指示会让用户误以为界面卡死；
   - 一次性将数万条原始 JSON 进行 `jsonEncode` 写入本地数据库，容易导致主线程短暂冻结，发生掉帧。

---

## 三、理想状态是什么

1. **真·全库随机播放（Shuffle All）**：
   - 点击“随机播放”时，由服务端在全曲库范围内进行真正的高质量随机抽取（默认 200~500 首），通过统一客户端接口返回，秒级起播。
   - 不必等待全库下载即可享受均匀覆盖整座曲库的随机电台体验。

2. **平滑可靠的“播放全部”（Play All）**：
   - 若当前页面已经全部加载完毕（`hasMore == false`），直接以当前列表即刻起播，零网络开销；
   - 若存在尚未加载的数据，无缝唤起现有轻量加载进度浮层（`runWithRemoteTrackLoadProgress`），分批次在后台拉取剩余曲目，支持随时取消；
   - 拉取完成的歌曲同步更新给当前页面列表和内存缓存，避免重复拉取；
   - 拉取过程中仅维护纯文本元数据模型，保持极低的内存与 CPU 开销。

---

## 四、具体改动方法与实施步骤

### 步骤 1：底层接口与客户端能力扩展
1. **统一抽象层扩展 (`lib/player/remote/clients/remote_media_library_client.dart`)**：
   - 增加方法：
     ```dart
     Future<List<Map<String, dynamic>>> getRandomSongs({int size = 500});
     ```
2. **Subsonic 客户端适配 (`lib/player/remote/clients/subsonic_client.dart`)**：
   - 对接已有的 `getRandomSongs({int size = 500})`，确保正确映射 `getRandomSongs.view`。
3. **Jellyfin 客户端适配 (`lib/player/remote/clients/jellyfin_client.dart`)**：
   - 实现 `getRandomSongs`：调用 `/Users/{userId}/Items`，附带 `IncludeItemTypes=Audio`、`Recursive=true`、`SortBy=Random`、`Limit=size`。

---

### 步骤 2：全库歌曲批量加载辅助逻辑 (`lib/utils/remote_library_playback.dart` 等)
1. **封装可取消的分页轮询服务**：
   - 实现 `fetchAllRemoteSongs({client, initialSongs, onProgress, ...})`；
   - 复用现有 `runWithRemoteTrackLoadProgress` 浮层组件展示加载进度（如“正在加载曲目 1500 / 4800...”），且在用户点击取消时支持平滑中断退出；
   - 当服务端返回的批次小于 `pageSize`（500 首）或为空时自动判定为拉取结束。

---

### 步骤 3：页面与交互层改造 (`lib/pages/remote/widgets/remote_library_songs_tab.dart` 及宿主页)
1. **改造 `_playAll(shuffle: true)`（随机播放全部）**：
   - 点击随机播放按钮时，调用 `_client.getRandomSongs(size: 500)`；
   - 拉取成功后直接交给 `audioService.playPlaylist`，并设置播放源标识；
   - 期间提供轻量级 loading 反馈。
2. **改造 `_playAll(shuffle: false)`（播放全部）**：
   - 若 `!hasMore`，直接播放当前的 `widget.songs`；
   - 若 `hasMore == true`，弹出进度浮层，从当前已拉取的位置继续分批请求后续页面，直到全部获取完毕；
   - 获取完成后把全量曲目更新至列表并立即起播。

---

### 步骤 4：自动化测试与验证
1. 编写针对 `getRandomSongs` 在 Subsonic 与 Jellyfin 下的单元测试，验证请求参数组装与数据解析；
2. 编写针对分页全量合并与取消逻辑的测试；
3. 执行 `flutter analyze lib` 确保代码无 warning/error；
4. 执行 `./scripts/run_tests.sh` 或相关单元测试确保全量行为正确。

