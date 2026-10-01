import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

export 'package:file_picker/file_picker.dart' show FileType;

class FileSelectorHelper {
  FileSelectorHelper._();

  static bool get _useFileSelector =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Picks a directory path.
  ///
  /// Uses `audio_core.player` method channel on iOS to retain security-scoped permissions and persist bookmarks,
  /// [file_selector] on Windows, Linux, and macOS, and [file_picker] on other platforms.
  static Future<String?> pickDirectory({bool lockParentWindow = true}) async {
    String? path;
    if (Platform.isIOS) {
      try {
        path = await const MethodChannel(
          'audio_core.player',
        ).invokeMethod<String>('pickAndAuthorizeDirectory');
      } catch (e) {
        debugPrint('[FileSelectorHelper] pickAndAuthorizeDirectory failed: $e');
      }
    } else if (_useFileSelector) {
      path = await file_selector.getDirectoryPath();
    } else {
      path = await FilePicker.getDirectoryPath(lockParentWindow: lockParentWindow);
    }
    return path;
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
      final result = await FilePicker.pickFiles(
        type: fileType == FileType.any && extensions != null
            ? FileType.custom
            : fileType,
        allowedExtensions: fileType == FileType.any && extensions != null
            ? extensions
            : null,
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
      final result = await FilePicker.pickFiles(
        type: fileType == FileType.any && extensions != null
            ? FileType.custom
            : fileType,
        allowedExtensions: fileType == FileType.any && extensions != null
            ? extensions
            : null,
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

