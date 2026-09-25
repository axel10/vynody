import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../dialogs/sort_options_dialog.dart';
import '../l10n/app_localizations.dart';
import '../models/music_file.dart';

enum QueueSortField {
  title,
  artist,
  album,
  duration,
  filename,
  trackNumber,
}

class QueueSortUtils {
  static List<MusicFile> sortQueue(
    List<MusicFile> queue,
    QueueSortField field,
    bool ascending,
  ) {
    if (queue.isEmpty) return queue;
    final sortedList = List<MusicFile>.from(queue);
    sortedList.sort((a, b) {
      int cmp = 0;
      switch (field) {
        case QueueSortField.title:
          cmp = compareNatural(
            a.displayName.toLowerCase(),
            b.displayName.toLowerCase(),
          );
          break;
        case QueueSortField.artist:
          cmp = compareNatural(
            (a.artist ?? '').toLowerCase(),
            (b.artist ?? '').toLowerCase(),
          );
          if (cmp == 0) {
            cmp = compareNatural(
              a.displayName.toLowerCase(),
              b.displayName.toLowerCase(),
            );
          }
          break;
        case QueueSortField.album:
          cmp = compareNatural(
            (a.album ?? '').toLowerCase(),
            (b.album ?? '').toLowerCase(),
          );
          if (cmp == 0) {
            final aTrack = a.trackNumber ?? 0;
            final bTrack = b.trackNumber ?? 0;
            cmp = aTrack.compareTo(bTrack);
            if (cmp == 0) {
              cmp = compareNatural(
                a.displayName.toLowerCase(),
                b.displayName.toLowerCase(),
              );
            }
          }
          break;
        case QueueSortField.duration:
          final aDur = a.durationMillis ?? 0;
          final bDur = b.durationMillis ?? 0;
          cmp = aDur.compareTo(bDur);
          if (cmp == 0) {
            cmp = compareNatural(
              a.displayName.toLowerCase(),
              b.displayName.toLowerCase(),
            );
          }
          break;
        case QueueSortField.filename:
          cmp = compareNatural(a.name.toLowerCase(), b.name.toLowerCase());
          break;
        case QueueSortField.trackNumber:
          if (a.trackNumber != null && b.trackNumber != null) {
            cmp = a.trackNumber!.compareTo(b.trackNumber!);
          } else if (a.trackNumber != null) {
            cmp = -1;
          } else if (b.trackNumber != null) {
            cmp = 1;
          } else {
            cmp = compareNatural(
              a.displayName.toLowerCase(),
              b.displayName.toLowerCase(),
            );
          }
          break;
      }
      return ascending ? cmp : -cmp;
    });
    return sortedList;
  }

  static Future<SortResult<QueueSortField>?> showSortDialog(
    BuildContext context, {
    required QueueSortField currentField,
    required bool sortAscending,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<SortResult<QueueSortField>>(
      context: context,
      builder: (context) => SortOptionsDialog<QueueSortField>(
        title: l10n.sort,
        currentField: currentField,
        sortAscending: sortAscending,
        options: [
          SortOptionItem(
            value: QueueSortField.title,
            label: l10n.title,
            icon: Icons.title_rounded,
          ),
          SortOptionItem(
            value: QueueSortField.artist,
            label: l10n.artists,
            icon: Icons.person_rounded,
          ),
          SortOptionItem(
            value: QueueSortField.album,
            label: l10n.albums,
            icon: Icons.album_rounded,
          ),
          SortOptionItem(
            value: QueueSortField.duration,
            label: l10n.sortDuration,
            icon: Icons.schedule_rounded,
          ),
          SortOptionItem(
            value: QueueSortField.filename,
            label: l10n.fileName,
            icon: Icons.insert_drive_file_outlined,
          ),
          SortOptionItem(
            value: QueueSortField.trackNumber,
            label: l10n.trackNumber,
            icon: Icons.numbers_rounded,
          ),
        ],
      ),
    );
  }
}
