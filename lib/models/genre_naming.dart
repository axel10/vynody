/// 流派名称归一化与资源键映射。
///
/// 流派字段在各家标签格式里都是完全自由的文本：同一个流派可能以
/// `Rock` / `rock` / `ROCK` / `Alternative Rock` / `华语摇滚` 出现，
/// 远程源（Navidrome / Jellyfin / SMB / WebDAV）之间还各有一套写法。
/// 直接拿原始字符串当聚合键，一个流派会在库里裂成好几份；
/// 直接拿它去找展示图，绝大多数流派又会掉进兜底图。
///
/// 这里提供三层能力，彼此独立：
///
/// 1. [normalizeGenreKey] —— 聚合键，只用于分组与相等判断，不展示。
/// 2. [pickGenreDisplayName] —— 展示名，保留用户语言和大写习惯。
/// 3. [genreImageAssetKey] / [genreIconAssetKey] —— 资源键。
library;

/// 兜底资源键：没有命中任何规则时使用的通用图（`music.webp`）。
const String kFallbackGenreAssetKey = 'music';

/// 全部有专属图的流派资源键。
///
/// 与 `assets/images/genre/webp/` 下的文件名**逐字一致**（含连字符），
/// 拼路径时不再做任何转换，改名漏改一处就会立刻 404。
/// 图标不保证同名，见 [_iconKeyByImageKey]。
const List<String> kGenreAssetKeys = <String>[
  'ambient',
  'anime',
  'blues',
  'classical',
  'country',
  'edm',
  'electronic',
  'folk',
  'funk',
  'hip-hop',
  'indie',
  'j-pop',
  'jazz',
  'k-pop',
  'latin',
  'lo-fi',
  'metal',
  'pop',
  'punk',
  'r-b',
  'reggae',
  'rock',
  'soul',
  'soundtrack',
];

/// 「连字符 / 空格 / 连写」三种写法的等价表。
///
/// 键是 [normalizeGenreKey] 文本归一化结果**去掉全部空格**后的形态，
/// 值是规范聚合键。只收 [ _acronymDisplays ] 里已被认定为「同一流派多种
/// 写法」的组，不做同义词合并（`Rap` 归到 `Hip-Hop` 这类由资源键层负责）。
///
/// 为什么需要这一层：标点归一后 `J-Pop` 变成 `j pop`、`JPop` 仍是 `jpop`，
/// 两者键不同就会在库里裂成两个条目；而 [pickGenreDisplayName] 又会把两条
/// 都美化成 `J-Pop`，列表里看起来就是同一个流派重复出现了两次。
const Map<String, String> _genreKeyEquivalents = <String, String>{
  'jpop': 'j pop',
  'kpop': 'k pop',
  'hiphop': 'hip hop',
  'lofi': 'lo fi',
  'rnb': 'r and b',
  'rb': 'r and b',
  'randb': 'r and b',
};

/// 把流派原始文本收敛成稳定的聚合键。
///
/// 规则：小写化 → 全角转半角 → 撇号删除 → `&`/`+` 改写为 `and`
/// → 其余标点视为分隔符 → 折叠空白 → 查 [_genreKeyEquivalents] 合并连写差异。
///
/// 因此 `R&B`、`R and B`、`RnB` 会落到同一个键 `r and b`，
/// `J-Pop` 与 `JPop` 会落到同一个键 `j pop`。
String normalizeGenreKey(String raw) {
  if (raw.isEmpty) return '';

  var s = raw.toLowerCase();
  // 全角空格与全角符号 → 半角
  s = s.replaceAll('\u3000', ' ');
  s = s.replaceAll('＆', '&');
  s = s.replaceAll('＋', '+');
  // 撇号直接删除，避免 rock'n'roll 被切成三段
  s = s.replaceAll(RegExp(r"['\u2018\u2019`]"), '');
  // & 与 + 表示并列关系
  s = s.replaceAll(RegExp(r'[&+]'), ' and ');
  // 其余标点统一当分隔符
  s = s.replaceAll(
    RegExp(r'[-_/\\|,;:.·、，。；：（）()\[\]{}<>《》「」“”"!?！？~]'),
    ' ',
  );
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 连写与带分隔符的写法收敛到同一个聚合键（见 _genreKeyEquivalents）
  return _genreKeyEquivalents[s.replaceAll(' ', '')] ?? s;
}

/// 已知缩写的美化写法，仅在原文全为小写时生效。
const Map<String, String> _acronymDisplays = <String, String>{
  'r&b': 'R&B',
  'r & b': 'R&B',
  'rnb': 'R&B',
  'hip hop': 'Hip-Hop',
  'hiphop': 'Hip-Hop',
  'edm': 'EDM',
  'lofi': 'Lo-Fi',
  'lo-fi': 'Lo-Fi',
  'jpop': 'J-Pop',
  'j-pop': 'J-Pop',
  'kpop': 'K-Pop',
  'k-pop': 'K-Pop',
  'ost': 'OST',
  'idm': 'IDM',
  'acg': 'ACG',
  'bgm': 'BGM',
  'dnb': 'DnB',
};

/// 在一组等价写法里挑一个可读的展示名。
///
/// - 原文已含大写字母（`R&B`、`Hip-Hop`）：原样返回，尊重标签作者的排版；
/// - 含非 ASCII 字符（中文、日文等）：原样返回，不做大小写转换；
/// - 其余全小写英文：首字母大写（`rock` → `Rock`），常见缩写走 [_acronymDisplays]。
String pickGenreDisplayName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  final lower = trimmed.toLowerCase();
  final acronym = _acronymDisplays[lower];
  if (acronym != null) return acronym;

  if (RegExp('[A-Z]').hasMatch(trimmed)) return trimmed;
  if (RegExp('[^\x00-\x7F]').hasMatch(trimmed)) return trimmed;

  return trimmed
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// 精确匹配别名：键为 [normalizeGenreKey] 处理后的完整字符串。
///
/// 这里放两类：写法固定的标准流派名，以及太短、用子串匹配会误伤的词
/// （`ost` / `dub` / `ska` / `rap` / `edm` 等）。
///
/// 连写形态（`JPop` / `KPop` / `HipHop` / `Lofi` / `RnB`）不必单列：
/// [normalizeGenreKey] 已把它们收敛成带分隔符的规范键。
const Map<String, String> _exactAssetAliases = <String, String>{
  // ── 说唱 ────────────────────────────────────────────────────────────
  'hip hop': 'hip-hop',
  'rap': 'hip-hop',
  'trap': 'hip-hop',
  'drill': 'hip-hop',
  'grime': 'hip-hop',
  'boom bap': 'hip-hop',
  'gangsta rap': 'hip-hop',
  '说唱': 'hip-hop',
  '嘻哈': 'hip-hop',
  '饶舌': 'hip-hop',
  '饒舌': 'hip-hop',

  // ── R&B ─────────────────────────────────────────────────────────────
  'r and b': 'r-b',
  'rhythm and blues': 'r-b',
  'contemporary r and b': 'r-b',
  'neo soul': 'r-b',
  '节奏布鲁斯': 'r-b',

  // ── 电子舞曲 ────────────────────────────────────────────────────────
  'edm': 'edm',
  'dance': 'edm',
  'house': 'edm',
  'deep house': 'edm',
  'tech house': 'edm',
  'progressive house': 'edm',
  'electro house': 'edm',
  'big room': 'edm',
  'techno': 'edm',
  'trance': 'edm',
  'psytrance': 'edm',
  'dubstep': 'edm',
  'hardstyle': 'edm',
  'drum and bass': 'edm',
  'dnb': 'edm',
  'future bass': 'edm',
  'uk garage': 'edm',
  '电子舞曲': 'edm',
  '舞曲': 'edm',
  '浩室': 'edm',

  // ── 嘻哈 / 电子交界 ─────────────────────────────────────────────────
  'trip hop': 'electronic',
  'breakbeat': 'electronic',
  'downtempo': 'electronic',
  'idm': 'electronic',
  'glitch': 'electronic',
  'synthwave': 'electronic',
  'chillwave': 'electronic',
  'electro': 'electronic',

  // ── 氛围 / 低保真 ───────────────────────────────────────────────────
  'ambient': 'ambient',
  'new age': 'ambient',
  'drone': 'ambient',
  'field recording': 'ambient',
  '氛围': 'ambient',
  '新世纪': 'ambient',
  'lo fi': 'lo-fi',
  'chillhop': 'lo-fi',
  'jazzhop': 'lo-fi',
  'chill': 'lo-fi',
  'chillout': 'lo-fi',
  '低保真': 'lo-fi',

  // ── 日系 ────────────────────────────────────────────────────────────
  // 封面已拆成 anime / j-pop 两张：二次元向归 anime，日语流行向归 j-pop。
  'anime': 'anime',
  'vocaloid': 'anime',
  'anison': 'anime',
  'acg': 'anime',
  '动漫': 'anime',
  '二次元': 'anime',
  'j pop': 'j-pop',
  'city pop': 'j-pop',
  '日系': 'j-pop',
  '日本流行': 'j-pop',

  // ── 影视 / 游戏原声 ─────────────────────────────────────────────────
  'soundtrack': 'soundtrack',
  'ost': 'soundtrack',
  'original soundtrack': 'soundtrack',
  'original score': 'soundtrack',
  'film score': 'soundtrack',
  'motion picture': 'soundtrack',
  '原声': 'soundtrack',
  '原声带': 'soundtrack',
  '配乐': 'soundtrack',
  '影视原声': 'soundtrack',
  '游戏原声': 'soundtrack',

  // ── 独立 / 另类 ─────────────────────────────────────────────────────
  'indie': 'indie',
  'indie pop': 'indie',
  'alternative': 'indie',
  'alternative rock': 'indie',
  'alt rock': 'indie',
  'shoegaze': 'indie',
  'britpop': 'indie',
  '独立': 'indie',
  '另类': 'indie',

  // ── 朋克 / 金属 ─────────────────────────────────────────────────────
  'punk': 'punk',
  'pop punk': 'punk',
  'hardcore': 'punk',
  '朋克': 'punk',
  '硬核': 'punk',
  'metal': 'metal',
  'metalcore': 'metal',
  'nu metal': 'metal',
  '金属': 'metal',

  // ── 灵魂 / 放克 ─────────────────────────────────────────────────────
  'soul': 'soul',
  'motown': 'soul',
  '灵魂': 'soul',
  'funk': 'funk',
  'disco': 'funk',
  'afrobeat': 'funk',
  '放克': 'funk',
  '迪斯科': 'funk',

  // ── 雷鬼 / 拉丁 ─────────────────────────────────────────────────────
  'reggae': 'reggae',
  'ska': 'reggae',
  'dub': 'reggae',
  'dancehall': 'reggae',
  '雷鬼': 'reggae',
  'latin': 'latin',
  'salsa': 'latin',
  'bossa nova': 'latin',
  'reggaeton': 'latin',
  'samba': 'latin',
  'tango': 'latin',
  'cumbia': 'latin',
  '拉丁': 'latin',

  // ── 蓝调 / 乡村 / 民谣 ──────────────────────────────────────────────
  'blues': 'blues',
  '蓝调': 'blues',
  '布鲁斯': 'blues',
  '藍調': 'blues',
  'country': 'country',
  'bluegrass': 'country',
  'americana': 'country',
  '乡村': 'country',
  'folk': 'folk',
  'acoustic': 'folk',
  'singer songwriter': 'folk',
  '民谣': 'folk',
  '民謠': 'folk',

  // ── 爵士 ────────────────────────────────────────────────────────────
  'jazz': 'jazz',
  'bebop': 'jazz',
  'swing': 'jazz',
  'big band': 'jazz',
  '爵士': 'jazz',

  // ── 古典 ────────────────────────────────────────────────────────────
  'classical': 'classical',
  'baroque': 'classical',
  'orchestral': 'classical',
  'symphony': 'classical',
  'opera': 'classical',
  'chamber music': 'classical',
  'romantic': 'classical',
  '古典': 'classical',
  '交响': 'classical',
  '管弦': 'classical',
  '歌剧': 'classical',

  // ── 摇滚 ────────────────────────────────────────────────────────────
  'rock': 'rock',
  'grunge': 'rock',
  'rockabilly': 'rock',
  '摇滚': 'rock',

  // ── 流行 ────────────────────────────────────────────────────────────
  'pop': 'pop',
  'k pop': 'k-pop',
  'mandopop': 'pop',
  'cantopop': 'pop',
  'synthpop': 'pop',
  'dream pop': 'pop',
  'electropop': 'pop',
  '流行': 'pop',
  '华语流行': 'pop',
  '国语流行': 'pop',
  '粤语流行': 'pop',
};

/// 子串匹配规则，按顺序命中即返回。
///
/// 只收长度足够、不会误伤的关键词；顺序遵循「越具体越靠前」，
/// 大类（`rock` / `pop`）放在最后兜住长尾写法。
const List<(String, String)> _substringAssetRules = <(String, String)>[
  // 日系先于 pop，否则 j-pop / k-pop 会被 pop 吞掉
  ('anime', 'anime'),
  ('vocaloid', 'anime'),
  ('anison', 'anime'),
  ('动漫', 'anime'),
  ('二次元', 'anime'),
  ('j pop', 'j-pop'),
  ('jpop', 'j-pop'),
  ('city pop', 'j-pop'),
  ('日系', 'j-pop'),
  ('日本流行', 'j-pop'),
  ('k pop', 'k-pop'),
  ('kpop', 'k-pop'),

  // 低保真先于 hip hop / electronic
  ('lofi', 'lo-fi'),
  ('lo fi', 'lo-fi'),
  ('chillhop', 'lo-fi'),
  ('jazzhop', 'lo-fi'),
  ('低保真', 'lo-fi'),

  // 原声先于 rock / classical
  ('soundtrack', 'soundtrack'),
  ('原声', 'soundtrack'),
  ('配乐', 'soundtrack'),
  ('影视', 'soundtrack'),
  ('游戏音乐', 'soundtrack'),

  ('ambient', 'ambient'),
  ('氛围', 'ambient'),
  ('new age', 'ambient'),

  // 独立先于 rock
  ('indie', 'indie'),
  ('alternative', 'indie'),
  ('shoegaze', 'indie'),
  ('britpop', 'indie'),
  ('独立', 'indie'),
  ('另类', 'indie'),

  ('punk', 'punk'),
  ('朋克', 'punk'),
  ('metal', 'metal'),
  ('金属', 'metal'),

  ('rhythm and blues', 'r-b'),
  ('r and b', 'r-b'),
  ('节奏布鲁斯', 'r-b'),

  ('soul', 'soul'),
  ('灵魂', 'soul'),
  ('funk', 'funk'),
  ('放克', 'funk'),
  ('disco', 'funk'),

  ('reggae', 'reggae'),
  ('dancehall', 'reggae'),
  ('雷鬼', 'reggae'),

  ('latin', 'latin'),
  ('salsa', 'latin'),
  ('bossa', 'latin'),
  ('reggaeton', 'latin'),
  ('拉丁', 'latin'),

  ('blues', 'blues'),
  ('蓝调', 'blues'),
  ('布鲁斯', 'blues'),
  ('藍調', 'blues'),

  ('country', 'country'),
  ('bluegrass', 'country'),
  ('乡村', 'country'),

  ('folk', 'folk'),
  ('民谣', 'folk'),
  ('民謠', 'folk'),
  ('acoustic', 'folk'),

  ('jazz', 'jazz'),
  ('bebop', 'jazz'),
  ('爵士', 'jazz'),

  // classical 先于 pop/rock，避免被拆分写法吞掉
  ('classical', 'classical'),
  ('baroque', 'classical'),
  ('orchestral', 'classical'),
  ('symphony', 'classical'),
  ('opera', 'classical'),
  ('古典', 'classical'),
  ('交响', 'classical'),

  ('electronic', 'electronic'),
  ('electronica', 'electronic'),
  ('synthwave', 'electronic'),
  ('breakbeat', 'electronic'),
  ('trip hop', 'electronic'),
  ('电子', 'electronic'),

  // 大类兜底：长尾写法（folk rock / dance pop 等）落到这里
  ('rock', 'rock'),
  ('摇滚', 'rock'),
  ('pop', 'pop'),
  ('流行', 'pop'),
];

/// 命中已知流派时返回资源键，未命中返回 `null`。
String? matchGenreAssetKey(String raw) {
  final key = normalizeGenreKey(raw);
  if (key.isEmpty) return null;

  final exact = _exactAssetAliases[key];
  if (exact != null) return exact;

  for (final (needle, asset) in _substringAssetRules) {
    if (key.contains(needle)) return asset;
  }
  return null;
}

/// 图片资源键 → 图标资源键的差异映射。
///
/// 图片按素材原名用连字符（`hip-hop.webp`、`r-b.webp`），图标沿用初版的下划线
/// 命名（`hip_hop.svg`、`rnb.svg`），两者不再同名；日系三张图（anime / j-pop /
/// k-pop）里前两张共用一枚 `anime_jpop.svg`。未列出的键两套资源同名。
const Map<String, String> _iconKeyByImageKey = <String, String>{
  'hip-hop': 'hip_hop',
  'lo-fi': 'lofi',
  'r-b': 'rnb',
  'anime': 'anime_jpop',
  'j-pop': 'anime_jpop',
  'k-pop': 'kpop',
};

/// 图片资源键，未命中时回落到 [kFallbackGenreAssetKey]。
String genreImageAssetKey(String raw) =>
    matchGenreAssetKey(raw) ?? kFallbackGenreAssetKey;

/// 图标资源键；兜底流派没有专属图标，返回 `null` 表示不渲染图标。
String? genreIconAssetKey(String raw) {
  final imageKey = matchGenreAssetKey(raw);
  if (imageKey == null) return null;
  return _iconKeyByImageKey[imageKey] ?? imageKey;
}
