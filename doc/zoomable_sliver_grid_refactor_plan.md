# `zoomable_sliver_grid` 接口内聚与性能优化工作计划

> 本文档规划 `zoomable_sliver_grid` 子模块及其在 Vynody 主项目中的演进路线。遵循“**架构设计统一规划、工程实施严格分阶段**”的原则，依次完成：**阶段 0（轻量止血）→ 阶段 1（接口内聚与数据分层）→ 阶段 2（渲染下沉与零重建优化）**。

---

## 一、现状概述

### 1.1 当前架构形态
`zoomable_sliver_grid` 作为独立子模块（`./zoomable_sliver_grid`）接入主项目，服务于本地与远程媒体库的目录、歌曲、专辑、艺术家、歌单、搜索及队列等 20 余个页面。其核心能力包括：
- **7 档位连续过渡**：4 档单列列表（极简/紧凑/标准/大图）与 3 档多列网格（小/中/大网格）之间的双指捏合跟手与 260ms 动画切换。
- **多段协同滚动补偿与焦点锚定**：单页挂载多个可缩放网格段（如“子目录 + 歌曲”）时，基于页面坐标系与焦点高度统一换算滚动位置，抑制反复换档时的视口漂移。
- **单侧可见条目冻结机制（`FolderZoomItemPinning`）**：过渡起始时刻冻结起止可见性集合，双侧共同可见条目执行加权位移，单侧可见条目锁在对应屏幕坐标原地淡入淡出。
- **拖拽重排与跨组件拖放**：与 `super_drag_and_drop` 结合，支持单选/多选拖拽排序及向播放队列投递。

### 1.2 近期优化成果
最近数次提交（主仓库 `5e9f831b`、`7657507c`、`4a1ab3c1` 与子模块 `e4cd321`、`1e5f517`、`8920551`）已解决若干显著瓶颈：
- 移除横幅高斯模糊与卡片嵌套圆角裁剪，减少 GPU 离屏绘制。
- 稳态锁定整数字号、捏合期间冻结或台阶化字号，缓解 `CreateGlyphAtlas` 尖峰。
- 捏合与吸附期间在手势层屏蔽无障碍语义树更新，消除同步构建语义节点的耗时。
- 为 `FolderZoomSliverBuilder` 引入静态 `child` 参数，隔离外层 `CustomScrollView` 与 `FolderHeaderBanner` 的逐帧重建。
- 为 `ZoomItemScaffold` 显式透传 `index` 并移除外层 `LayoutBuilder`，改为 `CustomMultiChildLayout` 定位槽位。

### 1.3 现有测试资产
子模块 `zoomable_sliver_grid/test/` 已沉淀 28 个专项测试文件，覆盖焦点锚定、多段协作、段间间距运动、单侧淡入淡出、重建隔离、后台恢复与拖拽重排等核心不变量，可作为后续各阶段重构的安全网。

---

## 二、核心痛点

### 2.1 计算量与渲染管线痛点
1. **动画期每帧全量重建业务条目树**  
   `_FolderZoomSliverBuilderState` 每帧通过 `setState` 构造新的 `FolderZoomLayoutMetrics` 并经由 `FolderZoomMetricsScope` 下发，触发 `FolderZoomSectionHost` 重建整个 `SliverGrid`、`SliverAnimatedZoomGridDelegate` 与 `SliverChildBuilderDelegate`。视口及缓存区内所有条目（含本应静态原地淡入淡出的单侧可见条目）均需每帧完整执行 Widget `build`（含 Riverpod 订阅检查、文本拼接、样式构建与子树 diff）。
2. **文字缩放与裁剪仍依赖 CPU 文本重排与字形图集重建**  
   目前通过每帧修改 `TextStyle.fontSize` 与文本容器约束宽度驱动变化。为避免低端设备上 `CreateGlyphAtlas` 卡顿，不得不引入 2pt 台阶量化/冻结字号的妥协；而参考 Poweramp 等原生播放器的实现，文字缩放应通过 GPU 矩阵缩放实现，宽度变化应通过绘制层裁剪窗口平滑过渡，动画期间零文本重排、零字形图集重建。
3. **主路径残留内层 `LayoutBuilder` 二次重建**  
   `ZoomItemScaffold` 虽已移除最外层 `LayoutBuilder`，但只要传入 `textColumnBuilder`（`SongZoomItem` 主路径）或 `infoText`，文本区域内部仍嵌套了一层 `LayoutBuilder`，导致缩放期间在 `flushLayout` 阶段依然触发二次 Widget 重建。
4. **多处确定性高频计算浪费**
   - `folderZoomGeometryProbe` 默认关闭，但 `_probeLayoutFrame` 与 `computeMaxScrollOffset` 在调用 `zoomGeomProbe` 之前已无条件执行 `scrollPixelsReader?.call()`、`zd(...)`、`layers.map(...).join(',')` 拼接签名字符串并分配闭包。
   - `_SliverAnimatedZoomGridLayout.getGeometryForChildIndex` 对每个可见条目重复计算同帧恒定的层几何参数（`contentWidth`、`originOffsetX`、`cardWidth`、`mainStride`、`layerViewportTop`）。
   - `ZoomItemMorphingInfoColumn._buildListMorph` 每次 `build` 均无条件新建 `TextPainter` 并同步执行 `layout()`（且未调用 `dispose()`）。

### 2.2 接口内聚与封装边界痛点
1. **稳态规格与逐帧动画状态耦合在同一数据结构中**  
   `FolderZoomLayoutMetrics` 同时承载“目标档位/稳态卡片宽/屏幕方向”和“每帧变化的 `gridMorph`/`transitionProgress`/字号”，导致业务组件哪怕只需稳态信息，也被迫订阅逐帧变化。
2. **核心单文件过度膨胀**  
   `zoomable_sliver_grid/lib/src/zoom_layout_utils.dart` 单文件超过 4100 行，混合了档位策略、多段视口追踪、冻结表、动画状态机、作用域组件、自定义 `SliverGridDelegate`/`SliverGridLayout` 及探针日志，阅读与局部重构阻力大。
3. **主项目与插件实现分叉**
   - 主项目 `lib/widgets/folder_zoom_gesture_layer.dart` 与插件 `zoomable_sliver_grid/lib/src/zoom_gesture_layer.dart` 维护了两套高度重合的滚轮簇节流与双指捏合逻辑，导致主项目的 `ExcludeSemantics` 性能优化未能同步回插件。
   - 主项目 `lib/widgets/folder_layout_utils.dart` 不得不额外编写 `zoomItemThumbnailSizeForScale` 复刻插件内部稳态计算逻辑。
4. **隐式调用契约偏多**  
   调用方需手工保持 `SliverAnimatedZoomGridDelegate.section` 与 `ZoomItemScaffold.section` 一致、显式传 `index` 才能跳过 `LayoutBuilder`、并保证外层 `SliverPadding` 水平内边距与 `folderContentHorizontalPadding` 互补。

---

## 三、理想状态

### 3.1 接口与封装目标
- **职责清晰、模块内聚**：核心实现按“稳态策略 / 视口追踪与冻结 / Sliver 布局 / 动画宿主 / 手势层”拆分为独立文件，主项目仅保留极薄的业务状态（Riverpod）绑定壳。
- **稳态与动态数据显式分离**：
  - 稳态布局规格（`ZoomSteadyMetrics` / `ZoomPolicy`）仅在目标档位、容器宽度或屏幕方向变化时刷新。
  - 过渡动画进度通过 `Listenable` / 内部只读通道传递，业务条目无需直接消费逐帧插值标量。
- **一体化高层入口**：提供 `ZoomableSliverGrid` 等组合组件，内部自动托管水平边距互补、`section` 配对与 `index` 透传，消除调用方的隐式契约负担。

### 3.2 性能与视觉目标
- **单侧可见条目（淡入/淡出）**：过渡期间 **0 次业务 Widget 重建**，完全由合成层 `FadeTransition` / `ScaleTransition` 驱动。
- **共同可见条目（位移动画）**：过渡期间尽量避免整屏业务条目重建，位置、尺寸、文字缩放与裁剪下沉至 `Listenable` + `RenderObject` / GPU 变换层。
- **平滑度与流畅度兼得**：取消捏合期 2pt 字号台阶妥协，通过 GPU 矩阵缩放实现 100% 连续平滑的文字大小变化，同时保证过渡期间 **0 次 `CreateGlyphAtlas` 重建** 与 **0 次内层 `LayoutBuilder` 二次重建**。

---

## 四、分阶段改造方法

### 阶段 0：零风险性能止血（不改公开接口）

**目标**：在不触碰任何外部 API 签名的前提下，快速清除高频确定性计算浪费，并补齐插件与主项目的语义屏蔽缺口。

**具体改动清单**：
1. **探针短路优化**
   - 文件：`zoomable_sliver_grid/lib/src/zoom_layout_utils.dart`
   - 做法：在 `_probeLayoutFrame`、`_probeNegativeChild`、`_probePinnedClamp` 及 `computeMaxScrollOffset` 构造 `signature` 之前统一增加 `if (!folderZoomGeometryProbe) return;`。
2. **单帧层几何预计算**
   - 文件：`zoomable_sliver_grid/lib/src/zoom_layout_utils.dart`
   - 做法：新增私有不可变结构 `_ResolvedLayerFrame`（缓存 `contentWidth`、`originOffsetX`、`cardWidth`、`cardHeight`、`mainStride`、`crossStride`、`viewportTop`）。在 `SliverAnimatedZoomGridDelegate.getLayout` 构造 `_SliverAnimatedZoomGridLayout` 时按 `layers` 一次性生成该列表，`getGeometryForChildIndex`、`getMinChildIndexForScrollOffset`、`getMaxChildIndexForScrollOffset` 均直接读取预计算值。
3. **`TextPainter` 测量缓存与释放**
   - 文件：`zoomable_sliver_grid/lib/src/zoom_item_scaffold.dart`
   - 做法：将 `ZoomItemMorphingInfoColumn` 改造为 `StatefulWidget` 或引入轻量级测量缓存，仅当 `info` 文本、`infoStyle`（字号/字重/字体）或 `TextDirection` 变化时重新测量并在 `dispose` 时释放 `TextPainter`；当 `compactMorph <= 0.001`（纯标准/大列表）时直接跳过宽度测量。
4. **语义屏蔽能力下沉至插件手势层**
   - 文件：`zoomable_sliver_grid/lib/src/zoom_gesture_layer.dart`
   - 做法：将主项目 `FolderZoomGestureLayer` 中的 `_zoomSemanticsBlocked`（`ValueNotifier<bool>`）与 `ExcludeSemantics` 机制同步至插件 `ZoomGestureLayer`。

**验收标准**：
- `zoomable_sliver_grid` 全部 28 个测试及主项目 `flutter analyze lib`、`flutter test` 全部通过。
- 新增单测验证：`folderZoomGeometryProbe == false` 时布局不触发探针格式化；`ZoomGestureLayer` 捏合激活期间子树语义正确屏蔽、结束后恢复。

---

### 阶段 1：接口内聚与模块拆分（视觉与行为 100% 等价）

**目标**：拆解超长单文件，消除主项目与插件之间的重复实现，收拢隐式契约，并在接口层完成“稳态规格”与“动态过渡通道”的解耦，为阶段 2 打好结构基础。

**具体改动清单**：
1. **拆分 `zoom_layout_utils.dart` 为模块化结构**（通过 `zoomable_sliver_grid.dart` 保持对外兼容导出）：
   - `lib/src/zoom_policy.dart`：档位枚举与常量、`FolderZoomPolicy`、纯函数字号与尺寸计算，并新增 `ZoomPolicy.thumbnailSizeForScale(...)` 稳态纯函数。
   - `lib/src/zoom_viewport_tracker.dart`：`_ZoomSectionState`、`FolderZoomViewportTracker`、`FolderZoomItemPinning` 与 `_PinSegment`。
   - `lib/src/zoom_sliver_layout.dart`：`SliverAnimatedZoomGridDelegate`、`_SliverAnimatedZoomGridLayout` 与预计算层几何。
   - `lib/src/zoom_sliver_builder.dart`：`FolderZoomLayoutMetrics`、`FolderZoomMetricsScope`、`FolderZoomSectionHost`、`FolderZoomSliverBuilder`。
2. **收拢主项目重复代码**
   - 主项目 `lib/widgets/folder_zoom_gesture_layer.dart`：删除重复的手势识别器、滚轮簇节流、双指欧氏距离追踪与 `ExcludeSemantics` 样板，改为直接包裹插件的 `ZoomGestureLayer`，仅负责将 Riverpod `settings` / `zoomGesturesEnabled` / 混合视图锁定状态映射为参数。
   - 主项目 `lib/widgets/folder_layout_utils.dart`：`zoomItemThumbnailSizeForScale` 直接委托插件的 `ZoomPolicy.thumbnailSizeForScale`，消除双份公式漂移风险。
3. **收拢隐式契约，引入组合入口 `ZoomableSliverGrid`**
   - 文件：新增 `zoomable_sliver_grid/lib/src/zoom_sliver_grid.dart`
   - 做法：封装 `FolderZoomSectionHost` + 水平互补 `SliverPadding` + `SliverGrid(gridDelegate: SliverAnimatedZoomGridDelegate(...))`，并通过轻量 `InheritedWidget` 或 builder 参数自动向每个条目注入 `section` 与 `index`。逐步迁移主项目 `FolderSubfoldersSliver`、`FolderSongsSliver` 等核心 Sliver。
4. **数据分层准备（为阶段 2 铺路）**
   - 在 `FolderZoomSliverBuilder` 内部抽出可监听的动画状态源 `ZoomTransitionListenable`（继承 `Listenable`，暴露当前帧的 `transitionProgress`、`gridMorph`、`compactMorph`、`geometryLayers` 及条目级过渡查询），与稳态配置 `ZoomSteadyMetrics` 解耦。此阶段先保持旧版 `FolderZoomMetricsScope` 兼容，待阶段 2 完成切换后再清理冗余字段。

**验收标准**：
- 所有现有 28 个插件测试 + 主项目全部单元测试通过，无任何视觉或交互行为变化。
- 主项目 `folder_zoom_gesture_layer.dart` 代码量缩减 70% 以上，手势逻辑单一事实来源完全收归插件。
- 新增 `ZoomableSliverGrid` 多段配对与 `ZoomPolicy.thumbnailSizeForScale` 一致性单测。

---

### 阶段 2：借鉴 Poweramp 的渲染下沉与零重建优化

**目标**：在不牺牲过渡视觉精致度的前提下，消除动画期间的逐帧业务 Widget 重建、字形图集重建与文本重排。

**具体改动清单**：
1. **文字缩放改走 GPU `Transform.scale`（零 `CreateGlyphAtlas`）**
   - 文件：`zoomable_sliver_grid/lib/src/zoom_item_scaffold.dart`、主项目 `lib/widgets/song_zoom_item.dart`
   - 做法：
     - 过渡期间文本组件锁定渲染字号为起止两档中较大一端的稳态整数字号（避免放大发虚），外层使用 `Transform.scale(scale: animatedFontSize / baseFontSize, alignment: Alignment.centerLeft)` 驱动平滑缩放。
     - 过渡结束后落定至目标档位稳态整数字号（`scale == 1.0`）。
     - 同步移除捏合期 `kFolderZoomPinchFontSizeQuantum = 2.0` 的台阶妥协，恢复 100% 连续平滑字号过渡。
2. **文字裁剪改走绘制层动态裁剪 & 彻底移除内层 `LayoutBuilder`**
   - 文件：`zoomable_sliver_grid/lib/src/zoom_item_scaffold.dart`、主项目 `lib/widgets/song_zoom_item.dart`
   - 做法：
     - 将 `ZoomItemScaffold` 内因 `textColumnBuilder` / `infoText` 残留的 `LayoutBuilder` 替换为纯 `RenderBox` / `CustomMultiChildLayout` 定位；过渡期锁定文本内部排版宽度（如起止宽度的稳态值），外层通过 `ClipRect` / `OverflowBox` 随动画进度平滑裁剪可见宽度，仅在动画落定稳态帧时重排为目标宽度的正式省略号。
     - 对 `_SongZoomContent` 拆出独立于瞬时宽高的稳态构建结构，避免每帧因约束微变触发二次 build。
3. **动画驱动下沉至 `Listenable` / `RenderObject`（消除业务条目每帧 rebuild）**
   - 文件：`zoomable_sliver_grid/lib/src/zoom_sliver_builder.dart`、`zoom_sliver_layout.dart`、`zoom_item_scaffold.dart`
   - 做法：
     - **单侧可见条目**：`ZoomItemScaffold` 外层常驻的 `Opacity` + `Transform.scale` 改为监听 `ZoomTransitionListenable` 的 `AnimatedBuilder` / 自定义 `RenderProxyBox`（在 `paint` 阶段直接应用透明度与缩放矩阵），过渡期间单侧可见条目的业务子树 **0 次 rebuild**。
     - **共享可见条目**：`FolderZoomSliverBuilder` 在动画期间不再每帧更新 `FolderZoomMetricsScope` 广播整棵子树，改为仅驱动 `ZoomTransitionListenable` 通知 `SliverGrid` 的布局代理与 `ZoomItemScaffold` 的 `MultiChildLayoutDelegate(relayout: listenable)`，让封面/文本/尾部槽位的位移与尺寸在纯布局/绘制阶段完成。
     - 业务条目（`SongZoomItem`、`FolderZoomItem`）仅在目标档位或容器宽度变化时重建一次，动画全程保持静默。

**验收标准**：
- 新增重建计数回归测试（扩展 `zoom_rebuild_isolation_test.dart`）：验证一次完整换档动画与持续捏合手势期间，单侧可见条目与共享可见条目的业务 Widget `build` 次数均为预期最小值（稳态切换触发，过渡帧为 0）。
- Android 真机（Profile 模式 + DevTools Timeline）实测对比改造前后：
  - UI 线程 `Build` 耗时大幅下降；
  - Raster 线程过渡期间 `CreateGlyphAtlas` 次数降为 0；
  - 帧时间 P95 / P99 与掉帧率显著改善，且慢速捏合时文字大小与裁剪视觉完全平滑。

---

## 五、风险控制与验证节奏

| 阶段 | 主要风险 | 缓解措施 | 验证方式 |
| :--- | :--- | :--- | :--- |
| 阶段 0 | 预计算缓存遗漏动态字段导致多段偏移错位 | 严格对照原字段构造 `_ResolvedLayerFrame`，保留原有几何公式不变 | 跑通全部 28 个插件测试 + 主项目测试 |
| 阶段 1 | 文件拆分与 `ZoomGestureLayer` 合并时漏掉主项目特有的混合视图/排序锁定逻辑 | 锁定判据保留在主项目薄壳层，通过 `enabled`/`reorderActive` 传入插件 | 全量单测 + 桌面端滚轮/触控板、移动端捏合/混合视图手测 |
| 阶段 2 | 文本 `Transform.scale` 缩放对齐基线偏差或 `ClipRect` 过渡收尾跳变 | 统一 `Alignment.centerLeft` 缩放原点，收尾帧与稳态排版做视觉逐帧比对 | 专项 Widget 回归测试 + Android 真机 Profile 抓帧对比 |

---

## 六、执行前确认项

计划落盘后，建议按以下顺序逐步实施，每完成一个阶段独立提交并验证：
1. **先执行阶段 0**（预计改动小、见效快、零接口破坏）。
2. 阶段 0 验证通过后，进入 **阶段 1**（先保证接口与模块边界干净）。
3. 阶段 1 稳定后，集中攻克 **阶段 2**（结合真机 Profile 数据逐项验证 Poweramp 式渲染下沉收益）。
