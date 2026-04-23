import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

void showDeletedSongSnack(BuildContext context, {required bool skipped}) {
  final l10n = AppLocalizations.of(context)!;
  final message = skipped ? l10n.songDeletedSkipped : l10n.songDeleted;

  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
