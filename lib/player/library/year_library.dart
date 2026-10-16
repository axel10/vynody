export 'package:vynody/models/year_summary.dart';
export 'library_overview_providers.dart' show yearLibraryProvider;

/// 年份排序字段
enum YearSortField {
  year,
  songCount,
}

extension YearSortFieldX on YearSortField {
  String get storageValue => name;
  static YearSortField fromStorageValue(
    String? value,
    YearSortField defaultValue,
  ) {
    if (value == null) return defaultValue;
    return YearSortField.values.firstWhere(
      (e) => e.name == value,
      orElse: () => defaultValue,
    );
  }
}
