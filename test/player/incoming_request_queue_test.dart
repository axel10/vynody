import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/sharing/sharing_service.dart';

IncomingLyricsRequest _request(
  String senderId,
  List<String> decisions,
) {
  return IncomingLyricsRequest(
    senderId: senderId,
    senderName: senderId,
    type: IncomingLyricsRequestType.importLyrics,
    onDecision: (accepted) => decisions.add('$senderId:$accepted'),
  );
}

void main() {
  group('待确认请求排队', () {
    late ProviderContainer container;
    late List<String> decisions;

    setUp(() {
      container = ProviderContainer();
      decisions = [];
    });

    tearDown(() => container.dispose());

    test('第二条请求排队而不是覆盖第一条', () {
      final notifier = container.read(incomingLyricsRequestProvider.notifier);
      final first = _request('device-a', decisions);
      final second = _request('device-b', decisions);

      notifier.setRequest(first);
      notifier.setRequest(second);

      // 旧实现是单槽 `state = request`，这里会直接变成 second，
      // 而 first 的 Completer 永远不会完成，那条 HTTP 请求挂到超时。
      expect(container.read(incomingLyricsRequestProvider), same(first));

      notifier.setRequest(null);
      expect(container.read(incomingLyricsRequestProvider), same(second));

      notifier.setRequest(null);
      expect(container.read(incomingLyricsRequestProvider), isNull);
    });

    test('空队列时再出队不会报错', () {
      final notifier = container.read(incomingLyricsRequestProvider.notifier);
      notifier.setRequest(null);
      expect(container.read(incomingLyricsRequestProvider), isNull);
    });

    test('排队中的请求可以整体拒绝（断连 / 关闭共享时）', () {
      final notifier = container.read(incomingLyricsRequestProvider.notifier);
      notifier.setRequest(_request('a', decisions));
      notifier.setRequest(_request('b', decisions));

      notifier.rejectAllPending();

      // 两条都要给发起方一个明确的「拒绝」，否则它们会一直等。
      expect(decisions.toSet(), {'a:false', 'b:false'});
      expect(container.read(incomingLyricsRequestProvider), isNull);
    });

    test('歌单与文件传输各自独立排队', () {
      final lyrics = container.read(incomingLyricsRequestProvider.notifier);
      final playlists = container.read(
        incomingPlaylistRequestProvider.notifier,
      );

      lyrics.setRequest(_request('lyrics-sender', decisions));
      playlists.setRequest(
        IncomingPlaylistRequest(
          senderId: 'playlist-sender',
          senderName: 'playlist-sender',
          type: IncomingPlaylistRequestType.importPlaylists,
          onDecision: (_) {},
        ),
      );

      expect(
        container.read(incomingLyricsRequestProvider)?.senderId,
        'lyrics-sender',
      );
      expect(
        container.read(incomingPlaylistRequestProvider)?.senderId,
        'playlist-sender',
      );
    });
  });
}
