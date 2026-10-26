import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/widgets/album_sections.dart';

MusicFile _song({
  required String path,
  required String title,
  String? artist,
  String? albumArtist,
  String? album,
  int? trackNumber,
  int? durationMillis,
}) {
  return MusicFile(
    path: path,
    name: '$title.mp3',
    title: title,
    artist: artist,
    albumArtist: albumArtist,
    album: album,
    trackNumber: trackNumber,
    durationMillis: durationMillis,
  );
}

void main() {
  // 两张专辑，各 3 首，用于验证分组保整与按曲目裁剪两条分支。
  final songs = <MusicFile>[
    _song(
      path: '/a/1.mp3',
      title: 'Come Together',
      artist: 'The Beatles',
      albumArtist: 'The Beatles',
      album: 'Abbey Road',
      trackNumber: 1,
      durationMillis: 1000,
    ),
    _song(
      path: '/a/2.mp3',
      title: 'Something',
      artist: 'The Beatles',
      albumArtist: 'The Beatles',
      album: 'Abbey Road',
      trackNumber: 2,
      durationMillis: 2000,
    ),
    _song(
      path: '/a/3.mp3',
      title: 'Medley',
      artist: 'The Beatles',
      albumArtist: 'The Beatles',
      album: 'Abbey Road',
      trackNumber: 3,
      durationMillis: 3000,
    ),
    _song(
      path: '/b/1.mp3',
      title: 'Time',
      artist: 'Pink Floyd',
      albumArtist: 'Pink Floyd',
      album: 'The Dark Side of the Moon',
      trackNumber: 1,
      durationMillis: 4000,
    ),
    _song(
      path: '/b/2.mp3',
      title: 'Money',
      artist: 'Pink Floyd',
      albumArtist: 'Pink Floyd',
      album: 'The Dark Side of the Moon',
      trackNumber: 2,
      durationMillis: 5000,
    ),
  ];

  final sections = buildAlbumSections(songs, 'Unknown Album');

  test('空词原样返回同一个列表实例', () {
    expect(identical(filterAlbumSections(sections, ''), sections), isTrue);
    expect(identical(filterAlbumSections(sections, '   '), sections), isTrue);
  });

  test('命中专辑名时保留整张专辑的全部曲目', () {
    final result = filterAlbumSections(sections, 'abbey');

    expect(result, hasLength(1));
    expect(result.single.title, 'Abbey Road');
    expect(result.single.songs, hasLength(3));
  });

  test('只命中曲目时该专辑只保留命中曲目，分组标题仍是专辑名', () {
    final result = filterAlbumSections(sections, 'money');

    expect(result, hasLength(1));
    expect(result.single.title, 'The Dark Side of the Moon');
    expect(result.single.songs.map((s) => s.path), ['/b/2.mp3']);
  });

  test('命中专辑艺术家时同样保留整张专辑', () {
    final result = filterAlbumSections(sections, 'pink floyd');

    expect(result, hasLength(1));
    expect(result.single.title, 'The Dark Side of the Moon');
    expect(result.single.songs, hasLength(2));
  });

  test('过滤后每组 startIndex 按新列表连续重算', () {
    final result = filterAlbumSections(sections, 'e');

    // 两组的曲目都要被裁剪，逐组核对起止下标能否覆盖整段可见列表。
    var expectedStart = 0;
    for (final section in result) {
      expect(section.startIndex, expectedStart);
      expectedStart += section.songs.length;
    }
    expect(expectedStart, result.fold<int>(0, (sum, s) => sum + s.songs.length));
  });

  test('代表曲目不在命中集合里时退回首曲，避免取到被过滤掉的歌', () {
    final result = filterAlbumSections(sections, 'money');
    final section = result.single;

    expect(section.representativeSong.path, '/b/2.mp3');
    expect(section.representativeSong.path, section.songs.first.path);
  });

  test('过滤后的时长按命中曲目重算', () {
    final result = filterAlbumSections(sections, 'money');

    expect(result.single.totalDurationMillis, 5000);
  });

  test('完全没有命中时返回空列表', () {
    expect(filterAlbumSections(sections, 'zzz'), isEmpty);
  });
}
