import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/genre_summary.dart';

GenreSummary _genre(String name, int songCount) =>
    GenreSummary(name: name, songCount: songCount, songs: const []);

void main() {
  group('dedupeGenresByCoverArt', () {
    test('共用同一封面的流派只保留一个', () {
      // Rap / Trap / Drill 都落到 hip-hop.webp
      final result = dedupeGenresByCoverArt(<GenreSummary>[
        _genre('Hip-Hop', 10),
        _genre('Rap', 3),
        _genre('Trap', 5),
      ]);

      expect(result, hasLength(1));
      expect(result.single.name, 'Hip-Hop');
      expect(result.single.imageAssetPath, endsWith('hip-hop.webp'));
    });

    test('兜底封面的流派只出现一次', () {
      // 三个都命中不了规则，共用 music.webp
      final result = dedupeGenresByCoverArt(<GenreSummary>[
        _genre('BGM', 2),
        _genre('Unknown', 9),
        _genre('卡拉OK', 4),
      ]);

      expect(result, hasLength(1));
      expect(result.single.name, 'Unknown');
      expect(result.single.songCount, 9);
    });

    test('代表项取曲目最多的那个，位置沿用首次出现处', () {
      final result = dedupeGenresByCoverArt(<GenreSummary>[
        _genre('Rap', 3),
        _genre('Rock', 1),
        _genre('Trap', 5),
      ]);

      expect(result.map((g) => g.name).toList(), <String>['Trap', 'Rock']);
    });

    test('不同封面互不影响且保持原顺序', () {
      final result = dedupeGenresByCoverArt(<GenreSummary>[
        _genre('Pop', 1),
        _genre('Rock', 2),
        _genre('Jazz', 3),
      ]);

      expect(result.map((g) => g.name).toList(), <String>['Pop', 'Rock', 'Jazz']);
    });

    test('兜底封面与专属封面不会互相吞并', () {
      final result = dedupeGenresByCoverArt(<GenreSummary>[
        _genre('Pop', 1),
        _genre('BGM', 2),
        _genre('Karaoke', 3),
      ]);

      expect(result.map((g) => g.name).toList(), <String>['Pop', 'Karaoke']);
    });

    test('兜底封面固定排在最后，即使它最先出现', () {
      final result = dedupeGenresByCoverArt(<GenreSummary>[
        _genre('Unknown', 9),
        _genre('Pop', 1),
        _genre('Rock', 2),
      ]);

      expect(
        result.map((g) => g.name).toList(),
        <String>['Pop', 'Rock', 'Unknown'],
      );
      expect(result.last.usesFallbackCover, isTrue);
      expect(result.take(2).every((g) => !g.usesFallbackCover), isTrue);
    });

    test('空输入返回空列表', () {
      expect(dedupeGenresByCoverArt(const <GenreSummary>[]), isEmpty);
    });
  });
}
