# 其它约定与环境（MEMORY.md 的尾巴）

> 被主文件挤出来的低优先条目。动手改对应模块前读一遍。

## 其它约定

- 新增实体右键菜单三件套：`lib/widgets/<entity>_context_menu.dart`（`show<Entity>ContextMenu` + `show<Entity>BottomSheet` + 共用 `_handle...`）；条目根挂 `GestureDetector(behavior: opaque, onSecondaryTapDown, onLongPress)`；l10n 加 `view<Entity>Details`/`copy<Entity>Name`。
- 流派/年份封面统一 `GenreSummary.representativeArtworkPath/ThumbnailPath` + `SongThumbnail`（列表 44、详情 96/116）。**两套「代表曲」规则不可混用**（集合摘要取 DB 顺序第一首带封面的歌 vs `buildAlbumSections` 的首组），故列表页/详情页头都不显示集合级封面。
- 远程库工具栏：「只看收藏」永远是**独立开关**（`RemoteStarFilterButton`，行内顺序 搜索 → 心形 → 排序下拉），**禁写进排序下拉**，也**禁做成 `getAlbumList(type:'starred')` 服务端请求**（顶掉排序、闪遮罩）。三个 Tab 统一：收藏集单独取一次存在内存 Set，`_getFiltered*()` 本地过滤；切开关只 setState，只有 Set 为空才补一次请求；专辑可用列表项的 `starred`/`isFavorite` 预填充。
- 「定位当前播放」唯一决策点 `SongLocatorHelper.locateCurrentPlayingSong`：Subsonic/Jellyfin 只走 `_openAlbumForRemoteSong`（`getSong` → `albumId`/`parent` 非空 → 开专辑详情页 + 高亮），**禁回落本地扫描树**、**禁再用 `songNotInScannedFolders` 描述远程失败**（统一 `remoteAlbumUnavailable`）；albumId 必须 `isNotEmpty`（Jellyfin 恒空串）；服务器列表要 `await` 而非读 `asData`。WebDAV/SMB 另有自己的一套。
- **禁对整仓跑 `dart format`**：新格式化器会重排 `remote_library_page.dart` 等整份文件（数百行噪声）。改完只跑 `flutter analyze lib`。

## 环境

- 搜索用 `rg`/`fd`：PATH 里的 grep/find 是 toybox shim，会漏匹配。
- `flutter` 不在 PATH：`export PATH="$HOME/flutter/bin:$PATH"`。
- 跑 `flutter test` 前必须 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy GLOBAL_AGENT_HTTP_PROXY` 并 `export NO_PROXY=127.0.0.1,localhost`，否则全部加载失败。
- 无 `groovy`/`pwsh`；验证 Groovy 片段用 Gradle 自带 jar。仓库源文件是 **CRLF**（`lib/l10n/app_*.arb` 等），脚本批量改必须显式保留行尾。
