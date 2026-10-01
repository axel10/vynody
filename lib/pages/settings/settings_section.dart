import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';

enum SettingsSection {
  home,
  general,
  audio,
  scanning,
  tags,
  transcode,
  lyrics,
  acoustid,
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
      SettingsSection.scanning => l10n.scanSectionTitle,
      SettingsSection.tags => l10n.tags,
      SettingsSection.transcode => l10n.transcodeSectionTitle,
      SettingsSection.lyrics => l10n.lyricsSectionTitle,
      SettingsSection.acoustid => l10n.acoustidSectionTitle,
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
      SettingsSection.scanning => Icons.search_rounded,
      SettingsSection.tags => Icons.label_outline_rounded,
      SettingsSection.transcode => Icons.swap_horiz_rounded,
      SettingsSection.lyrics => Icons.auto_awesome_rounded,
      SettingsSection.acoustid => Icons.radar_rounded,
      SettingsSection.storage => Icons.storage_rounded,
      SettingsSection.shortcuts => Icons.keyboard_rounded,
      SettingsSection.windows => Icons.open_in_new_rounded,
      SettingsSection.about => Icons.info_outline_rounded,
    };
  }

  List<Color> get iconGradient {
    return switch (this) {
      SettingsSection.home => const [Color(0xFF64748B), Color(0xFF475569)],
      SettingsSection.general => const [Color(0xFF64748B), Color(0xFF475569)],
      SettingsSection.audio => const [Color(0xFF8B5CF6), Color(0xFF6366F1)],
      SettingsSection.scanning => const [Color(0xFF0EA5E9), Color(0xFF0284C7)],
      SettingsSection.tags => const [Color(0xFFF59E0B), Color(0xFFD97706)],
      SettingsSection.transcode => const [Color(0xFF10B981), Color(0xFF059669)],
      SettingsSection.lyrics => const [Color(0xFFEC4899), Color(0xFFD946EF)],
      SettingsSection.acoustid => const [Color(0xFF06B6D4), Color(0xFF0891B2)],
      SettingsSection.storage => const [Color(0xFFF97316), Color(0xFFEA580C)],
      SettingsSection.shortcuts => const [Color(0xFF6366F1), Color(0xFF4F46E5)],
      SettingsSection.windows => const [Color(0xFF0284C7), Color(0xFF2563EB)],
      SettingsSection.about => const [Color(0xFF6B7280), Color(0xFF4B5563)],
    };
  }

  static List<SettingsSection> get sidebarSections => [
        SettingsSection.general,
        SettingsSection.audio,
        SettingsSection.scanning,
        SettingsSection.tags,
        SettingsSection.transcode,
        SettingsSection.lyrics,
        SettingsSection.acoustid,
        SettingsSection.storage,
        SettingsSection.shortcuts,
        if (Platform.isWindows) SettingsSection.windows,
        SettingsSection.about,
      ];
}
