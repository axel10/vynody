import 'package:collection/collection.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';

enum SortCriteria { title, filename, trackNumber }
enum SortOrder { ascending, descending }

class MusicSorter {
  static void sortFolders(List<MusicFolder> folders, {
    required SortCriteria criteria,
    required SortOrder order,
  }) {
    // Top level folders always sorted by name
    folders.sort(
      (a, b) => compareNatural(a.name.toLowerCase(), b.name.toLowerCase()),
    );
    for (var folder in folders) {
      sortFolderRecursive(folder, criteria: criteria, order: order);
    }
  }

  static void sortFolderRecursive(MusicFolder folder, {
    required SortCriteria criteria,
    required SortOrder order,
  }) {
    folder.subFolders.sort(
      (a, b) => compareNatural(a.name.toLowerCase(), b.name.toLowerCase()),
    );

    int Function(MusicFile, MusicFile) comparator;

    switch (criteria) {
      case SortCriteria.title:
        comparator = (a, b) => compareNatural(
          a.displayName.toLowerCase(),
          b.displayName.toLowerCase(),
        );
        break;
      case SortCriteria.filename:
        comparator = (a, b) =>
            compareNatural(a.name.toLowerCase(), b.name.toLowerCase());
        break;
      case SortCriteria.trackNumber:
        comparator = (a, b) {
          if (a.trackNumber != null && b.trackNumber != null) {
            return a.trackNumber!.compareTo(b.trackNumber!);
          }
          if (a.trackNumber != null) return -1;
          if (b.trackNumber != null) return 1;
          return compareNatural(a.name.toLowerCase(), b.name.toLowerCase());
        };
        break;
    }

    if (order == SortOrder.descending) {
      final baseComparator = comparator;
      comparator = (a, b) => baseComparator(b, a);
    }

    folder.files.sort(comparator);

    for (var sub in folder.subFolders) {
      sortFolderRecursive(sub, criteria: criteria, order: order);
    }
  }
}
