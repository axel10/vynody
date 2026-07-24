import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/file_selector_helper.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/transcode/transcode_riverpod.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:audio_core/audio_core.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:linux_directory_access/linux_directory_access.dart';
import 'package:device_info_plus/device_info_plus.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isBatteryExempted = false;
  bool _isMediaPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      _checkBatteryExemptionStatus();
      _checkMediaPermissionStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (Platform.isAndroid) {
        _checkBatteryExemptionStatus();
        _checkMediaPermissionStatus();
        // 延迟检测以应对 Android 系统电池优化与权限状态同步延迟的问题
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _checkBatteryExemptionStatus();
            _checkMediaPermissionStatus();
          }
        });
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            _checkBatteryExemptionStatus();
            _checkMediaPermissionStatus();
          }
        });
      }
    }
  }

  Future<void> _checkMediaPermissionStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      bool granted = false;
      if (androidInfo.version.sdkInt >= 33) {
        granted = await Permission.audio.isGranted;
      } else {
        granted = await Permission.storage.isGranted;
      }
      if (mounted) {
        setState(() {
          _isMediaPermissionGranted = granted;
        });
      }
    } catch (e) {
      debugPrint('[Onboarding] Error checking media permission: $e');
    }
  }

  Future<void> _requestMediaPermission() async {
    if (!Platform.isAndroid) return;
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      PermissionStatus status;
      if (androidInfo.version.sdkInt >= 33) {
        status = await Permission.audio.request();
      } else {
        status = await Permission.storage.request();
      }
      if (mounted) {
        setState(() {
          _isMediaPermissionGranted = status.isGranted;
        });
      }
    } catch (e) {
      debugPrint('[Onboarding] Error requesting media permission: $e');
    }
  }

  Future<void> _checkBatteryExemptionStatus() async {
    try {
      final exempted = await Permission.ignoreBatteryOptimizations.isGranted;
      if (mounted) {
        setState(() {
          _isBatteryExempted = exempted;
        });
      }
    } catch (e) {
      debugPrint('[Onboarding] Error checking battery exemption: $e');
    }
  }

  Future<void> _requestBatteryExemption() async {
    debugPrint(
      '[Onboarding] _requestBatteryExemption called. _isBatteryExempted = $_isBatteryExempted',
    );
    const channel = MethodChannel('app.vynody.player/battery');
    try {
      debugPrint(
        '[Onboarding] Invoking requestIgnoreBatteryOptimizations via channel...',
      );
      await channel.invokeMethod('requestIgnoreBatteryOptimizations');
      debugPrint('[Onboarding] requestIgnoreBatteryOptimizations success.');
    } catch (e) {
      debugPrint('[Onboarding] requestIgnoreBatteryOptimizations failed: $e');
      try {
        debugPrint('[Onboarding] Invoking openBatterySettings via channel...');
        await channel.invokeMethod('openBatterySettings');
        debugPrint('[Onboarding] openBatterySettings success.');
      } catch (e2) {
        debugPrint('[Onboarding] openBatterySettings failed: $e2');
        try {
          debugPrint(
            '[Onboarding] Invoking openAppSettings via permission_handler...',
          );
          final opened = await openAppSettings();
          debugPrint('[Onboarding] openAppSettings result: $opened');
        } catch (e3) {
          debugPrint('[Onboarding] openAppSettings failed: $e3');
        }
      }
    }
  }

  Future<String?> _getDirectoryPath() {
    return FileSelectorHelper.pickDirectory();
  }

  Future<void> _pickFolder(ScannerService scanner) async {
    Directory? cwd;
    try {
      cwd = Directory.current;
    } catch (_) {}

    String? selectedDirectory;
    String? persistentDocumentId;
    AndroidOutputDirectory? androidOutputDirectory;

    if (Platform.isAndroid) {
      androidOutputDirectory = await ref
          .read(transcodeServiceProvider)
          .pickAndroidOutputDirectory();
      selectedDirectory = androidOutputDirectory?.displayPath;
    } else if (Platform.isLinux && await LinuxDirectoryAccess().isFlatpak) {
      final grant = await LinuxDirectoryAccess().pickDirectory();
      selectedDirectory = grant?.path;
      persistentDocumentId = grant?.documentId;
    } else {
      selectedDirectory = await _getDirectoryPath();
    }

    if (cwd != null) {
      try {
        Directory.current = cwd;
      } catch (_) {}
    }

    if (selectedDirectory != null) {
      if (!mounted) return;

      if (Platform.isWindows) {
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (Platform.isAndroid && androidOutputDirectory != null) {
        await AndroidSafStorageHelper.saveMapping(
          androidOutputDirectory.displayPath,
          androidOutputDirectory.treeUri,
        );
      }

      final result = await scanner.addRootPath(
        selectedDirectory,
        persistentDocumentId: persistentDocumentId,
      );
      if (!mounted) return;

      String message;
      switch (result.status) {
        case RootPathAddStatus.added:
        case RootPathAddStatus.alreadyAdded:
          message = AppLocalizations.of(context)!.directoryAddedSuccess;
          break;
        case RootPathAddStatus.noMusic:
          message = AppLocalizations.of(context)!.directoryAddedNoMusic;
          break;
        case RootPathAddStatus.persistentAccessDenied:
          message = AppLocalizations.of(context)!.persistentAccessDenied;
          break;
        case RootPathAddStatus.failed:
          message = AppLocalizations.of(context)!.folderAddFailed;
          break;
      }
      AppSnackBar.show(context, ref, SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final showAndroidMediaGuide = Platform.isAndroid;
    final showLinuxGuide = Platform.isLinux;
    final showAndroidBatteryGuide = Platform.isAndroid;
    final totalPages = 2 +
        (showAndroidMediaGuide ? 1 : 0) +
        (showLinuxGuide ? 1 : 0) +
        (showAndroidBatteryGuide ? 1 : 0);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    const Color(0xFF0F172A),
                    const Color(0xFF1E293B),
                    const Color(0xFF0F172A),
                  ]
                : [
                    const Color(0xFFF8FAFC),
                    const Color(0xFFF1F5F9),
                    const Color(0xFFE2E8F0),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Spacer to push the card down slightly, taking custom title bar into account
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 500,
                      maxHeight: 600,
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.04)
                          : Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.black.withOpacity(0.08),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Expanded(
                          child: PageView(
                            controller: _pageController,
                            onPageChanged: (page) {
                              setState(() {
                                _currentPage = page;
                              });
                            },
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              // Step 1: Welcome
                              _buildWelcomePage(l10n, theme),
                              // Step 2 (Android only): Audio Library & Fast Scan Setup
                              if (showAndroidMediaGuide)
                                _buildAndroidMediaGuidePage(theme),
                              // Step 3: Add Music Directory
                              _buildMusicDirectoryPage(l10n, theme),
                              // Step 4 (Linux only): Linux Disk Auto-Mount Guide
                              if (showLinuxGuide)
                                _buildLinuxMountGuidePage(theme),
                              // Step 5 (Android only): Android Battery Optimization Guide
                              if (showAndroidBatteryGuide)
                                _buildAndroidBatteryGuidePage(theme),
                            ],
                          ),
                        ),
                        // Page navigation indicators & actions
                        _buildBottomActionBar(l10n, theme, totalPages),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomePage(AppLocalizations l10n, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF39C5BB), Color(0xFF28A49C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF39C5BB).withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.music_note_rounded,
              size: 64,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 40),
          Text(
            l10n.onboardingTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.onboardingSubtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMusicDirectoryPage(AppLocalizations l10n, ThemeData theme) {
    final scanner = ref.watch(scannerServiceProvider);
    final rootFolders = ref.watch(
      scannerServiceProvider.select((s) => s.rootFolders),
    );

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.folder_shared_rounded,
                  color: Colors.blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  l10n.onboardingStepRootDirectory,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            l10n.onboardingRootDirectoryDesc,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
              height: 1.5,
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: () => _pickFolder(scanner),
                icon: const Icon(Icons.create_new_folder_rounded),
                label: Text(
                  l10n.onboardingSelectDirectory,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF39C5BB),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (rootFolders.isNotEmpty) ...[
            Text(
              l10n.onboardingAddedDirectoriesCount(rootFolders.length),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withOpacity(0.08),
                  ),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: rootFolders.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: theme.colorScheme.onSurface.withOpacity(0.06),
                  ),
                  itemBuilder: (context, index) {
                    final folder = rootFolders[index];
                    final isAvailable = scanner.isRootPathAvailable(
                      folder.path,
                    );
                    return AnimatedOpacity(
                      opacity: isAvailable ? 1.0 : 0.45,
                      duration: const Duration(milliseconds: 180),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.folder,
                              color: Colors.amber,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                folder.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isAvailable
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              color: isAvailable
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ] else ...[
            const Spacer(),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(
    AppLocalizations l10n,
    ThemeData theme,
    int totalPages,
  ) {
    final isLastPage = _currentPage == totalPages - 1;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.onSurface.withOpacity(0.06),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Step indicators
          Row(
            children: List.generate(
              totalPages,
              (index) => Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index
                      ? const Color(0xFF39C5BB)
                      : theme.colorScheme.onSurface.withOpacity(0.2),
                ),
              ),
            ),
          ),
          // Actions
          Row(
            children: [
              if (_currentPage > 0)
                TextButton(
                  onPressed: () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Text(
                    l10n.onboardingBack,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: widget.onComplete,
                  child: Text(
                    l10n.onboardingSkip,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  if (isLastPage) {
                    widget.onComplete();
                  } else {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF39C5BB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isLastPage ? l10n.onboardingStartButton : l10n.onboardingNext,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openGnomeDisks() async {
    try {
      final result = await Process.run('gnome-disks', []);
      if (result.exitCode != 0) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppSnackBar.show(
            context,
            ref,
            SnackBar(content: Text(l10n.gnomeDisksOpenFailed)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackBar.show(
          context,
          ref,
          SnackBar(content: Text(l10n.gnomeDisksNotInstalled)),
        );
      }
    }
  }

  Widget _buildLinuxMountGuidePage(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    final title = l10n.linuxMountGuideTitle;
    final desc = l10n.linuxMountGuideDescription;
    final step1 = l10n.linuxMountGuideStep1;
    final step2 = l10n.linuxMountGuideStep2;
    final step3 = l10n.linuxMountGuideStep3;
    final openButtonText = l10n.linuxMountGuideOpenButton;

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.storage_rounded,
                  color: Colors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            desc,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _buildWarningBanner(theme, l10n),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withOpacity(0.08),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStepRow(step1, theme),
                    const SizedBox(height: 12),
                    _buildStepRow(step2, theme),
                    const SizedBox(height: 12),
                    _buildStepRow(step3, theme),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _openGnomeDisks,
                icon: const Icon(Icons.launch_rounded, size: 18),
                label: Text(
                  openButtonText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(
                    color: theme.colorScheme.onSurface.withOpacity(0.15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner(ThemeData theme, AppLocalizations l10n) {
    final isDark = theme.brightness == Brightness.dark;
    final warningColor = isDark ? Colors.amberAccent : Colors.orange.shade900;
    final warningBgColor = isDark
        ? Colors.amber.withOpacity(0.08)
        : Colors.orange.withOpacity(0.08);
    final warningBorderColor = isDark
        ? Colors.amber.withOpacity(0.2)
        : Colors.orange.withOpacity(0.2);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warningBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: warningBorderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: warningColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.linuxMountGuideWarning,
              style: theme.textTheme.bodySmall?.copyWith(
                color: warningColor,
                height: 1.4,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(String text, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3.0),
          child: Icon(
            Icons.arrow_right_rounded,
            size: 16,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.4,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBatteryStatusBanner(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;

    final statusText = _isBatteryExempted
        ? l10n.onboardingAndroidBatteryStatusUnrestricted
        : l10n.onboardingAndroidBatteryStatusOptimized;

    final statusColor = _isBatteryExempted
        ? (isDark ? Colors.greenAccent : Colors.green.shade800)
        : (isDark ? Colors.amberAccent : Colors.orange.shade900);
    final statusBgColor = _isBatteryExempted
        ? Colors.green.withOpacity(isDark ? 0.12 : 0.08)
        : Colors.orange.withOpacity(isDark ? 0.12 : 0.08);
    final statusBorderColor = _isBatteryExempted
        ? Colors.green.withOpacity(0.25)
        : Colors.orange.withOpacity(0.25);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: statusBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusBorderColor),
      ),
      child: Row(
        children: [
          Icon(
            _isBatteryExempted
                ? Icons.check_circle_rounded
                : Icons.warning_amber_rounded,
            color: statusColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusText,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: statusColor,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidBatteryGuidePage(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    final title = l10n.onboardingAndroidBatteryTitle;
    final desc = l10n.onboardingAndroidBatteryDescription;
    final step1 = l10n.onboardingAndroidBatteryStep1;
    final step2 = l10n.onboardingAndroidBatteryStep2;
    final step3 = l10n.onboardingAndroidBatteryStep3;
    final openButtonText = l10n.onboardingAndroidBatteryButton;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.battery_alert_rounded,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            desc,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          _buildBatteryStatusBanner(theme),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withOpacity(0.08),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStepRow(step1, theme),
                    const SizedBox(height: 10),
                    _buildStepRow(step2, theme),
                    const SizedBox(height: 10),
                    _buildStepRow(step3, theme),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _requestBatteryExemption,
                icon: const Icon(Icons.settings_suggest_rounded, size: 18),
                label: Text(
                  openButtonText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(
                    color: theme.colorScheme.onSurface.withOpacity(0.15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidMediaGuidePage(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    final title = l10n.onboardingAndroidMediaTitle;
    final desc = l10n.onboardingAndroidMediaDescription;
    final step1 = l10n.onboardingAndroidMediaStep1;
    final step2 = l10n.onboardingAndroidMediaStep2;
    final step3 = l10n.onboardingAndroidMediaStep3;
    final openButtonText = l10n.onboardingAndroidMediaButton;

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Colors.deepOrange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            desc,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          _buildMediaStatusBanner(theme),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withOpacity(0.08),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStepRow(step1, theme),
                    const SizedBox(height: 10),
                    _buildStepRow(step2, theme),
                    const SizedBox(height: 10),
                    _buildStepRow(step3, theme),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: _isMediaPermissionGranted
                  ? FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: Text(
                        l10n.onboardingAndroidMediaStatusGranted,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        disabledBackgroundColor: Colors.green.withOpacity(0.15),
                        disabledForegroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: _requestMediaPermission,
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: Text(
                        openButtonText,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(
                          color: theme.colorScheme.onSurface.withOpacity(0.15),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaStatusBanner(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    final statusText = _isMediaPermissionGranted
        ? l10n.onboardingAndroidMediaStatusGranted
        : l10n.onboardingAndroidMediaStatusNotGranted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _isMediaPermissionGranted
            ? Colors.green.withOpacity(0.12)
            : theme.colorScheme.onSurface.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isMediaPermissionGranted
              ? Colors.green.withOpacity(0.3)
              : theme.colorScheme.onSurface.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isMediaPermissionGranted
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            color: _isMediaPermissionGranted
                ? Colors.green
                : theme.colorScheme.onSurface.withOpacity(0.6),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: _isMediaPermissionGranted
                    ? Colors.green
                    : theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
