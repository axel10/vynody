import 'package:path/path.dart' as p;

class CleanHelper {
  /// 去除字符串首部的数字序号，例如:
  /// "01. Song Name" -> "Song Name"
  /// "01-02. Song Name" -> "Song Name"
  static String stripSequenceNumber(String text) {
    if (text.isEmpty) return text;
    final stripped = text.replaceFirst(RegExp(r'^\s*(?:\d{1,3}[\s._-]*)+'), '');
    final result = stripped.trim();
    return result.isEmpty ? text : result;
  }

  /// 去除字符串中的方括号及其内容，如:
  /// "Song Name [Live]" -> "Song Name"
  /// "Song Name 【2024】" -> "Song Name"
  static String removeBrackets(String text) {
    if (text.isEmpty) return text;
    return text
        .replaceAll(RegExp(r'[\[【][^\]】]*[\]】]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 从文件名派生出一个干净的标题（主要用于元数据缺失时的 Fallback）
  static String deriveCleanTitleFromFileName(String fileName) {
    final base = p.basenameWithoutExtension(fileName).trim();
    final noBrackets = removeBrackets(base);
    final noSeq = stripSequenceNumber(noBrackets);
    return noSeq;
  }
}
