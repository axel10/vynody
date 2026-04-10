Duration durationFromMilliseconds(Object? value) {
  if (value is Duration) return value;
  if (value is num) {
    return Duration(milliseconds: value.round());
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return Duration(milliseconds: parsed);
    }
  }
  return Duration.zero;
}

int durationToMilliseconds(Duration value) => value.inMilliseconds;

List<String> stringListFromJson(Object? value) {
  if (value is List) {
    return value.map((item) => item?.toString() ?? '').toList(growable: false);
  }
  return const [];
}

List<String> stringListToJson(List<String> value) => value;
