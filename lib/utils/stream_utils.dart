import 'dart:async';

extension StreamRateLimitExtension<T> on Stream<T> {
  /// Rate-limits the stream with leading-edge immediate delivery and trailing-edge debounce.
  ///
  /// - The first event (or any event arriving after [duration] of inactivity) is emitted immediately (0 latency).
  /// - Subsequent events arriving within [duration] are throttled/debounced, and the latest event
  ///   is emitted after the window has passed.
  Stream<T> throttleLeadingAndTrailing(Duration duration) {
    StreamController<T>? controller;
    StreamSubscription<T>? subscription;
    Timer? timer;
    T? pendingValue;
    bool hasPending = false;
    DateTime? lastEmitTime;

    controller = StreamController<T>(
      sync: true,
      onListen: () {
        subscription = listen(
          (data) {
            final now = DateTime.now();
            final elapsed = lastEmitTime == null
                ? duration
                : now.difference(lastEmitTime!);

            if (elapsed >= duration && (timer == null || !timer!.isActive)) {
              lastEmitTime = now;
              hasPending = false;
              pendingValue = null;
              controller?.add(data);
            } else {
              pendingValue = data;
              hasPending = true;
              if (timer == null || !timer!.isActive) {
                final remaining = duration - elapsed;
                final delay = remaining > Duration.zero ? remaining : duration;
                timer = Timer(delay, () {
                  timer = null;
                  if (hasPending && !(controller?.isClosed ?? true)) {
                    lastEmitTime = DateTime.now();
                    final val = pendingValue as T;
                    hasPending = false;
                    pendingValue = null;
                    controller?.add(val);
                  }
                });
              }
            }
          },
          onError: controller?.addError,
          onDone: () {
            timer?.cancel();
            timer = null;
            if (hasPending && !(controller?.isClosed ?? true)) {
              controller?.add(pendingValue as T);
            }
            controller?.close();
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        timer?.cancel();
        timer = null;
        return subscription?.cancel();
      },
    );

    return controller.stream;
  }
}
