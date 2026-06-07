import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:vibe_flow/player/settings/settings_service.dart';
import 'package:vibe_flow/player/settings/windows_association_service.dart';
import 'package:vibe_flow/player/scanner/scanner_service.dart';
import 'package:vibe_flow/player/scanner/scanner_path_utils.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/utils/app_snack_bar.dart';
import '../l10n/app_localizations.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isAssociated = false;
  bool _isAssociating = false;

  @override
  void initState() {
    super.initState();
    _checkAssociationStatus();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkAssociationStatus() async {
    if (Platform.isWindows) {
      final status = await WindowsAssociationService.isAssociated();
      if (mounted) {
        setState(() {
          _isAssociated = status;
        });
      }
    }
  }

  Future<String?> _getDirectoryPath() {
    if (Platform.isWindows) {
      debugPrint('[Onboarding] picking directory with file_selector');
      return file_selector.getDirectoryPath();
    }
    debugPrint('[Onboarding] picking directory with file_picker');
    return FilePicker.getDirectoryPath(lockParentWindow: true);
  }

  Future<void> _pickFolder(ScannerService scanner) async {
    Directory? cwd;
    try {
      cwd = Directory.current;
    } catch (_) {}

    final selectedDirectory = await _getDirectoryPath();

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

      final result = await scanner.addRootPath(selectedDirectory);
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

  Future<void> _associateFiles() async {
    if (!Platform.isWindows) return;
    setState(() {
      _isAssociating = true;
    });

    final l10n = AppLocalizations.of(context)!;
    try {
      await WindowsAssociationService.associate();
      await _checkAssociationStatus();
      if (!mounted) return;
      AppSnackBar.show(
        context,
        ref,
        SnackBar(content: Text(l10n.associationSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        ref,
        SnackBar(content: Text(l10n.associationFailed(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAssociating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasWindowsAssociation = Platform.isWindows;

    final totalPages = hasWindowsAssociation ? 3 : 2;

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
              const SizedBox(height: 48),
              Expanded(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
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
                        )
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
                              // Step 2: Windows File Association (If on Windows)
                              if (hasWindowsAssociation)
                                _buildFileAssociationPage(l10n, theme),
                              // Step 3: Add Music Directory
                              _buildMusicDirectoryPage(l10n, theme),
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
              const SizedBox(height: 48),
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
                )
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

  Widget _buildFileAssociationPage(AppLocalizations l10n, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
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
                  color: const Color(0xFF39C5BB).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.open_in_new_rounded,
                  color: Color(0xFF39C5BB),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  l10n.onboardingStepFileAssociation,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            l10n.onboardingFileAssociationDesc,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(isDark ? 0.08 : 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.amber.withOpacity(isDark ? 0.3 : 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.onboardingFileAssociationTip,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: isDark ? Colors.amber[200] : Colors.amber[900],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: _isAssociated
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                      label: Text(
                        '已开启关联 (Associated)',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _isAssociating ? null : _associateFiles,
                      icon: _isAssociating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.link_rounded),
                      label: Text(
                        l10n.associateButton,
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
              '已添加的目录 (${rootFolders.length})：',
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: rootFolders.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: theme.colorScheme.onSurface.withOpacity(0.06),
                  ),
                  itemBuilder: (context, index) {
                    final folder = rootFolders[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.folder, color: Colors.amber, size: 20),
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
                            Icons.check_circle,
                            color: theme.colorScheme.primary,
                            size: 18,
                          ),
                        ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
}
