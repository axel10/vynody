import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/remote/clients/smb_client.dart';
import 'package:vynody/player/remote/proxy/local_stream_proxy.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_server_models.dart';

void main() {
  group('SMB Models and URIs Test', () {
    test('RemoteServerType handles smb correctly', () {
      expect(RemoteServerType.fromString('smb'), RemoteServerType.smb);
      expect(RemoteServerType.smb.displayName, 'Samba / SMB');
    });

    test('RemoteServer serialization with SMB fields', () {
      final server = RemoteServer(
        id: 'smb_1',
        name: 'My NAS',
        type: RemoteServerType.smb,
        url: '192.168.1.50:445',
        username: 'alice',
        customPath: 'music',
        domain: 'WORKGROUP',
        createdAt: DateTime(2026, 1, 1),
      );

      final json = server.toJson();
      expect(json['type'], 'smb');
      expect(json['domain'], 'WORKGROUP');
      expect(json['customPath'], 'music');

      final restored = RemoteServer.fromJson(json);
      expect(restored.type, RemoteServerType.smb);
      expect(restored.domain, 'WORKGROUP');
      expect(restored.customPath, 'music');
    });

    test('RemoteMediaResolver parseUri and buildSmbUri', () {
      final uri = RemoteMediaResolver.buildSmbUri('srv_1', 'music', 'JayChou/Fantasy/01.flac');
      expect(uri, 'smb://srv_1/music/JayChou/Fantasy/01.flac');
      expect(RemoteMediaResolver.isRemoteUri(uri), isTrue);

      final info = RemoteMediaResolver.parseUri(uri);
      expect(info, isNotNull);
      expect(info!.type, RemoteServerType.smb);
      expect(info.serverId, 'srv_1');
      expect(info.trackIdOrPath, 'music/JayChou/Fantasy/01.flac');

      final parts = RemoteMediaResolver.parseSmbParts(info.trackIdOrPath);
      expect(parts.$1, 'music');
      expect(parts.$2, 'JayChou/Fantasy/01.flac');
    });

    test('SmbFile properties detect audio and images correctly', () {
      const audioFile = SmbFile(
        share: 'music',
        path: 'test.flac',
        name: 'test.flac',
        isDirectory: false,
        contentLength: 1024,
      );
      expect(audioFile.isAudio, isTrue);
      expect(audioFile.isImage, isFalse);
      expect(audioFile.isLyric, isFalse);

      const coverFile = SmbFile(
        share: 'music',
        path: 'cover.jpg',
        name: 'cover.jpg',
        isDirectory: false,
        contentLength: 512,
      );
      expect(coverFile.isAudio, isFalse);
      expect(coverFile.isImage, isTrue);

      const lrcFile = SmbFile(
        share: 'music',
        path: 'test.lrc',
        name: 'test.lrc',
        isDirectory: false,
        contentLength: 128,
      );
      expect(lrcFile.isLyric, isTrue);

      const dir = SmbFile(
        share: 'music',
        path: 'Artist',
        name: 'Artist',
        isDirectory: true,
        contentLength: 0,
      );
      expect(dir.isAudio, isFalse);
    });

    test('LocalStreamProxy generates valid 127.0.0.1 streaming URL', () async {
      final streamUrl = await LocalStreamProxy.instance.buildSmbStreamUrl(
        serverId: 'srv_test',
        share: 'music',
        relativePath: 'song.mp3',
      );

      expect(streamUrl, contains('http://127.0.0.1:'));
      expect(streamUrl, contains('/smb/stream'));
      expect(streamUrl, contains('serverId=srv_test'));
      expect(streamUrl, contains('share=music'));
      expect(streamUrl, contains('path=song.mp3'));

      await LocalStreamProxy.instance.stop();
    });
  });
}
