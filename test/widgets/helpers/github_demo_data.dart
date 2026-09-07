import 'package:vynody/player/library/library_insights_service.dart';
import 'macos_screenshot_harness.dart';

final List<DemoItem> githubDemoItems = [
  const DemoItem(
    filename: 'The Weeknd - Starboy.mp3',
    title: 'Starboy',
    artist: 'The Weeknd',
    album: 'Starboy',
    durationMs: 230453,
    coverPath: 'test_covers/github/The Weeknd - Starboy.webp',
  ),
  const DemoItem(
    filename: 'Michael Jackson - Billie Jean.mp3',
    title: 'Billie Jean',
    artist: 'Michael Jackson',
    album: 'Thriller (Special Edition)',
    durationMs: 294000,
    coverPath: 'test_covers/github/Michael Jackson - Thriller (Special Edition).webp',
  ),
  const DemoItem(
    filename: 'Taylor Swift - Anti-Hero.mp3',
    title: 'Anti-Hero',
    artist: 'Taylor Swift',
    album: 'Midnights (3am Edition)',
    durationMs: 200690,
    coverPath: 'test_covers/github/Taylor Swift - Midnights (3am Edition).webp',
  ),
  const DemoItem(
    filename: 'Alan Walker - The Spectre.mp3',
    title: 'The Spectre',
    artist: 'Alan Walker',
    album: 'The Spectre',
    durationMs: 193266,
    coverPath: 'test_covers/github/Alan Walker - The Spectre.webp',
  ),
  const DemoItem(
    filename: 'Bruno Mars - Just the Way You Are.mp3',
    title: 'Just the Way You Are',
    artist: 'Bruno Mars',
    album: 'Doo-Wops & Hooligans',
    durationMs: 220734,
    coverPath: 'test_covers/github/Bruno Mars - Doo-Wops & Hooligans.webp',
  ),
  const DemoItem(
    filename: 'OneRepublic - Counting Stars.mp3',
    title: 'Counting Stars',
    artist: 'OneRepublic',
    album: 'Native',
    durationMs: 257000,
    coverPath: 'test_covers/github/OneRepublic - Native.webp',
  ),
  const DemoItem(
    filename: 'Various Artists - City of Stars.mp3',
    title: 'City of Stars',
    artist: 'Various Artists',
    album: 'La La Land [Original Motion Picture Soundtrack]',
    durationMs: 149000,
    coverPath: 'test_covers/github/Various Artists - La La Land [Original Motion Picture Soundtrack].webp',
  ),
  const DemoItem(
    filename: 'The Weeknd - Blinding Lights.mp3',
    title: 'Blinding Lights',
    artist: 'The Weeknd',
    album: 'After Hours',
    durationMs: 200040,
    coverPath: 'test_covers/github/The Weeknd - After Hours.webp',
  ),
  const DemoItem(
    filename: 'BAAD - Kimi ga Suki da to Sakebitai.mp3',
    title: '君が好きだと叫びたい',
    artist: 'BAAD',
    album: 'TV Animation SLAM DUNK Opening & Ending Theme Songs',
    durationMs: 232000,
    coverPath: 'test_covers/github/BAAD - TV Animation SLAM DUNK Opening & Ending Theme Songs.webp',
  ),
  const DemoItem(
    filename: 'TWO-MIX - JUST COMMUNICATION.mp3',
    title: 'JUST COMMUNICATION',
    artist: 'TWO-MIX',
    album: 'Gundam Wing',
    durationMs: 258000,
    coverPath: 'test_covers/github/TWO-MIX - Gundam Wing.webp',
  ),
  const DemoItem(
    filename: 'TWO-MIX - RHYTHM EMOTION.mp3',
    title: 'RHYTHM EMOTION',
    artist: 'TWO-MIX',
    album: '新機動戦記ガンダムW OPERATION S',
    durationMs: 236000,
    coverPath: 'test_covers/github/TWO-MIX - 新機動戦記ガンダムW OPERATION S.webp',
  ),
  const DemoItem(
    filename: 'AC_DC - Back In Black.mp3',
    title: 'Back In Black',
    artist: 'AC/DC',
    album: 'Sight & Sound Collection',
    durationMs: 255000,
    coverPath: 'test_covers/github/AC_DC - Sight & Sound Collection.webp',
  ),
  const DemoItem(
    filename: 'The Cure - Lovesong.mp3',
    title: 'Lovesong',
    artist: 'The Cure',
    album: 'Disintegration (Deluxe Edition)',
    durationMs: 212000,
    coverPath: 'test_covers/github/The Cure - Disintegration (Deluxe Edition).webp',
  ),
  const DemoItem(
    filename: 'USHER - Yeah!.mp3',
    title: 'Yeah! (feat. Lil Jon & Ludacris)',
    artist: 'USHER',
    album: 'Confessions (20th Anniversary Edition)',
    durationMs: 250000,
    coverPath: 'test_covers/github/USHER - Confessions (20th Anniversary Edition).webp',
  ),
  const DemoItem(
    filename: 'Usher - U Got It Bad.mp3',
    title: 'U Got It Bad',
    artist: 'Usher',
    album: '8701',
    durationMs: 247000,
    coverPath: 'test_covers/github/Usher - 8701.webp',
  ),
  const DemoItem(
    filename: 'War - Low Rider.mp3',
    title: 'Low Rider',
    artist: 'War',
    album: 'Why Can\'t We Be Friends',
    durationMs: 191000,
    coverPath: 'test_covers/github/War - Why Can\'t We Be Friends.webp',
  ),
  const DemoItem(
    filename: 'Shania Twain - You\'re Still The One.mp3',
    title: 'You\'re Still The One',
    artist: 'Shania Twain',
    album: 'Little Miss Twain',
    durationMs: 213000,
    coverPath: 'test_covers/github/Shania Twain - Little Miss Twain.webp',
  ),
  const DemoItem(
    filename: 'Taylor Swift - willow.mp3',
    title: 'willow',
    artist: 'Taylor Swift',
    album: 'evermore',
    durationMs: 214000,
    coverPath: 'test_covers/github/Taylor Swift - evermore.webp',
  ),
  const DemoItem(
    filename: 'The Weeknd - Sacrifice.mp3',
    title: 'Sacrifice',
    artist: 'The Weeknd',
    album: 'Dawn FM (Explicit)',
    durationMs: 188000,
    coverPath: 'test_covers/github/The Weeknd - Dawn FM (Explicit).webp',
  ),
  const DemoItem(
    filename: 'The Weeknd - Timeless.mp3',
    title: 'Timeless',
    artist: 'The Weeknd',
    album: 'Hurry Up Tomorrow',
    durationMs: 256000,
    coverPath: 'test_covers/github/The Weeknd - Hurry Up Tomorrow.webp',
  ),
  const DemoItem(
    filename: 'Bruno Mars - Runaway Baby.mp3',
    title: 'Runaway Baby',
    artist: 'Bruno Mars',
    album: 'Best Roadtrip Bangers',
    durationMs: 147000,
    coverPath: 'test_covers/github/Bruno Mars - Best Roadtrip Bangers.webp',
  ),
  const DemoItem(
    filename: 'OneRepublic - Someday.mp3',
    title: 'Someday',
    artist: 'OneRepublic',
    album: 'Human',
    durationMs: 187000,
    coverPath: 'test_covers/github/OneRepublic - Human.webp',
  ),
  const DemoItem(
    filename: 'OneRepublic - Kids.mp3',
    title: 'Kids',
    artist: 'OneRepublic',
    album: 'Oh My My (Deluxe)',
    durationMs: 238000,
    coverPath: 'test_covers/github/OneRepublic - Oh My My (Deluxe).webp',
  ),
  const DemoItem(
    filename: 'Electro-Light - Symbolism.mp3',
    title: 'Symbolism',
    artist: 'Electro-Light',
    album: 'Symbolism',
    durationMs: 291000,
    coverPath: 'test_covers/github/Electro-Light - Symbolism.webp',
  ),
  const DemoItem(
    filename: 'Tobu - Sunburst.mp3',
    title: 'Sunburst',
    artist: 'Tobu, Itro',
    album: 'Best of Tobu 2023 - Ultimate Electronic Video Gaming Mix',
    durationMs: 190000,
    coverPath: 'test_covers/github/Tobu, Itro - Best of Tobu 2023 - Ultimate Electronic Video Gaming Mix.webp',
  ),
  const DemoItem(
    filename: 'Steerner & Martell - Sun.mp3',
    title: 'Sun',
    artist: 'Steerner & Martell',
    album: 'Sun',
    durationMs: 254000,
    coverPath: 'test_covers/github/Steerner & Martell - Sun.webp',
  ),
  const DemoItem(
    filename: 'Capchii - Pic and Pop!.mp3',
    title: 'Pic and Pop!',
    artist: 'Capchii',
    album: 'Pic and_ Pop!',
    durationMs: 172000,
    coverPath: 'test_covers/github/Capchii - Pic and_ Pop!.webp',
  ),
  const DemoItem(
    filename: 'Yorushika - Hitchcock.mp3',
    title: 'ヒッチコック',
    artist: 'Yorushika',
    album: 'Makeinu ni Encore wa Iranai',
    durationMs: 222000,
    coverPath: 'test_covers/github/Yorushika - Makeinu ni Encore wa Iranai.webp',
  ),
  const DemoItem(
    filename: 'Tohma - Kowloon Retro.mp3',
    title: '九龍レトロ',
    artist: 'トーマ,三味P',
    album: '九龍レトロ',
    durationMs: 193000,
    coverPath: 'test_covers/github/トーマ,三味P - 九龍レトロ.webp',
  ),
  const DemoItem(
    filename: 'Hachi - Suna no Wakusei.mp3',
    title: '砂の惑星',
    artist: 'ハチ,びび',
    album: '砂の惑星',
    durationMs: 239000,
    coverPath: 'test_covers/github/ハチ,びび - 砂の惑星.webp',
  ),
  const DemoItem(
    filename: 'Masarada - Liar Dancer.mp3',
    title: 'ライアーダンサー',
    artist: 'マサラダ',
    album: 'ライアーダンサー',
    durationMs: 184000,
    coverPath: 'test_covers/github/マサラダ - ライアーダンサー.webp',
  ),
  const DemoItem(
    filename: 'Akizuki Shisui - Tariki Hongan!.mp3',
    title: '他力本願！',
    artist: '秋月紫水',
    album: '他力本願！',
    durationMs: 168000,
    coverPath: 'test_covers/github/秋月紫水 - 他力本願！.webp',
  ),
];

class GithubLibraryDataset {
  final List<MusicFile> songs;
  final List<AlbumSummary> albums;
  final Map<String, SongMetadata> metadataMap;
  final MusicFolder rootFolder;
  final List<LibraryInsightSongEntry> insightEntries;

  GithubLibraryDataset({
    required this.songs,
    required this.albums,
    required this.metadataMap,
    required this.rootFolder,
    required this.insightEntries,
  });
}

GithubLibraryDataset createGithubLibraryDataset({
  String basePath = '/Music/Hi-Res Library',
}) {
  final demoData = createDemoLibraryData(
    basePath: basePath,
    demoItems: githubDemoItems,
  );

  final popArtists = {'The Weeknd', 'Michael Jackson', 'Taylor Swift', 'Bruno Mars', 'OneRepublic'};
  final edmArtists = {'Alan Walker', 'Tobu, Itro', 'Electro-Light', 'Steerner & Martell', 'Capchii'};
  final animeArtists = {'BAAD', 'TWO-MIX', 'Yorushika', 'トーマ,三味P', 'ハチ,びび', 'マサラダ', '秋月紫水'};
  final classicArtists = {'AC/DC', 'The Cure', 'USHER', 'Usher', 'War', 'Shania Twain', 'Various Artists'};

  final popFolder = MusicFolder(
    path: '$basePath/Pop & Contemporary',
    name: 'Pop & Contemporary',
    files: demoData.songs.where((s) => popArtists.contains(s.artist)).toList(),
  );

  final edmFolder = MusicFolder(
    path: '$basePath/Electronic & Gaming',
    name: 'Electronic & Gaming',
    files: demoData.songs.where((s) => edmArtists.contains(s.artist)).toList(),
  );

  final animeFolder = MusicFolder(
    path: '$basePath/Anime & ACG Favorites',
    name: 'Anime & ACG Favorites',
    files: demoData.songs.where((s) => animeArtists.contains(s.artist)).toList(),
  );

  final classicsFolder = MusicFolder(
    path: '$basePath/Classics & Soundtracks',
    name: 'Classics & Soundtracks',
    files: demoData.songs.where((s) => classicArtists.contains(s.artist)).toList(),
  );

  final rootFolder = MusicFolder(
    path: basePath,
    name: 'Hi-Res Music Library',
    files: demoData.songs,
    subFolders: [popFolder, edmFolder, animeFolder, classicsFolder],
  );

  final insightEntries = demoData.songs.take(16).toList().asMap().entries.map((entry) {
    final idx = entry.key;
    final song = entry.value;
    return LibraryInsightSongEntry(
      song: song,
      playCount: 58 - idx * 3,
      lastPlayedAt: DateTime.now().millisecondsSinceEpoch - idx * 2800000,
      createdAt: DateTime.now().millisecondsSinceEpoch - (idx + 1) * 86400000,
    );
  }).toList();

  return GithubLibraryDataset(
    songs: demoData.songs,
    albums: demoData.albums,
    metadataMap: demoData.metadataMap,
    rootFolder: rootFolder,
    insightEntries: insightEntries,
  );
}
