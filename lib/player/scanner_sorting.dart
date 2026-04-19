import 'package:collection/collection.dart';

import '../models/music_file.dart';
import '../models/music_folder.dart';

enum SortCriteria { title, filename, trackNumber }

enum SortOrder { ascending, descending }

class ScannerFolderSorter {
  const ScannerFolderSorter();

  void sortFolders(
    List<MusicFolder> folders, {
    required SortCriteria criteria,
    required SortOrder order,
  }) {
    folders.sort((a, b) => _compareNaturally(a.name, b.name));
    for (final folder in folders) {
      sortFolderRecursive(folder, criteria: criteria, order: order);
    }
  }

  void sortFolderRecursive(
    MusicFolder folder, {
    required SortCriteria criteria,
    required SortOrder order,
  }) {
    folder.subFolders.sort((a, b) => _compareNaturally(a.name, b.name));

    int Function(MusicFile, MusicFile) comparator;

    switch (criteria) {
      case SortCriteria.title:
        comparator = (a, b) => _compareNaturally(a.displayName, b.displayName);
        break;
      case SortCriteria.filename:
        comparator = (a, b) => _compareNaturally(a.name, b.name);
        break;
      case SortCriteria.trackNumber:
        comparator = (a, b) {
          if (a.trackNumber != null && b.trackNumber != null) {
            return a.trackNumber!.compareTo(b.trackNumber!);
          }
          if (a.trackNumber != null) return -1;
          if (b.trackNumber != null) return 1;
          return _compareNaturally(a.name, b.name);
        };
        break;
    }

    if (order == SortOrder.descending) {
      final baseComparator = comparator;
      comparator = (a, b) => baseComparator(b, a);
    }

    folder.files.sort(comparator);

    for (final subFolder in folder.subFolders) {
      sortFolderRecursive(subFolder, criteria: criteria, order: order);
    }
  }

  int _compareNaturally(String left, String right) {
    return compareNatural(left.toLowerCase(), right.toLowerCase());
  }
}
