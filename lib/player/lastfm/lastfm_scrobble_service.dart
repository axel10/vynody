import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/lastfm/lastfm_api_client.dart';
import 'package:vynody/player/lastfm/lastfm_auth_service.dart';
import 'package:vynody/player/lastfm/lastfm_credentials.dart';
import 'package:vynody/player/lastfm/lastfm_scrobble_entry.dart';
import 'package:vynody/player/lastfm/scrobble_tracker.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/settings/settings_service.dart';

/// Last.fm 上报的编排层。
///
/// 职责边界：
/// - [ScrobbleTracker] 负责「什么时候算听过」，是纯状态机；
/// - 本类负责开关、远程库策略、now playing 节流、入队与批量冲刷。
///
/// 它被 [AudioService] 的播放位置回调高频调用，所以热路径上只读内存字段，
/// 不做异步读盘 —— session 缺失时宁可不发，也不能阻塞播放回调。
class LastFmScrobbleService {
  LastFmScrobbleService({
    required LastFmApiClient client,
    required LastFmAuthService auth,
    required SettingsService settings,
    MetadataDatabase? database,
  }) : _client = client,
       _auth = auth,
       _settings = settings,
       _database = database ?? MetadataDatabase();

  /// 冲刷间隔。断网或服务端故障期间的记录留在队列里等下次。
  static const Duration flushInterval = Duration(minutes: 5);

  /// now playing 的节流窗口：暂停/继续反复触发时不要刷屏。
  static const Duration nowPlayingThrottle = Duration(seconds: 10);

  /// 批量之间的间隔，Last.fm 建议整体保持在每秒 5 次请求以内。
  static const Duration _batchSpacing = Duration(milliseconds: 250);

  final LastFmApiClient _client;
  final LastFmAuthService _auth;
  final SettingsService _settings;
  final MetadataDatabase _database;
  final ScrobbleTracker _tracker = ScrobbleTracker();

  /// 最近一次「确认写入成功」的时间，供设置页显示。
  final ValueNotifier<DateTime?> lastScrobbleAt = ValueNotifier<DateTime?>(null);

  /// 最近一次失败的简述，供设置页显示；成功后清空。
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  /// 队列里还有多少条待上报。
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  Timer? _flushTimer;
  bool _flushing = false;
  bool _started = false;
  String? _nowPlayingPath;
  DateTime? _nowPlayingAt;

  bool get isAvailable => LastFmCredentials.isConfigured;

  /// 启动周期冲刷，并立刻尝试一次（把上次退出时残留的记录补上）。
  void start() {
    if (_started) return;
    _started = true;
    unawaited(_auth.loadSession());
    _flushTimer = Timer.periodic(flushInterval, (_) => unawaited(flush()));
    unawaited(flush());
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _started = false;
  }

  /// 播放位置更新（由 AudioService 每帧/每秒调用）。
  void onPositionUpdate({
    required MusicFile song,
    required Duration position,
    required bool isPlaying,
    required Duration duration,
  }) {
    if (!_shouldTrack(song)) {
      if (_tracker.currentPath != null) _tracker.reset();
      return;
    }

    final effectiveDuration = _resolveDuration(song, duration);
    final signal = _tracker.update(
      path: song.path,
      position: position,
      isPlaying: isPlaying,
      duration: effectiveDuration,
    );

    switch (signal) {
      case ScrobbleSignal.nowPlaying:
        unawaited(_sendNowPlaying(song, effectiveDuration));
      case ScrobbleSignal.scrobble:
        unawaited(_recordScrobble(song, effectiveDuration));
      case ScrobbleSignal.none:
        break;
    }
  }

  bool _shouldTrack(MusicFile song) {
    if (!isAvailable) return false;
    if (!_settings.lastFmScrobblingEnabled) return false;
    if (!_settings.lastFmScrobbleRemote &&
        RemoteMediaResolver.isRemoteUri(song.path)) {
      return false;
    }
    // 没有会话就没什么可做的；start() 已经触发过加载，这里只读内存。
    return _auth.cachedSession != null;
  }

  Duration? _resolveDuration(MusicFile song, Duration playerDuration) {
    if (playerDuration.inMilliseconds > 0) return playerDuration;
    final tagDuration = song.durationMillis;
    if (tagDuration != null && tagDuration > 0) {
      return Duration(milliseconds: tagDuration);
    }
    return null;
  }

  Future<void> _sendNowPlaying(MusicFile song, Duration? duration) async {
    final session = _auth.cachedSession;
    if (session == null) return;

    final now = DateTime.now();
    if (_nowPlayingPath == song.path &&
        _nowPlayingAt != null &&
        now.difference(_nowPlayingAt!) < nowPlayingThrottle) {
      return;
    }

    final entry = LastFmScrobbleEntry.fromSong(
      song,
      playedAt: now,
      durationSeconds: duration?.inSeconds,
    );
    if (entry == null) {
      debugPrint('LastFm: skip now playing for ${song.path} (missing tags)');
      return;
    }

    _nowPlayingPath = song.path;
    _nowPlayingAt = now;

    try {
      await _client.updateNowPlaying(sessionKey: session.key, entry: entry);
    } on LastFmApiException catch (error) {
      if (error.isSessionInvalid) {
        await _auth.invalidateSession();
        debugPrint('LastFm: session invalidated while sending now playing');
      } else {
        debugPrint('LastFm: updateNowPlaying failed: $error');
      }
    } catch (error) {
      debugPrint('LastFm: updateNowPlaying failed: $error');
    }
  }

  Future<void> _recordScrobble(MusicFile song, Duration? duration) async {
    final entry = LastFmScrobbleEntry.fromSong(
      song,
      playedAt: DateTime.now(),
      durationSeconds: duration?.inSeconds,
    );
    if (entry == null) {
      debugPrint('LastFm: skip scrobble for ${song.path} (missing tags)');
      return;
    }

    try {
      await _database.enqueueScrobble(
        ScrobbleQueuesCompanion.insert(
          artist: entry.artist,
          track: entry.track,
          playedAt: entry.playedAt.millisecondsSinceEpoch ~/ 1000,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          songPath: Value(song.path),
          album: Value(entry.album),
          albumArtist: Value(entry.albumArtist),
          mbid: Value(entry.mbid),
          durationSeconds: Value(entry.durationSeconds),
          trackNumber: Value(entry.trackNumber),
        ),
      );
      debugPrint('LastFm: queued scrobble "${entry.artist} - ${entry.track}"');
    } catch (error) {
      debugPrint('LastFm: failed to enqueue scrobble: $error');
      return;
    }

    await _refreshPendingCount();
    unawaited(flush());
  }

  /// 把队列里的记录批量提交。失败按错误类型决定保留、丢弃还是要求重授权。
  Future<void> flush() async {
    if (_flushing) return;
    if (!isAvailable || !_settings.lastFmScrobblingEnabled) return;

    final session =
        _auth.cachedSession ?? await _auth.loadSession(forceReload: true);
    if (session == null) return;

    _flushing = true;
    try {
      await _database.purgeDeadScrobbles();

      // 单轮最多 10 批（500 条），避免长时间占用队列。
      for (var round = 0; round < 10; round++) {
        final rows = await _database.takePendingScrobbles();
        if (rows.isEmpty) break;

        final ids = rows.map((row) => row.id).toList(growable: false);
        final entries = rows.map(_toEntry).toList(growable: false);

        try {
          final ack = await _client.scrobble(
            sessionKey: session.key,
            entries: entries,
          );
          await _database.deleteScrobbles(ids);
          lastScrobbleAt.value = DateTime.now();
          lastError.value = null;
          debugPrint(
            'LastFm: flushed ${ids.length} scrobbles ($ack)',
          );
        } on LastFmApiException catch (error) {
          lastError.value = error.message.isEmpty
              ? 'error ${error.code}'
              : error.message;

          if (error.isSessionInvalid) {
            await _auth.invalidateSession();
            // 凭证已失效，这批数据无论如何都传不上去，直接丢弃。
            await _database.deleteScrobbles(ids);
            debugPrint('LastFm: session invalid, cleared queued batch');
          } else {
            // 临时故障保留重试；永久性错误靠 attempts 上限淘汰，
            // 这里先累加计数，让下一轮跳过去处理更新的记录。
            await _database.markScrobblesFailed(ids, error.message);
            debugPrint('LastFm: scrobble batch failed: $error');
          }
          break;
        } catch (error) {
          lastError.value = '$error';
          await _database.markScrobblesFailed(ids, '$error');
          debugPrint('LastFm: scrobble batch failed: $error');
          break;
        }

        await Future<void>.delayed(_batchSpacing);
      }
    } finally {
      _flushing = false;
      await _refreshPendingCount();
    }
  }

  LastFmScrobbleEntry _toEntry(ScrobbleQueue row) {
    return LastFmScrobbleEntry(
      artist: row.artist,
      track: row.track,
      playedAt: DateTime.fromMillisecondsSinceEpoch(row.playedAt * 1000),
      album: row.album,
      albumArtist: row.albumArtist,
      mbid: row.mbid,
      durationSeconds: row.durationSeconds,
      trackNumber: row.trackNumber,
    );
  }

  Future<void> _refreshPendingCount() async {
    try {
      pendingCount.value = await _database.countPendingScrobbles();
    } catch (error) {
      debugPrint('LastFm: failed to count pending scrobbles: $error');
    }
  }
}
