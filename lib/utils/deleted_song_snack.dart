import 'package:flutter/material.dart';

void showDeletedSongSnack(BuildContext context, {required bool skipped}) {
  final isZh = Localizations.localeOf(context).languageCode == 'zh';
  final message = skipped
      ? (isZh ? '歌曲已删除，已跳过' : 'Song deleted, skipped')
      : (isZh ? '歌曲已删除' : 'Song deleted');

  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
