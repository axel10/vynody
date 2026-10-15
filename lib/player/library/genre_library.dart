
export 'package:vynody/models/genre_summary.dart';
export 'library_overview_providers.dart' show genreLibraryProvider;

/// 流派排序字段
enum GenreSortField {
  genre,
  songCount,
}

extension GenreSortFieldX on GenreSortField {
  String get storageValue => name;
  static GenreSortField fromStorageValue(
    String? value,
    GenreSortField defaultValue,
  ) {
    if (value == null) return defaultValue;
    return GenreSortField.values.firstWhere(
      (e) => e.name == value,
      orElse: () => defaultValue,
    );
  }
}
