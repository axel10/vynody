import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/dialogs/shortcut_settings_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/pages/settings/sections/about_section.dart';
import 'package:vynody/pages/settings/sections/acoustid_section.dart';
import 'package:vynody/pages/settings/sections/audio_section.dart';
import 'package:vynody/pages/settings/sections/general_section.dart';
import 'package:vynody/pages/settings/sections/proxy_section.dart';
import 'package:vynody/pages/settings/sections/shortcuts_section.dart';
import 'package:vynody/pages/settings/sections/tags_section.dart';
import 'package:vynody/pages/settings/sections/transcode_section.dart';
import 'package:vynody/pages/settings/settings_search_registry.dart';
import 'package:vynody/pages/settings/widgets/settings_dropdown_tile.dart';
import 'package:vynody/pages/settings/widgets/settings_group_card.dart';
import 'package:vynody/pages/settings/widgets/settings_section_header.dart';
import 'package:vynody/pages/settings_page.dart';
import 'package:vynody/player/pro/pro_models.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/player/settings/shortcut_bindings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SettingsSection enum provides correct metadata', () {
    // 13 个真实分组 + home 伪条目（首页本身不是一个设置页）。
    expect(SettingsSection.values.length, 14);
    expect(SettingsSection.visibleSections.contains(SettingsSection.general), isTrue);
    expect(SettingsSection.visibleSections.contains(SettingsSection.audio), isTrue);
    expect(SettingsSection.visibleSections.contains(SettingsSection.proxy), isTrue);
    expect(SettingsSection.visibleSections.contains(SettingsSection.lyrics), isTrue);
    expect(SettingsSection.visibleSections.contains(SettingsSection.about), isTrue);
  });

  test('home 卡片分组与侧栏清单同源，且覆盖所有可见分组', () {
    final visible = SettingsSection.visibleSections;

    // 首页只是伪条目，不应出现在任何清单里。
    expect(visible.contains(SettingsSection.home), isFalse);

    // 分组字段必须覆盖每一个真实分组（新增枚举忘了归口会编译失败，这里兜底运行时）。
    for (final section in visible) {
      expect(section.group, isNotNull, reason: '${section.name} 缺少分组归口');
    }

    // 侧栏 = 首页卡片展平，顺序一致 —— 这是「两边漏项」的回归断言。
    final flattened = SettingsSection.homeGroups.values.expand((e) => e).toList();
    expect(flattened, visible);

    // Windows 专属页只在 Windows 上出现。
    expect(
      visible.contains(SettingsSection.windows),
      Platform.isWindows,
    );
  });

  test('每个可见分组在搜索索引里都有条目', () {
    final indexed = settingsSearchRegistry.map((item) => item.section).toSet();
    for (final section in SettingsSection.visibleSections) {
      expect(
        indexed.contains(section),
        isTrue,
        reason: '${section.name} 没有搜索条目，搜索页会搜不到它',
      );
    }
  });

  test('ProFeature.wasapiExclusive exists and provides metadata', () {
    expect(ProFeature.values.contains(ProFeature.wasapiExclusive), isTrue);
    expect(ProFeature.wasapiExclusive.icon, Icons.speaker_group_rounded);
  });

  testWidgets('SettingsSectionHeader renders title and description', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsSectionHeader(
            title: 'Test Header',
            description: 'Test Description',
          ),
        ),
      ),
    );

    expect(find.text('Test Header'), findsOneWidget);
    expect(find.text('Test Description'), findsOneWidget);
  });

  testWidgets('SettingsGroupCard renders title, icon and children', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsGroupCard(
            title: 'Group Title',
            icon: Icons.settings,
            children: [Text('Child 1'), Text('Child 2')],
          ),
        ),
      ),
    );

    expect(find.text('Group Title'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.text('Child 1'), findsOneWidget);
    expect(find.text('Child 2'), findsOneWidget);
  });

  testWidgets('SettingsDropdownTile renders selection and options with trailing badge', (tester) async {
    String selected = 'opt1';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsDropdownTile<String>(
            title: 'Dropdown Title',
            value: selected,
            options: const [
              SettingsDropdownOption(value: 'opt1', label: 'Option 1'),
              SettingsDropdownOption(
                value: 'opt2',
                label: 'Option 2',
                trailing: Text('PRO_BADGE'),
              ),
            ],
            onChanged: (val) {
              if (val != null) selected = val;
            },
          ),
        ),
      ),
    );

    expect(find.text('Dropdown Title'), findsOneWidget);
    expect(find.text('Option 1'), findsOneWidget);
  });

  testWidgets('ShortcutsSection renders correctly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ShortcutsSection(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShortcutsSection), findsOneWidget);
  });

  testWidgets('AudioSection renders correctly', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AudioSection(settings: settings),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AudioSection), findsOneWidget);
  });

  testWidgets('TagsSection renders correctly', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TagsSection(settings: settings),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TagsSection), findsOneWidget);
  });

  testWidgets('TranscodeSection renders correctly', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TranscodeSection(settings: settings),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TranscodeSection), findsOneWidget);
  });

  testWidgets('AcoustidSection renders correctly', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AcoustidSection(settings: settings),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AcoustidSection), findsOneWidget);
  });

  testWidgets('AboutSection renders correctly', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AboutSection(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AboutSection), findsOneWidget);
  });

  test('AppShortcutAction.toggleWasapiExclusive metadata and defaults', () {
    expect(
      AppShortcutAction.values.contains(AppShortcutAction.toggleWasapiExclusive),
      isTrue,
    );
    expect(
      AppShortcutAction.toggleWasapiExclusive.storageKey,
      'toggle_wasapi_exclusive',
    );
    final defaultBinding =
        AppShortcutAction.toggleWasapiExclusive.defaultBinding;
    expect(defaultBinding.shift, isTrue);
  });

  test('hasUsedWasapiExclusive auto-activates when mode is set to wasapi_exclusive', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);

    expect(settings.hasUsedWasapiExclusive, isFalse);

    // Setting mode to wasapi_exclusive triggers hasUsedWasapiExclusive
    settings.windowsAudioOutputMode = 'wasapi_exclusive';
    expect(settings.hasUsedWasapiExclusive, isTrue);

    // Resetting mode to shared preserves hasUsedWasapiExclusive
    settings.windowsAudioOutputMode = 'shared';
    expect(settings.hasUsedWasapiExclusive, isTrue);
  });

  testWidgets('SingleShortcutEditDialog renders correctly', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleShortcutEditDialog(
              action: AppShortcutAction.toggleWasapiExclusive,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleShortcutEditDialog), findsOneWidget);
    expect(find.byType(ShortcutRecorderField), findsOneWidget);
  });

  testWidgets('GeneralSection renders rewindToStartOnPrevious switch and toggles it', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: GeneralSection(settings: settings),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(settings.rewindToStartOnPrevious, isTrue);

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    final tileFinder = find.widgetWithText(SwitchListTile, l10n.rewindToStartOnPrevious);
    expect(tileFinder, findsOneWidget);

    final switchTile = tester.widget<SwitchListTile>(tileFinder);
    expect(switchTile.value, isTrue);

    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    expect(settings.rewindToStartOnPrevious, isFalse);
  });

  testWidgets('ProxySection renders correctly', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: ProxySection(settings: settings),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l10n.proxySettingsTitle), findsWidgets);
    expect(find.text(l10n.proxyMode), findsOneWidget);
  });
}
