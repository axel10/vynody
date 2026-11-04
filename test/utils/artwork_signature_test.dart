import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/utils/artwork_signature.dart';

/// 封面签名是「同一首歌换封面」这条链路的唯一判据，被三处共用：
/// 模糊背景位图缓存、网格背景纹理、播放页的封面字节缓存。
///
/// 判据一旦退化成 identity（比如有人图省事换成 `bytes.hashCode`），
/// 换封面后背景不会跟着换，而每次播放又会因为字节实例不同而反复重启过渡。
void main() {
  Uint8List bytesOf(int length, {int seed = 0}) {
    return Uint8List.fromList(
      List<int>.generate(length, (i) => (i * 31 + seed) & 0xFF),
    );
  }

  group('artworkBytesSignature', () {
    test('内容相同、实例不同 → 签名相同', () {
      final a = bytesOf(4096);
      final b = Uint8List.fromList(a);

      expect(identical(a, b), isFalse);
      expect(artworkBytesSignature(a), artworkBytesSignature(b));
    });

    test('同一首歌换了封面 → 签名不同', () {
      final oldCover = bytesOf(4096, seed: 1);
      final newCover = bytesOf(4096, seed: 2);

      expect(
        artworkBytesSignature(oldCover),
        isNot(artworkBytesSignature(newCover)),
      );
    });

    test('长度不同 → 签名不同（即使取样区间内容一致）', () {
      expect(
        artworkBytesSignature(Uint8List(1024)),
        isNot(artworkBytesSignature(Uint8List(1025))),
      );
    });

    test('大文件只看头尾：尾部变化也能识别', () {
      const int length = 200 * 1024;
      final original = bytesOf(length);
      final modified = Uint8List.fromList(original);
      modified[length - 1] ^= 0xFF;

      expect(
        artworkBytesSignature(original),
        isNot(artworkBytesSignature(modified)),
      );
    });

    test('空字节也能得到稳定签名（不是 null）', () {
      expect(
        artworkBytesSignature(Uint8List(0)),
        artworkBytesSignature(Uint8List(0)),
      );
    });
  });

  group('artworkFileSignature', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vynody_signature_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('路径为空 / 文件不存在 → null', () {
      expect(artworkFileSignature(null), isNull);
      expect(artworkFileSignature(''), isNull);
      expect(
        artworkFileSignature('${tempDir.path}/definitely_missing.jpg'),
        isNull,
      );
    });

    test('文件内容被原地覆盖（长度变化）→ 签名变化', () async {
      final file = File('${tempDir.path}/cover.jpg');
      await file.writeAsBytes(List<int>.filled(32, 1));
      final before = artworkFileSignature(file.path);

      await file.writeAsBytes(List<int>.filled(64, 2));
      final after = artworkFileSignature(file.path);

      expect(before, isNotNull);
      expect(after, isNotNull);
      expect(before, isNot(after));
    });
  });

  group('artworkSignatureOf', () {
    test('有字节时按内容算，忽略文件路径', () {
      final bytes = bytesOf(2048, seed: 7);

      expect(
        artworkSignatureOf(bytes: bytes, filePath: '/nonexistent/cover.jpg'),
        artworkBytesSignature(bytes),
      );
    });

    test('空字节视为「没有字节」，回落到文件签名', () async {
      final tempDir = await Directory.systemTemp.createTemp('vynody_sig_of_');
      addTearDown(() => tempDir.delete(recursive: true));

      final file = File('${tempDir.path}/cover.jpg');
      await file.writeAsBytes(List<int>.filled(16, 3));

      expect(
        artworkSignatureOf(bytes: Uint8List(0), filePath: file.path),
        artworkFileSignature(file.path),
      );
    });

    test('既没字节也没文件 → null（清除封面的信号）', () {
      expect(artworkSignatureOf(bytes: null, filePath: null), isNull);
      expect(artworkSignatureOf(bytes: Uint8List(0), filePath: ''), isNull);
    });
  });
}
