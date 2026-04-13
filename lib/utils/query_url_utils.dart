class QueryUrlUtils {
  static String buildUrl(
    String baseUrl, {
    Map<String, String> queryParameters = const {},
    Map<String, String> rawQueryParameters = const {},
  }) {
    final queryParts = <String>[
      for (final entry in queryParameters.entries)
        '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
      for (final entry in rawQueryParameters.entries)
        '${entry.key}=${entry.value}',
    ];

    if (queryParts.isEmpty) {
      return baseUrl;
    }

    return '$baseUrl?${queryParts.join('&')}';
  }
}
