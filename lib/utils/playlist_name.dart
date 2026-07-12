import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../player/library/playlist_service.dart';

String localizedPlaylistName(BuildContext context, Playlist playlist) {
  final l10n = AppLocalizations.of(context)!;
  if (playlist.id == 'default') return l10n.defaultList;
  if (playlist.id == PlaylistService.favoritePlaylistId) return l10n.favorites;
  return playlist.name;
}
