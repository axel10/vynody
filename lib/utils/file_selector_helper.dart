import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart';
import 'package:vynody/player/platform/apple_file_access.dart';

export 'package:file_picker/file_picker.dart' show FileType;

/// Result of a directory pick, keeping the "user cancelled" and "system denied
/// access" cases distinguishable.
///
/// On iOS a picked folder can come back with no usable security scope (for
/// example a File Provider location). Treating that as a cancellation hides the
/// problem: the folder gets added to the library and then scans to 0 songs.
class DirectoryPickResult {
  const DirectoryPickResult._({this.path, this.accessDenied = false});

  const DirectoryPickResult.picked(String path) : this._(path: path);

  const DirectoryPickResult.cancelled() : this._();

  const DirectoryPickResult.denied() : this._(accessDenied: true);

  final String? path;

  /// True when the picker returned a folder the app is not allowed to read.
  final bool accessDenied;

  bool get hasPath => path != null && path!.isNotEmpty;
}

class FileSelectorHelper {
  FileSelectorHelper._();

  static bool get _useFileSelector =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Picks a directory path.
  ///
  /// Uses [AppleFileAccess] on iOS to retain security-scoped permissions and persist bookmarks,
  /// [file_selector] on Windows, Linux, and macOS, and [file_picker] on other platforms.
  static Future<String?> pickDirectory({bool lockParentWindow = true}) async {
    final result = await pickDirectoryDetailed(
      lockParentWindow: lockParentWindow,
    );
    return result.path;
  }

  /// Same as [pickDirectory] but reports whether the system denied access to
  /// the picked folder instead of collapsing every failure into `null`.
  static Future<DirectoryPickResult> pickDirectoryDetailed({
    bool lockParentWindow = true,
  }) async {
    if (Platform.isIOS) {
      // 选择器与授权都在 AppleFileAccess 里，这里只做结果映射。
      final pick = await AppleFileAccess.pickAndAuthorizeDirectory();
      if (pick.denied) return const DirectoryPickResult.denied();
      final path = pick.path;
      if (path == null || path.isEmpty) {
        return const DirectoryPickResult.cancelled();
      }
      return DirectoryPickResult.picked(path);
    }

    String? path;
    if (_useFileSelector) {
      path = await file_selector.getDirectoryPath();
    } else {
      path = await FilePicker.getDirectoryPath(
        lockParentWindow: lockParentWindow,
      );
    }
    if (path == null || path.isEmpty) {
      return const DirectoryPickResult.cancelled();
    }
    return DirectoryPickResult.picked(path);
  }

  /// Picks a single file path.
  ///
  /// Uses [file_selector] on Windows, Linux, and macOS, and [file_picker] on other platforms.
  static Future<String?> pickFile({
    String? label,
    List<String>? extensions,
    FileType fileType = FileType.any,
  }) async {
    if (_useFileSelector) {
      final typeGroup = file_selector.XTypeGroup(
        label: label,
        extensions: extensions,
      );
      final file = await file_selector.openFile(
        acceptedTypeGroups: [typeGroup],
      );
      return file?.path;
    } else {
      final effectiveType = fileType == FileType.any && extensions != null
          ? FileType.custom
          : fileType;
      final result = await FilePicker.pickFiles(
        type: effectiveType,
        allowedExtensions:
            effectiveType == FileType.custom ? extensions : null,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return null;
      return result.files.first.path;
    }
  }

  /// Picks multiple file paths.
  ///
  /// Uses [file_selector] on Windows, Linux, and macOS, and [file_picker] on other platforms.
  static Future<List<String>?> pickFiles({
    String? label,
    List<String>? extensions,
    FileType fileType = FileType.any,
  }) async {
    if (_useFileSelector) {
      final typeGroup = file_selector.XTypeGroup(
        label: label,
        extensions: extensions,
      );
      final files = await file_selector.openFiles(
        acceptedTypeGroups: [typeGroup],
      );
      return files.map((file) => file.path).toList();
    } else {
      final effectiveType = fileType == FileType.any && extensions != null
          ? FileType.custom
          : fileType;
      final result = await FilePicker.pickFiles(
        type: effectiveType,
        allowedExtensions:
            effectiveType == FileType.custom ? extensions : null,
        allowMultiple: true,
      );
      if (result == null) return null;
      return result.files.map((f) => f.path).whereType<String>().toList();
    }
  }

  /// Saves a file at a selected location with a suggested name.
  ///
  /// Uses [file_selector] on Windows, Linux, and macOS, and [file_picker] on other platforms.
  /// Note: [bytes] is required on Android & iOS by `file_picker`. On Desktop, if [bytes] is provided,
  /// it will automatically be written to the selected file location.
  static Future<String?> saveFile({
    required String suggestedName,
    String? label,
    List<String>? extensions,
    String? dialogTitle,
    Uint8List? bytes,
  }) async {
    if (_useFileSelector) {
      final typeGroup = file_selector.XTypeGroup(
        label: label,
        extensions: extensions,
      );
      final fileSaveLocation = await file_selector.getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: extensions != null ? [typeGroup] : const [],
      );
      if (fileSaveLocation == null) return null;
      if (bytes != null) {
        await File(fileSaveLocation.path).writeAsBytes(bytes);
      }
      return fileSaveLocation.path;
    } else {
      return FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: suggestedName,
        type: extensions != null ? FileType.custom : FileType.any,
        allowedExtensions: extensions,
        bytes: bytes,
      );
    }
  }
}

