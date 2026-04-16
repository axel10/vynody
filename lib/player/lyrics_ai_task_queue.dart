import 'dart:async';

class LyricsAiTaskQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    final previous = _tail;

    _tail = previous.then((_) async {
      try {
        final result = await task();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    }).catchError((_) {});

    return completer.future;
  }
}
