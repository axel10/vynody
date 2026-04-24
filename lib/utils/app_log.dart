import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppLog {
  AppLog._();

  static final DebugPrintCallback _defaultDebugPrint = debugPrint;

  static IOSink? _sink;
  static Future<void> _writeQueue = Future<void>.value();
  static bool _installed = false;
  static String? _logFilePath;

  static String? get logFilePath => _logFilePath;

  static Future<void> init() async {
    if (_sink != null) {
      return;
    }

    final supportDir = await getApplicationSupportDirectory();
    final logDir = Directory(p.join(supportDir.path, 'logs'));
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }

    final file = File(p.join(logDir.path, 'vibeflow.log'));
    final exists = await file.exists();
    if (exists) {
      final length = await file.length();
      const maxBytes = 2 * 1024 * 1024;
      if (length > maxBytes) {
        final backup = File(p.join(logDir.path, 'vibeflow.previous.log'));
        if (await backup.exists()) {
          await backup.delete();
        }
        await file.rename(backup.path);
      }
    }

    _logFilePath = file.path;
    _sink = file.openWrite(mode: FileMode.append, encoding: utf8);
    log(
      '=== session start pid=$pid mode=${kReleaseMode ? "release" : kDebugMode ? "debug" : "profile"} '
      'platform=${Platform.operatingSystem} executable=${Platform.resolvedExecutable} ===',
      mirrorToConsole: true,
    );
    log('log file path=$_logFilePath', mirrorToConsole: true);
  }

  static void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null) {
        _defaultDebugPrint(message, wrapWidth: wrapWidth);
        return;
      }
      log(message, mirrorToConsole: true);
    };
  }

  static void log(
    Object message, {
    bool mirrorToConsole = false,
    StackTrace? stackTrace,
  }) {
    final text = message.toString();
    final buffer = StringBuffer()
      ..write('[${DateTime.now().toIso8601String()}] ')
      ..writeln(text);
    if (stackTrace != null) {
      buffer.writeln(stackTrace);
    }
    final payload = buffer.toString();

    if (mirrorToConsole) {
      _defaultDebugPrint(text);
      if (stackTrace != null) {
        _defaultDebugPrint(stackTrace.toString());
      }
    }

    final sink = _sink;
    if (sink == null) {
      return;
    }

    _writeQueue = _writeQueue.then((_) async {
      sink.write(payload);
      await sink.flush();
    }).catchError((_) {});
  }

  static Future<void> flush() async {
    await _writeQueue;
    await _sink?.flush();
  }
}
