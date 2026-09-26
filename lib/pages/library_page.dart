import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'albums_tab.dart';
import 'artists_tab.dart';
import 'most_played_tab.dart';
import 'recently_played_tab.dart';
import '../widgets/library_selection_scope.dart';
import 'playlist_tab.dart';
import 'recently_added_tab.dart';
import 'main_layout_riverpod.dart';

// 媒体库页面

class LibraryPage extends ConsumerStatefulWidget {
  final int initialTabIndex;
  final bool initialAlbums3DView;
  final int initialAlbums3DIndex;
  final bool? useSidebar;

  const LibraryPage({
    super.key,
    this.initialTabIndex = 0,
    this.initialAlbums3DView = false,
    this.initialAlbums3DIndex = 0,
    this.useSidebar,
  });

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
  with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTabIndex;
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    )
      ..addListener(() {
        if (_tabController.indexIsChanging) return;
        if (_tabIndex == _tabController.index) return;
        _tabIndex = _tabController.index;
        ref.read(libraryActiveTabIndexProvider.notifier).set(_tabIndex);
        ref.read(librarySelectionScopeProvider.notifier).clear();
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(libraryActiveTabIndexProvider.notifier).set(_tabIndex);
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
    final bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final bool isCoverFlowImmersive =
        isLandscape && ref.watch(isCoverFlowImmersiveActiveProvider);
    final bool effectiveUseSidebar = widget.useSidebar ?? isLandscape;
    final double leftPadding = effectiveUseSidebar ? 80.0 : 0.0;
    final double safeTopPadding =
        isDesktop ? 32.0 : MediaQuery.of(context).padding.top;
    final double topPadding = safeTopPadding + kToolbarHeight;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          TabBarView(
            controller: _tabController,
            physics: isCoverFlowImmersive
                ? const NeverScrollableScrollPhysics()
                : null,
            children: [
              KeepAliveWrapper(
                child: PlaylistTab(
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
              KeepAliveWrapper(
                child: RecentlyPlayedTab(
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
              KeepAliveWrapper(
                child: MostPlayedTab(
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
              KeepAliveWrapper(
                child: RecentlyAddedTab(
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
              KeepAliveWrapper(
                child: AlbumsTab(
                  initial3DView: widget.initialAlbums3DView,
                  initial3DIndex: widget.initialAlbums3DIndex,
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
              KeepAliveWrapper(
                child: ArtistsTab(
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: leftPadding,
            right: 0,
            height: topPadding,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              opacity: isCoverFlowImmersive ? 0.0 : 1.0,
              child: IgnorePointer(
                ignoring: isCoverFlowImmersive,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      padding: EdgeInsets.only(top: safeTopPadding),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(
                          alpha: isDark ? 0.66 : 0.80,
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: theme.dividerColor.withValues(alpha: 0.12),
                            width: 0.8,
                          ),
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.center,
                        dividerColor: Colors.transparent,
                        tabs: [
                          Tab(text: l10n.playlist),
                          Tab(text: l10n.recentlyPlayed),
                          Tab(text: l10n.mostPlayed),
                          Tab(text: l10n.recentlyAdded),
                          Tab(text: l10n.albums),
                          Tab(text: l10n.artists),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class KeepAliveWrapper extends StatefulWidget {
  final Widget child;

  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
