import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/utils/time_format_utils.dart';

void main() {
  group('TimeFormatUtils', () {
    test('formatDuration with mm:ss', () {
      expect(
        TimeFormatUtils.formatDuration(const Duration(minutes: 3, seconds: 25)),
        '3:25',
      );
      expect(
        TimeFormatUtils.formatDuration(const Duration(seconds: 5)),
        '0:05',
      );
    });

    test('formatDuration with hh:mm:ss', () {
      expect(
        TimeFormatUtils.formatDuration(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '1:02:03',
      );
    });

    test('formatDuration null fallback', () {
      expect(TimeFormatUtils.formatDuration(null), '--:--');
      expect(TimeFormatUtils.formatDuration(null, fallback: ''), '');
    });

    test('formatMs works correctly', () {
      expect(TimeFormatUtils.formatMs(65000), '1:05');
      expect(TimeFormatUtils.formatMs(null), '--:--');
    });

    test('extension on Duration and int', () {
      expect(const Duration(minutes: 4, seconds: 12).toFormattedString(), '4:12');
      expect(125000.toFormattedDuration(), '2:05');
      expect((null as int?).toFormattedDuration(), '--:--');
      expect((null as Duration?).toFormattedString(fallback: 'none'), 'none');
    });
  });
}
