import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/services/remote_directory_scanner.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'folder_nav_bar_scaffold.dart';

/// Unified model representing the active scanning progress (local or remote).
@immutable
class ScanProgressInfo {
  final bool isScanning;
  final double? progress; // 0.0 ~ 1.0, or null for indeterminate
  final int discoveredCount;
  final int completedCount;
  final String? currentFile;
  final String? serverName;

  const ScanProgressInfo({
    this.isScanning = false,
    this.progress,
    this.discoveredCount = 0,
    this.completedCount = 0,
    this.currentFile,
    this.serverName,
  });

  ScanProgressInfo copyWith({
    bool? isScanning,
    double? progress,
    int? discoveredCount,
    int? completedCount,
    String? currentFile,
    String? serverName,
  }) {
    return ScanProgressInfo(
      isScanning: isScanning ?? this.isScanning,
      progress: progress ?? this.progress,
      discoveredCount: discoveredCount ?? this.discoveredCount,
      completedCount: completedCount ?? this.completedCount,
      currentFile: currentFile ?? this.currentFile,
      serverName: serverName ?? this.serverName,
    );
  }
}

/// Provider that computes and coordinates scanning progress for folder pages.
class ScanProgressInfoNotifier extends Notifier<ScanProgressInfo> {
  StreamSubscription<ScanProgress>? _localProgressSub;
  ScannerService? _observedScanner;
  ScanProgressInfo? _lastLocalProgressInfo;

  @override
  ScanProgressInfo build() {
    final localScanner = ref.watch(scannerServiceProvider);
    final remoteProgress = ref.watch(remoteScanProgressProvider);

    if (_observedScanner != localScanner) {
      _localProgressSub?.cancel();
      _observedScanner = localScanner;
      _localProgressSub = localScanner.scanProgressStream.listen(_handleLocalProgress);
    }

    ref.onDispose(() {
      _localProgressSub?.cancel();
      _localProgressSub = null;
      _observedScanner = null;
      _lastLocalProgressInfo = null;
    });

    return _calculateState(localScanner, remoteProgress);
  }

  void _handleLocalProgress(ScanProgress progress) {
    final localScanner = ref.read(scannerServiceProvider);
    if (!localScanner.isScanning) {
      _lastLocalProgressInfo = null;
      return;
    }

    final discovered = progress.discoveredCount;
    final completed = progress.completedCount;
    final ratio = discovered > 0 ? (completed / discovered).clamp(0.0, 1.0) : null;

    final newInfo = ScanProgressInfo(
      isScanning: true,
      progress: ratio,
      discoveredCount: discovered,
      completedCount: completed,
      currentFile: progress.filePath,
      serverName: null,
    );
    _lastLocalProgressInfo = newInfo;
    state = newInfo;
  }

  ScanProgressInfo _calculateState(
    ScannerService localScanner,
    RemoteScanProgress remoteProgress,
  ) {
    if (remoteProgress.isScanning) {
      final discovered = remoteProgress.totalDiscovered;
      final completed = remoteProgress.processedCount;
      final ratio = discovered > 0 ? (completed / discovered).clamp(0.0, 1.0) : null;
      return ScanProgressInfo(
        isScanning: true,
        progress: ratio,
        discoveredCount: discovered,
        completedCount: completed,
        currentFile: remoteProgress.currentFile ?? remoteProgress.currentFolder,
        serverName: remoteProgress.serverName,
      );
    }

    if (localScanner.isScanning) {
      return _lastLocalProgressInfo ?? const ScanProgressInfo(isScanning: true);
    }

    _lastLocalProgressInfo = null;
    return const ScanProgressInfo(isScanning: false);
  }
}

final scanProgressInfoProvider =
    NotifierProvider<ScanProgressInfoNotifier, ScanProgressInfo>(
  ScanProgressInfoNotifier.new,
);

/// A compact, elegant spinning indicator designed for the folder header action bar.
class FolderScanSpinner extends ConsumerWidget {
  const FolderScanSpinner({
    super.key,
    this.style,
  });

  final FolderNavBarStyle? style;

  void _showScanDetailsDialog(BuildContext context, ScanProgressInfo info) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fileName = info.currentFile != null && info.currentFile!.isNotEmpty
        ? p.basename(info.currentFile!)
        : '';

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  info.serverName != null && info.serverName!.isNotEmpty
                      ? '${l10n?.scanningDirectory ?? "扫描目录"} (${info.serverName})'
                      : (l10n?.scanningDirectory ?? '扫描目录'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.discoveredCount > 0)
                Text(
                  l10n != null
                      ? '${l10n.filesDiscovered(info.discoveredCount)} · ${l10n.filesFullyProcessed(info.completedCount)}'
                      : '已发现 ${info.discoveredCount} · 已完成 ${info.completedCount}',
                  style: theme.textTheme.bodyMedium,
                ),
              if (fileName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(scanProgressInfoProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: info.isScanning
          ? Tooltip(
              key: const ValueKey('folder-scan-spinner-active'),
              message: info.discoveredCount > 0
                  ? (l10n != null
                      ? '${l10n.scanningDirectory}: ${info.completedCount}/${info.discoveredCount}'
                      : '正在扫描: ${info.completedCount}/${info.discoveredCount}')
                  : (l10n?.scanningDirectory ?? '正在扫描目录...'),
              child: InkResponse(
                onTap: () => _showScanDetailsDialog(context, info),
                radius: 18,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          style?.iconColor ?? theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('folder-scan-spinner-idle')),
    );
  }
}

/// A hairline progress indicator anchored to the bottom edge of [FolderHeaderBanner].
class FolderBannerScanProgressBar extends ConsumerStatefulWidget {
  const FolderBannerScanProgressBar({super.key});

  @override
  ConsumerState<FolderBannerScanProgressBar> createState() =>
      _FolderBannerScanProgressBarState();
}

class _FolderBannerScanProgressBarState
    extends ConsumerState<FolderBannerScanProgressBar> {
  bool _isVisible = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _handleScanningTransition(bool isScanning) {
    if (isScanning) {
      _hideTimer?.cancel();
      _hideTimer = null;
      if (!_isVisible) {
        setState(() => _isVisible = true);
      }
    } else if (_isVisible && _hideTimer == null) {
      // Delay fade out slightly for a smooth, rewarding completion transition
      _hideTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() => _isVisible = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(scanProgressInfoProvider);
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    // React to scanning state changes
    _handleScanningTransition(info.isScanning);

    return AnimatedOpacity(
      opacity: _isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: _isVisible
          ? SizedBox(
              height: 2.5,
              width: double.infinity,
              child: info.progress != null
                  ? TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0.0,
                        end: info.isScanning ? info.progress! : 1.0,
                      ),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      builder: (context, animatedValue, _) {
                        return LinearProgressIndicator(
                          value: animatedValue,
                          backgroundColor: primaryColor.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                          minHeight: 2.5,
                        );
                      },
                    )
                  : LinearProgressIndicator(
                      value: null,
                      backgroundColor: primaryColor.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      minHeight: 2.5,
                    ),
            )
          : const SizedBox.shrink(),
    );
  }
}
