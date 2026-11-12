import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';

/// 设置分组的归口。
///
/// 首页竖屏是「一张卡 = 一个分组」，横屏侧栏是「按同一顺序平铺」，
/// 两者都从 [SettingsSection] 的元数据派生 —— 新增设置分组只改
/// [SettingsSection]，不必再同步第二份清单。
enum SettingsSectionGroup { core, library, tools, about }

enum SettingsSection {
  home,
  general,
  audio,
  proxy,
  scanning,
  tags,
  transcode,
  lyrics,
  acoustid,
  lastFm,
  storage,
  shortcuts,
  windows,
  about;

  String title(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (this) {
      SettingsSection.home => l10n.settings,
      SettingsSection.general => l10n.generalSectionTitle,
      SettingsSection.audio => l10n.audioSettings,
      SettingsSection.proxy => l10n.proxySettingsTitle,
      SettingsSection.scanning => l10n.scanSectionTitle,
      SettingsSection.tags => l10n.tags,
      SettingsSection.transcode => l10n.transcodeSectionTitle,
      SettingsSection.lyrics => l10n.lyricsSectionTitle,
      SettingsSection.acoustid => l10n.acoustidSectionTitle,
      SettingsSection.lastFm => l10n.lastFmSectionTitle,
      SettingsSection.storage => l10n.storageAndCache,
      SettingsSection.shortcuts => l10n.shortcutSettingsTitle,
      SettingsSection.windows => l10n.windowsSettingsTitle,
      SettingsSection.about => l10n.about,
    };
  }

  IconData get icon {
    return switch (this) {
      SettingsSection.home => Icons.settings,
      SettingsSection.general => Icons.tune_rounded,
      SettingsSection.audio => Icons.graphic_eq_rounded,
      SettingsSection.proxy => Icons.vpn_lock_rounded,
      SettingsSection.scanning => Icons.search_rounded,
      SettingsSection.tags => Icons.label_outline_rounded,
      SettingsSection.transcode => Icons.swap_horiz_rounded,
      SettingsSection.lyrics => Icons.auto_awesome_rounded,
      SettingsSection.acoustid => Icons.radar_rounded,
      SettingsSection.lastFm => Icons.music_note_rounded,
      SettingsSection.storage => Icons.storage_rounded,
      SettingsSection.shortcuts => Icons.keyboard_rounded,
      SettingsSection.windows => Icons.open_in_new_rounded,
      SettingsSection.about => Icons.info_outline_rounded,
    };
  }

  /// 归属的首页卡片分组。[SettingsSection.home] 只是「首页」这个伪条目，
  /// 不属于任何分组。
  ///
  /// 故意写全所有枚举值（不用 `_` 兜底）：新增分组若忘了归口，这里会编译报错。
  SettingsSectionGroup? get group {
    return switch (this) {
      SettingsSection.home => null,
      SettingsSection.general ||
      SettingsSection.audio ||
      SettingsSection.proxy =>
        SettingsSectionGroup.core,
      SettingsSection.scanning ||
      SettingsSection.tags ||
      SettingsSection.transcode ||
      SettingsSection.lyrics ||
      SettingsSection.acoustid ||
      SettingsSection.lastFm => SettingsSectionGroup.library,
      SettingsSection.storage ||
      SettingsSection.shortcuts ||
      SettingsSection.windows => SettingsSectionGroup.tools,
      SettingsSection.about => SettingsSectionGroup.about,
    };
  }

  /// 当前平台是否提供该设置页。平台判定只写在这里。
  bool get isAvailable {
    if (this == SettingsSection.home) return false;
    if (this == SettingsSection.windows) return Platform.isWindows;
    if (this == SettingsSection.proxy) {
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    }
    return true;
  }

  /// 侧栏与首页卡片共用的唯一可见清单，顺序即枚举声明顺序。
  static List<SettingsSection> get visibleSections => [
    for (final section in values)
      if (section.isAvailable) section,
  ];

  /// 首页竖屏卡片：按 [SettingsSectionGroup] 的声明顺序分桶，空桶不输出。
  static Map<SettingsSectionGroup, List<SettingsSection>> get homeGroups {
    final buckets = <SettingsSectionGroup, List<SettingsSection>>{
      for (final group in SettingsSectionGroup.values) group: <SettingsSection>[],
    };
    for (final section in visibleSections) {
      buckets[section.group]!.add(section);
    }
    return {
      for (final entry in buckets.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
  }
}
