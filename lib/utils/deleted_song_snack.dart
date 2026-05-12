import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'app_snack_bar.dart';

void showDeletedSongSnack(
  BuildContext context,
  WidgetRef ref, {
  required bool skipped,
}) {
  final l10n = AppLocalizations.of(context)!;
  final message = skipped ? l10n.songDeletedSkipped : l10n.songDeleted;

  AppSnackBar.show(context, ref, SnackBar(content: Text(message)));
}
