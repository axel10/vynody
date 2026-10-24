import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/utils/drop_data_utils.dart';

import '../marquee/marquee_selection_region.dart';
import 'drag_payload.dart';

/// The single native drag-source implementation used across the app.
///
/// Wrapping a widget in a [DragSource] makes it draggable to:
/// * in-app queue / playlist drop zones (same isolate),
/// * the standalone queue window (separate isolate),
/// * other applications (Finder, Explorer, …).
///
/// Platform support checks, drag-session bookkeeping and [DragItem] assembly
/// live here once, so a call site only has to answer two questions: *what* is
/// being dragged ([buildPayload]) and *how it looks* while dragging
/// ([buildPreview]).
class DragSource extends StatelessWidget {
  const DragSource({
    super.key,
    required this.child,
    required this.buildPayload,
    required this.buildPreview,
    this.enabled = true,
  });

  final Widget child;

  /// Invoked when a drag actually starts.
  ///
  /// Deliberately lazy: collecting the dragged paths (every song of an album,
  /// every track of a genre…) must not happen on every rebuild.
  final DragPayload Function() buildPayload;

  final Widget Function(BuildContext context) buildPreview;

  final bool enabled;

  /// Whether native desktop drag & drop is available on this platform.
  static bool get isPlatformSupported => DropDataUtils.isPlatformSupported;

  /// Lets an in-progress marquee selection win over native file dragging.
  ///
  /// Evaluated synchronously by `super_drag_and_drop` inside
  /// `isPointerAllowed`, before the drag recognizer joins the gesture arena, so
  /// holding Alt on a list row starts a marquee instead of dragging the file
  /// out of the app. Returns `true` (drag allowed) everywhere else.
  static bool _isLocationDraggable(Offset position) =>
      !MarqueeSelectionRuntime.suppressNativeDrag;

  @override
  Widget build(BuildContext context) {
    if (!enabled || !isPlatformSupported) {
      return child;
    }

    return DragItemWidget(
      allowedOperations: () => const [DropOperation.copy, DropOperation.link],
      dragItemProvider: (request) async {
        DropDataUtils.trackInternalDrag(request.session);
        return buildPayload().toDragItem();
      },
      dragBuilder: (context, child) => buildPreview(context),
      child: DraggableWidget(
        hitTestBehavior: HitTestBehavior.translucent,
        isLocationDraggable: _isLocationDraggable,
        child: child,
      ),
    );
  }
}
