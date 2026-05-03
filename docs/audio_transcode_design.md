# 音频转码功能设计

## 目标

在现有 `vibe_flow` 中新增一个“音频转码”能力，满足以下场景：

- 对单首歌曲执行转码
- 对多首歌曲批量转码
- 允许用户选择输出格式、码率、采样率、声道等参数
- 在桌面端兼容外部 `ffmpeg`，在移动端/Apple 平台走 `audio_converter`
- 转码完成后可选择：
  - 打开输出目录
  - 导入到媒体库
  - 替换原文件前手动确认

这次建议先做成“任务型 feature”，不要把它揉进播放核心 `AudioService`。

---

## 为什么不要挂进 `AudioService`

当前项目里：

- `AudioService` 负责播放状态与队列
- `ScannerService` 负责媒体库扫描与同步
- `SettingsService` 负责持久化用户偏好

转码本质上是“离线文件任务”，不是播放生命周期的一部分，所以更适合单独做一层：

- UI 层发起任务
- `TranscodeService` 调用 `audio_converter`
- 任务完成后通知 `ScannerService` 做增量刷新

这样职责更清晰，也不会把播放状态污染成“播放器兼转码器”。

---

## 推荐目录结构

项目当前并不是严格 feature-first，但已经具备 `player/ + pages/ + dialogs/ + widgets/` 的稳定分工。

为了和现有代码风格一致，建议采用“局部 feature 聚合”：

```text
lib/
├── transcode/
│   ├── transcode_models.dart
│   ├── transcode_preset.dart
│   ├── transcode_task.dart
│   ├── transcode_state.dart
│   ├── transcode_service.dart
│   ├── transcode_coordinator.dart
│   ├── transcode_output_planner.dart
│   ├── transcode_history_store.dart
│   └── transcode_riverpod.dart
├── dialogs/
│   ├── transcode_dialog.dart
│   └── batch_transcode_dialog.dart
├── pages/
│   └── transcode_tasks_page.dart
└── widgets/
    ├── transcode_task_tile.dart
    ├── transcode_queue_banner.dart
    └── transcode_preset_chip.dart
```

如果你后面准备把“标签编辑、歌词生成、转码、格式分析”都做成独立工具，再考虑统一迁到：

```text
lib/features/transcode/{data,ui}
```

当前阶段没必要为这一个功能大迁移。

---

## 分层建议

### 1. `transcode_models.dart`

放纯模型与枚举：

- `TranscodeTargetScope`
  - `single`
  - `multiple`
- `TranscodeConflictPolicy`
  - `skip`
  - `overwrite`
  - `rename`
- `TranscodeImportPolicy`
  - `doNothing`
  - `scanOutputFolder`
  - `appendToCurrentPlaylist`
- `TranscodeJobStatus`
  - `queued`
  - `running`
  - `success`
  - `failed`
  - `cancelled`

### 2. `transcode_preset.dart`

抽象用户可复用的预设：

- `name`
- `qualityTier`
- `outputFormat`
- `bitRate`
- `bitRateMode`
- `sampleRate`
- `channels`

这里建议不要让预设名直接跟具体格式耦合，而是先建立“质量档位”：

- `low`
- `medium`
- `high`
- `extreme`

默认码率映射固定为：

- `low` -> `128kbps`
- `medium` -> `192kbps`
- `high` -> `256kbps`
- `extreme` -> `320kbps`

同时根据输出格式和平台自动推导默认码率控制模式：

- `opus` 默认 `vbr`
- `mp3` 默认 `cbr`
- `m4a` 在 `macOS` / `iOS` 默认 `vbr`
- 其他情况默认 `cbr`

也就是说，`TranscodePreset` 更适合被实现成：

- 一个“用户可见的质量档位”
- 一套“按格式/平台派生出的底层参数”

这样 UI 和执行逻辑都更稳定。

建议加一个派生器，例如：

- `TranscodePresetResolver.resolve(format, qualityTier, platform)`

由它统一产出：

- `bitRate`
- `bitRateMode`
- 默认采样率
- 默认声道

避免这些规则散落在 dialog 和 service 里。

### 3. `transcode_task.dart`

表示一个真正执行中的任务，建议字段：

- `id`
- `inputPath`
- `outputPath`
- `sourceSong`
- `request`
- `status`
- `createdAt`
- `startedAt`
- `finishedAt`
- `result`
- `errorMessage`

### 4. `transcode_state.dart`

给 Riverpod/UI 用的聚合状态：

- `capabilities`
- `isLoadingCapabilities`
- `activeTasks`
- `recentTasks`
- `queuedCount`
- `runningCount`
- `failedCount`

### 5. `transcode_service.dart`

只负责“调用插件执行单次转码”，不要掺 UI 和批量调度。

职责：

- 初始化 `AudioConverter`
- 读取 `getCapabilities()`
- 构建 `ConvertRequest`
- 执行 `convertFile()`
- 统一错误映射

不要负责：

- 队列并发
- 页面弹窗
- 扫描媒体库

### 6. `transcode_output_planner.dart`

专门负责输出路径规则，避免路径逻辑散落在 UI。

职责：

- 计算输出目录
- 生成默认输出文件名
- 处理重名策略
- 生成“源文件同目录 / 自定义目录 / 转码缓存目录”

### 7. `transcode_coordinator.dart`

这是核心编排层，建议作为 UI 和 Service 之间的总入口。

职责：

- 创建单个/批量任务
- 控制串行执行
- 更新任务状态
- 成功后触发扫描刷新
- 写入最近任务历史

建议第一版只做“串行 1 个并发”，原因：

- 简化状态管理
- 减少多任务同时占用 CPU/IO
- 更符合桌面音乐管理工具的稳定性预期

### 8. `transcode_history_store.dart`

如果你想保留最近转码记录，可以单独做一层持久化：

- 先用 `SharedPreferences` 存最近 20 条
- 后续如果要做可搜索历史，再迁数据库

### 9. `transcode_riverpod.dart`

集中放 provider：

- `transcodeServiceProvider`
- `transcodeCoordinatorProvider`
- `transcodeStateProvider`
- `transcodeCapabilitiesProvider`

风格上和现有 [audio_riverpod.dart](/Users/axel10/projects/player_project/vibe_flow/lib/player/audio_riverpod.dart) 保持一致。

---

## 与现有模块的关系

### `SettingsService`

适合持久化“默认偏好”，不适合存任务态。

建议新增：

- 默认输出格式
- 默认质量档位
- 默认输出目录策略
- 桌面端自定义 `ffmpegPath`
- 转码后是否自动扫描输出目录

如果用户打开过高级选项并修改了底层参数，再额外保存：

- 最近一次自定义码率
- 最近一次自定义码率模式
- 最近一次自定义采样率
- 最近一次自定义声道

但普通默认值仍建议以“格式 + 质量档位”为主，而不是直接以裸参数为主。

### `ScannerService`

转码完成后只调用它做“输出文件纳入媒体库”的处理。

建议协调方式：

- 若输出在已扫描目录中：
  - 调用增量刷新/局部刷新
- 若输出在未扫描目录中：
  - 只提示“已生成文件，可手动导入”
  - 或提供“加入扫描根目录”入口

不要在转码 service 内部直接修改 `metadataMap`。

### `PlaylistService`

可选增强：

- 批量转码后，把输出文件追加到某个播放列表

第一版可以不做。

---

## UI 入口设计

建议做“双入口 + 一个任务中心”。

### 入口一：歌曲操作菜单

最自然，优先级最高。

适合接在 [song_context_menu_utils.dart](/Users/axel10/projects/player_project/vibe_flow/lib/utils/song_context_menu_utils.dart)：

- `转码...`

适用页面：

- 文件夹页
- 专辑页
- 艺术家页
- 队列页
- 排行列表

单首时直接打开 `TranscodeDialog`。

多选时打开 `BatchTranscodeDialog`。

### 入口二：设置页中的“转码”分组

放全局配置，不放任务执行主入口。

适合放在 [settings_page.dart](/Users/axel10/projects/player_project/vibe_flow/lib/pages/settings_page.dart)：

- 默认输出格式
- 默认码率
- 默认输出目录
- `ffmpeg` 路径
- 平台能力说明
- “打开任务中心”

### 入口三：任务中心页

新增 [transcode_tasks_page.dart](/Users/axel10/projects/player_project/vibe_flow/lib/pages/transcode_tasks_page.dart)。

这个页不建议做成主导航一级 Tab，原因：

- 使用频率低于播放/媒体库/文件夹
- 更像工具面板，不像核心浏览页

更适合：

- 从设置页进入
- 从 Snackbar/横幅点击进入
- 从转码弹窗完成后“查看任务”

---

## 弹窗与页面分工

### `TranscodeDialog`

负责“配置并提交任务”。

适用于：

- 单首转码
- 少量多首共用一套参数

推荐布局：

1. 顶部信息卡
2. 输出格式区
3. 质量预设区
4. 高级选项折叠区
5. 输出位置区
6. 冲突处理区
7. 提交按钮区

建议字段：

- 输入文件名/数量
- 输出格式下拉
- 四挡质量预设 Chips
- `高级选项` 开关或折叠面板
- 高级区中的码率输入
- 高级区中的 `CBR/VBR` 切换
- 高级区中的采样率下拉
- 高级区中的声道下拉
- `重置为当前预设` 按钮
- 输出目录选择
- 同名文件策略
- “完成后扫描到媒体库”开关

这里最关键的交互原则是：

- 用户平时只看到：
  - 输出格式
  - 四挡质量预设
- 只有打开高级选项后，才看到：
  - 比特率
  - 码率控制模式
  - 采样率
  - 声道

这样能把“常用操作”压缩到最少步骤。

### `BatchTranscodeDialog`

如果你希望批量逻辑更清楚，可以单独做一个批量版：

- 展示前 3 首文件名 + `+N`
- 显示预计输出目录
- 显示潜在冲突数量
- 显示总任务数

如果想先节省实现量，也可以只保留一个 `TranscodeDialog`，根据 `songs.length` 自动切换文案。

### `TranscodeTasksPage`

负责查看执行结果，不负责编辑参数。

推荐分区：

- `正在进行`
- `等待中`
- `最近完成`
- `失败`

每个任务卡片显示：

- 源文件名
- 目标格式
- 输出路径
- 状态
- 错误摘要
- 操作按钮
  - 打开输出目录
  - 重试
  - 清除记录

---

## UI 交互细节建议

### 1. 单首操作优先 bottom sheet

你现有标签编辑使用的是底部大面板，转码也可以复用这个交互风格，保持一致。

参考 [song_tag_edit_dialog.dart](/Users/axel10/projects/player_project/vibe_flow/lib/dialogs/song_tag_edit_dialog.dart)。

建议：

- 单首转码使用 `showModalBottomSheet`
- 批量转码也继续用同风格

### 2. 提交后立即关闭配置面板

提交转码任务后，不要让用户一直卡在配置页等完成。

更顺的流程是：

- 点击“开始转码”
- 关闭弹窗
- 弹出 Snackbar: `已加入转码队列`
- 提供 `查看任务` 操作

### 3. 进行中状态用全局轻横幅

可以新增一个全局小组件，例如：

- `正在转码 2 项`
- `1 项失败`

挂在主布局底部或顶部，点击进入任务中心。

这类轻提示比单独常驻页面更符合这个 feature 的使用方式。

### 4. 不建议第一版暴露太多高级 ffmpeg 参数

第一版默认 UI 只给：

- 格式
- 四挡质量预设
- 输出目录

高级选项折叠后才给：

- 码率
- `CBR/VBR`
- 采样率
- 声道

并提供一个很明确的按钮：

- `重置为当前预设`

点击后用“当前选中的格式 + 当前选中的质量档位 + 当前平台规则”重新填充高级参数。

`extraOptions` 先留给代码层，不直接开放给用户，不然 UI 会变得很重。

### 5. 预设与高级参数的联动规则

建议在状态层明确三种来源：

- `presetDerived`
- `userCustomized`
- `resetFromPreset`

推荐交互规则：

1. 用户切换输出格式
   - 若高级参数未被手动改过，自动刷新到底层默认值
   - 若已经手动改过，弹性做法是仍自动刷新，但给出轻提示“已按新格式重置高级参数”
2. 用户切换质量档位
   - 自动更新比特率
   - 自动按规则更新默认码率模式
3. 用户手改高级参数
   - 标记当前配置为 `customized`
4. 用户点击 `重置为当前预设`
   - 用当前 `format + qualityTier + platform` 重新生成全部高级值

这个规则最好封装成一个单独对象，例如：

- `TranscodeConfigController`
- 或 `TranscodeDraft`

让 UI 只负责展示，不自己算联动。

---

## 推荐状态流

```text
UI(dialog/page)
  -> transcodeCoordinatorProvider
  -> TranscodeCoordinator.enqueue(...)
  -> TranscodeService.convert(...)
  -> audio_converter.convertFile(...)
  -> ConvertResult
  -> TranscodeCoordinator 更新任务状态
  -> 可选触发 ScannerService 刷新
  -> Riverpod state 通知 UI
```

关键点：

- UI 不直接 new `AudioConverter`
- UI 不自己拼 `ConvertRequest`
- UI 不直接调用 `ScannerService`

---

## Provider 组织建议

可以在 [audio_riverpod.dart](/Users/axel10/projects/player_project/vibe_flow/lib/player/audio_riverpod.dart) 之外新增独立文件：

```dart
final transcodeServiceProvider = Provider<TranscodeService>((ref) {
  return TranscodeService();
});

final transcodeCoordinatorProvider =
    NotifierProvider<TranscodeCoordinator, TranscodeState>(
      TranscodeCoordinator.new,
    );
```

如果 `TranscodeCoordinator` 需要扫描服务：

```dart
final scanner = ref.read(scannerServiceProvider);
```

这样依赖关系比较自然。

---

## 第一版实现优先级

### P0

- 接入 `audio_converter` 依赖
- `TranscodeService`
- `TranscodeCoordinator`
- 单首转码弹窗
- 设置页默认参数
- 转码完成后打开输出目录

### P1

- 批量转码
- 任务中心页
- 最近任务记录
- 自动扫描输出目录

### P2

- 失败重试
- 预设管理
- 替换原文件流程
- 输出文件自动加入播放列表

---

## 实现注意点

### 1. Windows/Linux 的 `ffmpeg` 依赖提示

`audio_converter` 当前桌面端可能依赖外部 `ffmpeg`。

所以 UI 上要明确：

- 当前引擎
- 是否需要外部二进制
- 当前 `ffmpegPath`
- 找不到时如何修复

### 2. 不要默认覆盖源文件

第一版强烈建议：

- 默认输出到新文件
- 默认策略为 `rename` 或 `skip`

因为音乐库文件很敏感，覆盖风险高。

### 3. 扫描刷新要延后

批量任务不要每成功一首就全库刷新。

建议：

- 批次结束后再触发一次目标目录增量同步
- 或由 `TranscodeCoordinator` 节流聚合

### 4. 失败信息要保留原始日志

`ConvertResult.rawLog` 很有价值。

任务详情里建议支持：

- 查看错误详情
- 复制日志

---

## 最推荐的落地方案

如果按“最小改动、最快上线”来做，我建议你走这个版本：

1. 在 `lib/transcode/` 新增 service、state、riverpod
2. 在 `lib/dialogs/` 新增一个 `transcode_dialog.dart`
3. 在歌曲右键菜单里新增 `转码...`
4. 在设置页新增“转码默认设置”分组
5. 在主布局加一个轻量 `transcode_queue_banner`
6. 后续再补 `transcode_tasks_page.dart`

这个路径最符合你当前项目形态，也最不容易牵动现有播放和扫描代码。

其中 P0 的交互建议直接定成：

- 默认只显示 `格式 + 低/中/高/最高`
- `低=128kbps`
- `中=192kbps`
- `高=256kbps`
- `最高=320kbps`
- `opus -> vbr`
- `mp3 -> cbr`
- `m4a(macOS/iOS) -> vbr`
- `其他 -> cbr`
- 高级选项默认折叠
- 高级区支持 `重置为当前预设`

---

## 建议落点文件

- Provider 风格参考：
  [audio_riverpod.dart](/Users/axel10/projects/player_project/vibe_flow/lib/player/audio_riverpod.dart)
- 设置页入口参考：
  [settings_page.dart](/Users/axel10/projects/player_project/vibe_flow/lib/pages/settings_page.dart)
- 单首大面板交互参考：
  [song_tag_edit_dialog.dart](/Users/axel10/projects/player_project/vibe_flow/lib/dialogs/song_tag_edit_dialog.dart)
- 歌曲右键菜单入口参考：
  [song_context_menu_utils.dart](/Users/axel10/projects/player_project/vibe_flow/lib/utils/song_context_menu_utils.dart)
