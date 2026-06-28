import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/utils/linux_mount_helper.dart';

void main() {
  group('LinuxMountHelper.isLabelMatch', () {
    test('exact match', () {
      expect(LinuxMountHelper.isLabelMatch('新加卷', '新加卷'), isTrue);
      expect(LinuxMountHelper.isLabelMatch('Music', 'Music'), isTrue);
    });

    test('suffix match with simple digit suffix', () {
      expect(LinuxMountHelper.isLabelMatch('新加卷1', '新加卷'), isTrue);
      expect(LinuxMountHelper.isLabelMatch('新加卷2', '新加卷'), isTrue);
      expect(LinuxMountHelper.isLabelMatch('新加卷12', '新加卷'), isTrue);
    });

    test('suffix match with space and digit suffix', () {
      expect(LinuxMountHelper.isLabelMatch('新加卷 1', '新加卷'), isTrue);
      expect(LinuxMountHelper.isLabelMatch('新加卷 2', '新加卷'), isTrue);
    });

    test('suffix match with underscore/dash and digit suffix', () {
      expect(LinuxMountHelper.isLabelMatch('新加卷_1', '新加卷'), isTrue);
      expect(LinuxMountHelper.isLabelMatch('新加卷-2', '新加卷'), isTrue);
    });

    test('no match for different labels', () {
      expect(LinuxMountHelper.isLabelMatch('新加卷', '64WinXP'), isFalse);
      expect(LinuxMountHelper.isLabelMatch('64WinXP', '新加卷'), isFalse);
    });

    test('no match for non-numeric suffix', () {
      expect(LinuxMountHelper.isLabelMatch('新加卷备份', '新加卷'), isFalse);
      expect(LinuxMountHelper.isLabelMatch('新加卷 1a', '新加卷'), isFalse);
    });
  });
}
