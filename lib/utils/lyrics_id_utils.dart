import 'dart:convert';

import 'lrc_utils.dart';

class LyricsIdUtils {
  static String fromLyricsText(String? text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty) return '';
    return _fnv1a64Hex(normalized);
  }

  static String _normalize(String? text) {
    if (text == null) return '';
    return LrcUtils.stripTimestamps(text).replaceAll('\r\n', '\n').trim();
  }

  static String _fnv1a64Hex(String input) {
    var hash = BigInt.parse('1469598103934665603');
    final prime = BigInt.parse('1099511628211');
    final mask = (BigInt.one << 64) - BigInt.one;

    for (final byte in utf8.encode(input)) {
      hash = (hash ^ BigInt.from(byte)) * prime;
      hash &= mask;
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }
}
