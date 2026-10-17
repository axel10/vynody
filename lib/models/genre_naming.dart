/// 流派名称归一化与展示名。
///
/// 流派字段在各家标签格式里都是完全自由的文本：同一个流派可能以
/// `Rock` / `rock` / `ROCK` / `Alternative Rock` / `华语摇滚` 出现，
/// 远程源（Navidrome / Jellyfin / SMB / WebDAV）之间还各有一套写法。
/// 直接拿原始字符串当聚合键，一个流派会在库里裂成好几份。
///
/// 这里提供两层能力，彼此独立：
///
/// 1. [normalizeGenreKey] —— 聚合键，只用于分组与相等判断，不展示。
/// 2. [pickGenreDisplayName] —— 展示名，保留用户语言和大写习惯。
///
/// 流派专属封面与图标资源已于 2026-10-17 全部移除：界面统一使用
/// 该流派代表曲的专辑封面，兜底为通用音符图标，不再维护任何资源键映射。
library;

/// 「连字符 / 空格 / 连写」三种写法的等价表。
///
/// 键是 [normalizeGenreKey] 文本归一化结果**去掉全部空格**后的形态，
/// 值是规范聚合键。只收 [_acronymDisplays] 里已被认定为「同一流派多种
/// 写法」的组，不做同义词合并（`Rap` 与 `Hip-Hop` 属于不同流派，保持独立）。
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
