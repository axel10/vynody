import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lan_sync_models.dart';

/// 「最近一次同步」的持久化。
///
/// 只存一条：用户想看的是「上次同步发生了什么」，不是同步审计日志。
/// 存成 JSON 而不是拆成多个 key，是为了以后加字段（比如耗时明细）时
/// 老数据还能按缺省值读出来，不用写迁移。
class LanSyncHistoryStore {
  static const String _key = 'lan_sync_last_receipt_v1';

  /// 记录一次结果。失败只记日志：历史记录坏了不能让同步本身报错。
  static Future<void> record(LanSyncReceipt receipt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(receipt.toJson()));
    } catch (e) {
      debugPrint('[LanSyncHistory] Failed to record receipt: $e');
    }
  }

  static Future<LanSyncReceipt?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return LanSyncReceipt.fromJson(decoded);
    } catch (e) {
      debugPrint('[LanSyncHistory] Failed to read receipt: $e');
      return null;
    }
  }

  /// 上次同步的完成时间。单列一个字段太啰嗦，直接读 JSON 里的时间戳。
  static Future<int?> lastFinishedAtMillis() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final value = decoded['finishedAtMs'];
      return value is int ? value : null;
    } catch (_) {
      return null;
    }
  }
}
