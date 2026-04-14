import 'dart:convert';

class LyricsAiStreamTextParser {
  String? extractText(dynamic raw) {
    if (raw is Map || raw is List) {
      final extracted = _extractTextFromDecoded(raw);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
      return null;
    }

    if (raw is! String) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      final extracted = _extractTextFromDecoded(decoded);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
    } catch (_) {
      // Ignore malformed SSE payloads and continue with a loose fallback.
    }

    final looseMatch = RegExp(
      r'"text"\s*:\s*"((?:\\.|[^"\\])*)"',
      dotAll: true,
    ).firstMatch(raw);
    if (looseMatch != null) {
      final rawText = '"${looseMatch.group(1)!}"';
      try {
        final text = jsonDecode(rawText);
        if (text is String && text.isNotEmpty) {
          return text;
        }
      } catch (_) {
        // Keep returning null if the fallback cannot be decoded.
      }
    }

    return null;
  }

  String? _extractTextFromDecoded(dynamic decoded) {
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        if ((entry.key == 'text' || entry.key == 'content') &&
            entry.value is String) {
          final text = entry.value as String;
          if (text.isNotEmpty) return text;
        }

        final nested = _extractTextFromDecoded(entry.value);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
      return null;
    }

    if (decoded is List) {
      for (final item in decoded) {
        final nested = _extractTextFromDecoded(item);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
      return null;
    }

    return null;
  }
}
