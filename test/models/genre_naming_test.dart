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

    test('空串与纯空白返回空键', () {
      expect(normalizeGenreKey(''), '');
      expect(normalizeGenreKey('   '), '');
    });
  });

  group('matchGenreAssetKey', () {
    test('标准流派名精确命中', () {
      expect(matchGenreAssetKey('Rock'), 'rock');
      expect(matchGenreAssetKey('hip-hop'), 'hip_hop');
      expect(matchGenreAssetKey('R&B'), 'rnb');
      expect(matchGenreAssetKey('Jazz'), 'jazz');
    });

    test('长尾写法落到正确的大类', () {
      expect(matchGenreAssetKey('Alternative Rock'), 'indie');
      expect(matchGenreAssetKey('Pop Punk'), 'punk');
      expect(matchGenreAssetKey('Folk Rock'), 'folk');
      expect(matchGenreAssetKey('Dance Pop'), 'pop');
      expect(matchGenreAssetKey('K-Pop'), 'pop');
      expect(matchGenreAssetKey('House'), 'edm');
      expect(matchGenreAssetKey('Electronica'), 'electronic');
    });

    test('原声优先于摇滚，不会被 soundtrack 里的 rock 带偏', () {
      expect(matchGenreAssetKey('Soundtrack'), 'soundtrack');
      expect(matchGenreAssetKey('Original Soundtrack'), 'soundtrack');
      expect(matchGenreAssetKey('Rock Soundtrack'), 'soundtrack');
    });

    test('中文流派名可识别', () {
      expect(matchGenreAssetKey('华语流行'), 'pop');
      expect(matchGenreAssetKey('经典摇滚'), 'rock');
      expect(matchGenreAssetKey('爵士'), 'jazz');
      expect(matchGenreAssetKey('雷鬼'), 'reggae');
    });

    test('未命中的流派回落到 default 图且没有图标', () {
      expect(matchGenreAssetKey('BGM'), isNull);
      expect(genreImageAssetKey('BGM'), kFallbackGenreAssetKey);
      expect(genreIconAssetKey('BGM'), isNull);
    });

    test('每个命中的键都在已知资源清单内', () {
      for (final raw in <String>[
        'Rock',
        'hip-hop',
        'R&B',
        'Jazz',
        'Classical',
        'Ambient',
        'Lo-Fi',
        'Soundtrack',
        'Latin',
        'Punk',
        'Metal',
        'Funk',
        'Soul',
        'Reggae',
        'Blues',
        'Country',
        'Folk',
        'Indie',
        'Electronic',
        'EDM',
        'Pop',
        'Anime',
      ]) {
        final key = matchGenreAssetKey(raw);
        if (key == null) continue;
        expect(
          kGenreAssetKeys.contains(key),
          isTrue,
          reason: '$raw 命中了未登记的资源键 $key',
        );
      }
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
