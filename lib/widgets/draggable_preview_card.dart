import 'dart:io';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/utils/drop_data_utils.dart';

/// Reusable visual preview card shown when dragging items across the app or desktop.
class AppDraggablePreviewCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? imagePath;
  final IconData defaultIcon;
  final int count;
  final String? badgeText;
  final bool isBatch;
  final double width;

  const AppDraggablePreviewCard({
    super.key,
    required this.title,
    this.subtitle,
    this.imagePath,
    this.defaultIcon = Icons.music_note_rounded,
    this.count = 1,
    this.badgeText,
    this.isBatch = false,
    this.width = 250,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = imagePath != null &&
        imagePath!.isNotEmpty &&
        File(imagePath!).existsSync();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    image: hasImage
                        ? DecorationImage(
                            image: FileImage(File(imagePath!)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: !hasImage
                      ? Icon(
                          defaultIcon,
                          size: 22,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                ),
                if (isBatch && count > 1)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        badgeText ?? '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimary,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Expanded(
                          child: Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: isBatch
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight:
                                  isBatch ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                        ),
                      if (!isBatch && badgeText != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeText!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Generic wrapper that handles desktop platform verification, translucent hit testing,
/// and SuperDragAndDrop configuration.
class DesktopDraggableWrapper extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final Future<DragItem?> Function(DragItemRequest request) dragItemProvider;
  final Widget Function(BuildContext context, Widget child) dragBuilder;
  final List<DropOperation> Function()? allowedOperations;

  const DesktopDraggableWrapper({
    super.key,
    required this.child,
    this.enabled = true,
    required this.dragItemProvider,
    required this.dragBuilder,
    this.allowedOperations,
  });

  static bool get isPlatformSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    if (!enabled || !isPlatformSupported) {
      return child;
    }

    return DragItemWidget(
      dragItemProvider: (request) async {
        DropDataUtils.isInternalDragActive = true;
        request.session.dragCompleted.addListener(() {
          Future.delayed(const Duration(milliseconds: 350), () {
            DropDataUtils.isInternalDragActive = false;
          });
        });
        try {
          return await dragItemProvider(request);
        } catch (e) {
          DropDataUtils.isInternalDragActive = false;
          rethrow;
        }
      },
      allowedOperations: allowedOperations ??
          () => const [DropOperation.copy, DropOperation.link],
      dragBuilder: dragBuilder,
      child: DraggableWidget(
        hitTestBehavior: HitTestBehavior.translucent,
        child: child,
      ),
    );
  }
}
