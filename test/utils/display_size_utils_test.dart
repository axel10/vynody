import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/utils/layout_constants.dart';

void main() {
  group('logicalDisplaySizeFrom', () {
    test('Linux 口径：Display.size 已是逻辑像素，不再除以 dpr', () {
      // 1920x1200 @2x 的 HiDPI 屏，GTK 上报 1920x1200（application pixels）
      final Size size = logicalDisplaySizeFrom(
        const Size(1920, 1200),
        2.0,
        sizeIsLogical: true,
      );

      expect(size, const Size(1920, 1200));
    });

    test('Windows / macOS / 移动端口径：物理像素需除以 dpr', () {
      final Size size = logicalDisplaySizeFrom(
        const Size(3840, 2400),
        2.0,
        sizeIsLogical: false,
      );

      expect(size, const Size(1920, 1200));
    });

    test('dpr 非法（0 / 负数 / NaN）时原样返回，不应出现除零崩溃', () {
      const Size raw = Size(1920, 1200);

      expect(logicalDisplaySizeFrom(raw, 0, sizeIsLogical: false), raw);
      expect(logicalDisplaySizeFrom(raw, -1, sizeIsLogical: false), raw);
      expect(logicalDisplaySizeFrom(raw, double.nan, sizeIsLogical: false), raw);
    });

    test('dpr = 1.0 时两种口径结果一致', () {
      const Size raw = Size(2560, 1440);

      expect(logicalDisplaySizeFrom(raw, 1.0, sizeIsLogical: true), raw);
      expect(logicalDisplaySizeFrom(raw, 1.0, sizeIsLogical: false), raw);
    });

    test('回归：HiDPI Linux 不再把 1920x1200 误算成 960x600', () {
      // 修复前 display.size.height / dpr = 1200 / 2 = 600，命中 <= 600 兜底，
      // 横屏歌词模式左侧控件区因此被压扁。
      final Size linuxSize = logicalDisplaySizeFrom(
        const Size(1920, 1200),
        2.0,
        sizeIsLogical: true,
      );

      expect(linuxSize.height, isNot(600.0));
      expect(linuxSize.height, 1200.0);
    });
  });

  group('displaySizeReportedInLogicalPixels', () {
    test('当前测试宿主平台口径判断可正常求值', () {
      // 仅验证 getter 不抛异常；具体真假取决于运行平台。
      expect(displaySizeReportedInLogicalPixels, isA<bool>());
    });
  });
}
