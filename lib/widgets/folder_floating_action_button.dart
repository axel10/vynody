import 'package:flutter/material.dart';

/// A floating action button shell matching QueuePage's portrait floating actions style.
class FolderFloatingActionButton extends StatelessWidget {
  const FolderFloatingActionButton({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: Material(
            shape: const CircleBorder(),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.92),
            elevation: 4.0,
            shadowColor: Colors.black.withValues(alpha: 0.28),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
  }
}
