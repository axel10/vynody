import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';

/// 曲库快照递增计数，用来触发 [albumLibraryProvider] 重建（模拟播放 / 扫描）。
class _LibraryRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final _libraryRevisionProvider =
    NotifierProvider<_LibraryRevision, int>(_LibraryRevision.new);

void main() {
  const range = LibraryTimeRange.allTime;

  const song = MusicFile(
    path: '/music/song.flac',
    name: 'song.flac',
    title: 'Song',
    artist: 'Artist',
    album: 'Album',
    durationMillis: 1000,
  );
  const album = AlbumSummary(
    id: 'album::artist',
    title: 'Album',
    artist: 'Artist',
    songs: [song],
    representativeSong: song,
    totalDurationMillis: 1000,
  );

  const addedEntry = LibraryInsightSongEntry(
    song: song,
    playCount: 0,
    createdAt: 1000,
  );

  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [
        albumLibraryProvider.overrideWith((ref) {
          ref.watch(_libraryRevisionProvider);
          return Stream.value(const [album]);
        }),
        recentlyAddedSongsProvider(range).overrideWith(
          (ref) => Stream.value(const [addedEntry]),
        ),
      ],
    );
  }

  test('专辑聚合视图在上游 reload 时沿用旧值，不退回整页 loading', () async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final provider = recentlyAddedAlbumsRankedProvider(range);
    final sub = container.listen(provider, (_, _) {}, fireImmediately: true);
    addTearDown(sub.close);
    await container.pump();
    await Future<void>.delayed(Duration.zero);
    await container.pump();

    final initial = container.read(provider);
    expect(initial.hasValue, isTrue);
    expect(initial.value, hasLength(1));

    // 播放一首歌会写 songs 表并推出新的曲库快照：albums 上游重建进入 reload。
    // 这里必须保留上一次的专辑列表，否则页面会整页闪成加载圈。
    container.read(_libraryRevisionProvider.notifier).bump();

    // 先确认这次重建真的让上游进入了 reload，否则下面的断言就成了空转。
    final albumsDuringReload = container.read(albumLibraryProvider);
    expect(albumsDuringReload.isLoading, isTrue);
    expect(albumsDuringReload.hasValue, isTrue);

    await container.pump();

    final reloaded = container.read(provider);
    expect(reloaded.isLoading, isFalse, reason: 'reload 不应把整页退回加载圈');
    expect(reloaded.hasValue, isTrue);
    expect(reloaded.value, hasLength(1));
  });
}
