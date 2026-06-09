import 'dart:convert';

class LyricsAiStreamTextParser {
  static final RegExp _refusalPattern = RegExp(
    r'(?:'
    r'抱歉[，,].*?(?:无法|不能|不可以|不提供|不支持|拒绝|无法提供|不能提供)|'
    r'很抱歉.*?(?:无法|不能|不可以|不提供|不支持|拒绝)|'
    r"(?:I\s+am|I'm)\s+sorry.*?(?:can't|cannot|unable|won't|must\s+decline)|"
    r"(?:I\s+can't|I\s+cannot|I\s+won't|I\s+must\s+decline).*?(?:provide|help|generate|share)|"
    r"(?:cannot|can't|won't|unable\s+to)\s+(?:provide|help|generate|share)"
    r')',
    caseSensitive: false,
    dotAll: true,
  );
  static const Set<String> _blockedKeys = <String>{
    'reasoning',
    'reasoning_details',
    'refusal',
  };
  static const Set<String> _preferredTextKeys = <String>{
    'text',
    'content',
    'output_text',
    'delta',
  };

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

    if (_containsBlockedFields(raw)) {
      return null;
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

  String? extractDoubaoDeltaText(dynamic raw) {
    final decoded = _decodeRaw(raw);
    if (decoded is! Map) {
      return null;
    }

    final type = decoded['type']?.toString().trim();
    if (type != 'response.output_text.delta') {
      return null;
    }

    final delta = decoded['delta'];
    if (delta is String && delta.isNotEmpty) {
      return delta;
    }
    return null;
  }

  bool looksLikeRefusalText(String text) {
    return _refusalPattern.hasMatch(text.trim());
  }

  bool _containsBlockedFields(String raw) {
    return raw.contains('"reasoning"') ||
        raw.contains('"reasoning_details"') ||
        raw.contains('"refusal"');
  }

  dynamic _decodeRaw(dynamic raw) {
    if (raw is Map || raw is List) {
      return raw;
    }
    if (raw is! String) {
      return null;
    }
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  String? _extractTextFromDecoded(dynamic decoded) {
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        if (_blockedKeys.contains(entry.key)) {
          continue;
        }

        if (_preferredTextKeys.contains(entry.key) && entry.value is String) {
          final text = entry.value as String;
          if (text.isNotEmpty) return text;
        }

        if (entry.value is Map || entry.value is List) {
          final nested = _extractTextFromDecoded(entry.value);
          if (nested != null && nested.isNotEmpty) {
            return nested;
          }
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
