import 'dart:convert';
import 'dart:io';

import '../clients/subsonic_client.dart';

/// 二进制端点（Subsonic 的 `download.view`/`stream`、Jellyfin 下载、WebDAV GET）
/// 存在两类「HTTP 200，但内容根本不是音频」的响应：
///
///  1. 协议级失败 —— Subsonic/Navidrome 返回 `subsonic-response.status == "failed"`
///     的 JSON（服务端关闭下载时是 code 50）；
///  2. 反向代理/网关自身出错 —— 502/504 的自定义 HTML 错误页、目录列表、登录门户
///     （如 nginx 的 50x 页面、Cloudflare 的挑战页）。反代通常不看上游内容，
///     上游回了 200 它就直接透传，于是客户端拿到的是一张网页。
///
/// Dio 只看状态码，两者都会被当成「下载成功」写进音乐库。落盘前必须验一遍载荷形态。
///
/// 判定顺序刻意做成「先证明是音频，再证明不是」：
///  - 命中已知音频魔数（ID3/fLaC/OggS/RIFF/ftyp/MPEG 帧同步）→ 直接放行，
///    无论 Content-Type 写了什么（`text/plain` + 真音频的服务器确实存在）；
///  - 头部字节以 `{` 开头 → 交给 Subsonic 错误体解析，拿到真实错误码；
///  - Content-Type 是文档类型，或头部以 `<` 开头 → 判定为非媒体载荷。
///
/// 只读文件头 [_probeBytes] 字节：反代错误页可能几 MB，按文件大小设阈值会漏判。
class RemotePayloadGuard {
  RemotePayloadGuard._();

  /// 合成错误码：响应不是媒体。Subsonic 协议错误码都是正数，用负数区分。
  static const int errorNonMediaPayload = -1;

  /// 嗅探窗口。HTML 错误页的 `<html>`/`<!DOCTYPE` 一定落在最前面。
  static const int _probeBytes = 2048;

  /// JSON 错误体都很小；超过这个大小不再整份解码成字符串。
  static const int _maxJsonErrorBytes = 64 * 1024;

  /// 判断已下载的 [file] 是否是「非媒体载荷」。
  ///
  /// 返回 null 表示看起来是媒体（或无法判断，交给后续常规判定）；返回异常表示
  /// 调用方应当按失败处理，**不要**把文件搬进音乐库。
  ///
  /// [contentType] 传响应的 `Content-Type` 头；[parseSubsonicError] 仅在
  /// Subsonic 协议下为 true（Jellyfin/WebDAV 的 JSON 错误体不是这个结构）。
  static SubsonicException? inspect(
    File? file, {
    String? contentType,
    bool parseSubsonicError = true,
  }) {
    try {
      if (file == null || !file.existsSync()) return null;
      final length = file.lengthSync();
      if (length == 0) return null; // 空响应由调用方按「空文件」处理

      final head = _readHead(file);
      if (head == null || head.isEmpty) return null;

      // 已知音频魔数：直接放行，避免 Content-Type 配错的服务器被误杀。
      if (_looksLikeAudio(head)) return null;

      final first = _firstSignificantByte(head);
      if (first == null) return null; // 全是空白，交给空响应分支

      // 1. Subsonic 失败体：优先返回真实错误码（code 50 等），文案才能精确。
      if (parseSubsonicError &&
          (first == 0x7B /* { */ || first == 0x5B /* [ */) &&
          length <= _maxJsonErrorBytes) {
        final body = _decodeUtf8(file);
        final error = body == null ? null : SubsonicClient.parseErrorBody(body);
        if (error != null) return error;
      }

      // 2. Content-Type 本身是文档类型 → 反代错误页/门户页。
      final type = _normalizeContentType(contentType);
      if (type != null && _isDocumentType(type)) {
        return RemotePayloadException(
          'Server returned $type instead of media',
          code: errorNonMediaPayload,
        );
      }

      // 3. 头部形态是标记语言或 JSON → 同样不是音频。
      if (first == 0x3C /* < */) {
        return const RemotePayloadException(
          'Server returned a markup document (HTML/XML) instead of media',
          code: errorNonMediaPayload,
        );
      }
      if (first == 0x7B /* { */ || first == 0x5B /* [ */) {
        return const RemotePayloadException(
          'Server returned JSON instead of media',
          code: errorNonMediaPayload,
        );
      }

      return null;
    } catch (_) {
      // 读不到就不要误杀下载。
      return null;
    }
  }

  /// 只读文件头，避免把几 MB 的错误页整个读进内存。
  static List<int>? _readHead(File file) {
    RandomAccessFile? raf;
    try {
      raf = file.openSync();
      final head = raf.readSync(_probeBytes);
      raf.closeSync();
      raf = null;
      return head;
    } catch (_) {
      return null;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  static String? _decodeUtf8(File file) {
    try {
      return utf8.decode(file.readAsBytesSync(), allowMalformed: false);
    } catch (_) {
      return null; // 非法 UTF-8 → 二进制媒体
    }
  }

  /// 跳过 UTF-8 BOM 与空白后返回第一个非空白字节。
  static int? _firstSignificantByte(List<int> bytes) {
    var i = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      i = 3;
    }
    while (i < bytes.length) {
      final b = bytes[i];
      if (b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D) {
        i++;
        continue;
      }
      return b;
    }
    return null;
  }

  /// 已知音频容器/编码的魔数。命中即可确认是媒体，不再做任何文本判断。
  static bool _looksLikeAudio(List<int> b) {
    if (b.length >= 3 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
      return true; // "ID3"
    }
    if (b.length >= 4) {
      final four = String.fromCharCodes(b.sublist(0, 4));
      if (four == 'fLaC' ||
          four == 'OggS' ||
          four == 'RIFF' ||
          four == 'FORM' ||
          four == 'wvpk' ||
          four == 'MAC ' ||
          four == 'DSD ') {
        return true;
      }
      // MP4/M4A：前 4 字节是 box 长度，紧接着 'ftyp'。
      if (b.length >= 8 && String.fromCharCodes(b.sublist(4, 8)) == 'ftyp') {
        return true;
      }
      // ASF/WMA 的 GUID 头。
      if (b[0] == 0x30 && b[1] == 0x26 && b[2] == 0xB2 && b[3] == 0x75) {
        return true;
      }
    }
    // MPEG 音频帧同步 / ADTS：0xFF 后跟 0xE0 掩码。
    if (b.length >= 2 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) {
      return true;
    }
    return false;
  }

  static String? _normalizeContentType(String? raw) {
    if (raw == null) return null;
    var value = raw.trim().toLowerCase();
    if (value.isEmpty) return null;
    final semi = value.indexOf(';');
    if (semi >= 0) value = value.substring(0, semi).trim();
    return value.isEmpty ? null : value;
  }

  /// 「一眼就不是媒体」的类型：文本/HTML/XML/JSON。反代错误页必然是其中之一，
  /// 而音频文件不会是 `text/html`。
  static bool _isDocumentType(String type) {
    if (type.startsWith('text/')) return true;
    return type == 'application/json' ||
        type == 'application/xml' ||
        type == 'application/xhtml+xml' ||
        type == 'application/problem+json' ||
        type == 'application/ld+json';
  }
}

/// 载荷不是媒体。继承 [SubsonicException]，让下载队列沿用同一套失败分支
/// （`e is SubsonicException`），同时用负错误码与协议错误码区分。
class RemotePayloadException extends SubsonicException {
  const RemotePayloadException(super.message, {super.code});
}
