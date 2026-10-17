import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/genre_naming.dart';

void main() {
  group('normalizeGenreKey', () {
    test('大小写与首尾空格收敛到同一个键', () {
      expect(normalizeGenreKey('Rock'), normalizeGenreKey('rock'));
      expect(normalizeGenreKey('  ROCK  '), 'rock');
    });

    test('& 与 and 等价', () {
      expect(normalizeGenreKey('R&B'), 'r and b');
      expect(normalizeGenreKey('R and B'), 'r and b');
      expect(normalizeGenreKey('r & b'), 'r and b');
    });

    test('连字符、下划线、斜杠视为分隔符', () {
      expect(normalizeGenreKey('Hip-Hop'), 'hip hop');
      expect(normalizeGenreKey('hip_hop'), 'hip hop');
      expect(normalizeGenreKey('Pop / Rock'), 'pop rock');
    });

    test('全角空格与全角标点归一', () {
      expect(normalizeGenreKey('华语\u3000流行'), '华语 流行');
      expect(normalizeGenreKey('摇滚，流行'), '摇滚 流行');
    });

    test('连字符与连写收敛到同一个键', () {
      expect(normalizeGenreKey('J-Pop'), normalizeGenreKey('JPop'));
      expect(normalizeGenreKey('K-Pop'), normalizeGenreKey('KPop'));
      expect(normalizeGenreKey('Hip-Hop'), normalizeGenreKey('HipHop'));
      expect(normalizeGenreKey('Lo-Fi'), normalizeGenreKey('Lofi'));
      expect(normalizeGenreKey('J-Pop'), 'j pop');
    });

    test('R&B 的所有写法（含无分隔的 RnB）收敛到同一个键', () {
      for (final raw in ['R&B', 'R and B', 'r & b', 'RnB', 'R B']) {
        expect(normalizeGenreKey(raw), 'r and b', reason: raw);
      }
    });

    test('空串与纯空白返回空键', () {
      expect(normalizeGenreKey(''), '');
      expect(normalizeGenreKey('   '), '');
    });
  });

  group('pickGenreDisplayName', () {
    test('全小写英文首字母大写', () {
      expect(pickGenreDisplayName('rock'), 'Rock');
      expect(pickGenreDisplayName('indie rock'), 'Indie Rock');
    });

    test('已含大写字母的原样保留', () {
      expect(pickGenreDisplayName('R&B'), 'R&B');
      expect(pickGenreDisplayName('Hip-Hop'), 'Hip-Hop');
    });

    test('常见缩写美化', () {
      expect(pickGenreDisplayName('rnb'), 'R&B');
      expect(pickGenreDisplayName('edm'), 'EDM');
      expect(pickGenreDisplayName('lofi'), 'Lo-Fi');
    });

    test('中文流派名原样返回', () {
      expect(pickGenreDisplayName('华语流行'), '华语流行');
      expect(pickGenreDisplayName('摇滚'), '摇滚');
    });
  });
}
