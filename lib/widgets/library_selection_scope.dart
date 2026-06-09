import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LibrarySelectionScope {
  none,
  library,
  playlist,
  queue,
  folder,
  folderRoot,
}

class LibrarySelectionScopeController extends Notifier<LibrarySelectionScope> {
  @override
  LibrarySelectionScope build() => LibrarySelectionScope.none;

  void setScope(LibrarySelectionScope scope) {
    state = scope;
  }

  void clear() {
    state = LibrarySelectionScope.none;
  }
}

final librarySelectionScopeProvider =
    NotifierProvider<LibrarySelectionScopeController, LibrarySelectionScope>(
      LibrarySelectionScopeController.new,
    );

