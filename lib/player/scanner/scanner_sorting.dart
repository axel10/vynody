import 'package:collection/collection.dart';

import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';

enum SortCriteria { title, filename, trackNumber }

enum SortOrder { ascending, descending }

extension SortCriteriaX on SortCriteria {
  String get storageValue => switch (this) {
    SortCriteria.title => 'title',
    SortCriteria.filename => 'filename',
    SortCriteria.trackNumber => 'track_number',
  };

  static SortCriteria fromStorageValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'title':
        return SortCriteria.title;
      case 'track_number':
      case 'tracknumber':
        return SortCriteria.trackNumber;
      case 'filename':
      default:
        return SortCriteria.filename;
    }
  }
}

extension SortOrderX on SortOrder {
  String get storageValue => switch (this) {
    SortOrder.ascending => 'ascending',
    SortOrder.descending => 'descending',
  };

  static SortOrder fromStorageValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'descending':
        return SortOrder.descending;
      case 'ascending':
      default:
        return SortOrder.ascending;
    }
  }
}

class FolderSortSettings {
  const FolderSortSettings({required this.criteria, required this.order});

  final SortCriteria criteria;
  final SortOrder order;

  FolderSortSettings copyWith({SortCriteria? criteria, SortOrder? order}) {
    return FolderSortSettings(
      criteria: criteria ?? this.criteria,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() {
    return {'criteria': criteria.storageValue, 'order': order.storageValue};
  }

  factory FolderSortSettings.fromJson(Map<String, dynamic> json) {
    return FolderSortSettings(
      criteria: SortCriteriaX.fromStorageValue(json['criteria'] as String?),
      order: SortOrderX.fromStorageValue(json['order'] as String?),
    );
  }
}

class ScannerFolderSorter {
  const ScannerFolderSorter();

  /// 整棵目录树按各自解析出的设置重排。
  ///
  /// 根目录本身的显示顺序由用户拖拽决定（`ScannerService._roots.rootPaths`），
  /// 这里不碰传入的 [folders] 顺序。
  void sortFoldersForTree(
    List<MusicFolder> folders, {
    required FolderSortSettings Function(String path) resolveSettings,
  }) {
    for (final folder in folders) {
      sortFolderRecursiveForTree(folder, resolveSettings: resolveSettings);
    }
  }

  /// 只重排指定目录自身的「直接子目录 + 曲目」，不递归。
  void sortSpecificFolders(
    Iterable<MusicFolder> folders, {
    required FolderSortSettings Function(String path) resolveSettings,
  }) {
    for (final folder in folders) {
      final settings = resolveSettings(folder.path);
      folder.subFolders.sort(
        _folderComparator(order: settings.order),
      );
      folder.files.sort(
        _comparatorFor(criteria: settings.criteria, order: settings.order),
      );
      folder.representativeSongCache = null;
    }
  }

  void sortFolderRecursiveForTree(
    MusicFolder folder, {
    required FolderSortSettings Function(String path) resolveSettings,
  }) {
    final settings = resolveSettings(folder.path);
    folder.subFolders.sort(
      _folderComparator(order: settings.order),
    );
    folder.files.sort(
      _comparatorFor(criteria: settings.criteria, order: settings.order),
    );
    folder.representativeSongCache = null;

    for (final subFolder in folder.subFolders) {
      sortFolderRecursiveForTree(subFolder, resolveSettings: resolveSettings);
    }
  }

  int Function(MusicFile, MusicFile) _comparatorFor({
    required SortCriteria criteria,
    required SortOrder order,
  }) {
    final direction = order == SortOrder.descending ? -1 : 1;

    switch (criteria) {
      case SortCriteria.title:
        return (a, b) =>
            direction * _compareNaturally(a.displayName, b.displayName);
      case SortCriteria.filename:
        return (a, b) => direction * _compareNaturally(a.name, b.name);
      case SortCriteria.trackNumber:
        return (a, b) {
          final left = a.trackNumber;
          final right = b.trackNumber;
          if (left == null && right == null) {
            return direction * _compareNaturally(a.name, b.name);
          }
          // 缺失音轨号恒定排在末尾，不随升 / 降序翻转
          if (left == null) return 1;
          if (right == null) return -1;
          final byTrack = left.compareTo(right);
          if (byTrack != 0) return direction * byTrack;
          return direction * _compareNaturally(a.name, b.name);
        };
    }
  }

  /// 子目录只按名称排（排序依据只作用于曲目），方向跟随设置。
  int Function(MusicFolder, MusicFolder) _folderComparator({
    required SortOrder order,
  }) {
    final direction = order == SortOrder.descending ? -1 : 1;
    return (a, b) => direction * _compareNaturally(a.name, b.name);
  }

  int _compareNaturally(String left, String right) {
    if (identical(left, right) || left == right) return 0;
    return compareNatural(left.toLowerCase(), right.toLowerCase());
  }
}
