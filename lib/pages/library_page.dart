import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'albums_tab.dart';
import 'artists_tab.dart';
import 'most_played_tab.dart';
import 'playlist_page_riverpod.dart';
import 'playlist_tab.dart';
import 'recently_added_tab.dart';

// 媒体库页面

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _tabIndex = 0;
  bool _mostPlayedTabLoaded = false;
  bool _recentlyAddedTabLoaded = false;
  bool _albumsTabLoaded = false;
  bool _artistsTabLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this)
      ..addListener(() {
        if (_tabController.indexIsChanging) return;
        if (_tabIndex == _tabController.index) return;
        setState(() {
          _tabIndex = _tabController.index;
          if (_tabIndex == 1) {
            _mostPlayedTabLoaded = true;
          } else if (_tabIndex == 2) {
            _recentlyAddedTabLoaded = true;
          } else if (_tabIndex == 3) {
            _albumsTabLoaded = true;
          } else if (_tabIndex == 4) {
            _artistsTabLoaded = true;
          }
        });
        if (_tabIndex != 0) {
          ref.read(playlistSelectionModeProvider.notifier).setEnabled(false);
        }
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title:TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.playlist),
            Tab(text: l10n.mostPlayed),
            Tab(text: l10n.recentlyAdded),
            Tab(text: l10n.albums),
            Tab(text: l10n.artists),
          ],
        )
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          const PlaylistTab(),
          _mostPlayedTabLoaded
              ? const MostPlayedTab()
              : const SizedBox.shrink(),
          _recentlyAddedTabLoaded
              ? const RecentlyAddedTab()
              : const SizedBox.shrink(),
          _albumsTabLoaded ? const AlbumsTab() : const SizedBox.shrink(),
          _artistsTabLoaded ? const ArtistsTab() : const SizedBox.shrink(),
        ],
      ),
    );
  }

}
