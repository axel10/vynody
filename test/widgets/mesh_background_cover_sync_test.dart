import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 网格背景（「动态流变 v2」）的封面纹理必须能感知「同一首歌换了封面」。
///
/// 这是一条源码契约测试：`MeshFlowBackground` 是 ConsumerStatefulWidget，
/// 依赖 mesh_flow 的 GPU 着色器，widget 测试跑不起来；而破坏这条不变量只需要
/// 加回一行「已经有纹理就提前返回」，线上现象却是换封面 / 清除封面后背景
/// 一直停在旧图上，跟轮播封面不一致。
void main() {
  String readMeshBackgroundSource() =>
      File('lib/widgets/dynamic_mesh_background.dart').readAsStringSync();

  String syncCoverSourceBody(String source) {
    final start = source.indexOf('void _syncCoverSource(');
    expect(
      start,
      greaterThanOrEqualTo(0),
      reason: '_syncCoverSource 被改名或删除，请同步更新本测试',
    );
    final end = source.indexOf('Uint8List? _resolveCoverBytes(', start);
    expect(end, greaterThan(start), reason: '定位不到 _syncCoverSource 的函数体');
    return source.substring(start, end);
  }

  test('封面来源按内容签名判定，而不是「已有纹理就不再解析」', () {
    final body = syncCoverSourceBody(readMeshBackgroundSource());

    expect(
      body.contains('if (_coverBytes != null || _coverImage != null) return;'),
      isFalse,
      reason: '这个提前返回会让同一首歌换封面 / 清封面后，网格纹理永远停在旧图上',
    );
    expect(
      body.contains('artworkSignatureOf('),
      isTrue,
      reason: '封面变化必须按内容签名判断：path 不变而内容变了（标签补全）是最常见的情形',
    );
    expect(
      body.contains('_coverSignature'),
      isTrue,
      reason: '缺少签名比对，每次 rebuild 都会重启 MeshFlow 的过渡动画',
    );
  });

  test('coverKey 带上签名，FileImage 相等时也能触发纹理重载', () {
    final source = readMeshBackgroundSource();
    final start = source.indexOf('MeshFlow(');
    expect(start, greaterThanOrEqualTo(0));

    final end = source.indexOf('palette:', start);
    expect(end, greaterThan(start));

    final meshFlowArgs = source.substring(start, end);
    expect(
      meshFlowArgs.contains('_coverSignature'),
      isTrue,
      reason: 'coverKey 只带曲目路径时，原地覆盖封面文件（FileImage == 仍相等）'
          '不会被 MeshFlow 判定为封面变化',
    );
  });
}
