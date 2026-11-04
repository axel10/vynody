import 'dart:io';
import 'dart:typed_data';

// 封面「内容签名」的唯一实现。
//
// 播放链路里有若干以「曲目路径」为键的缓存（模糊背景位图、网格背景纹理、
// 播放页的封面字节缓存）。标签补全 / 手动改标签会把同一首歌的封面换成
// 另一张：路径不变、内容变了，只按路径判等就会一直贴着旧封面。
//
// 这里统一提供两种签名，让这些缓存能感知「内容换了」：
// - artworkBytesSignature：手里已有封面字节时用；
// - artworkFileSignature：只拿到封面文件路径时用。
//
// 两者前缀不同（b / f），避免字节签名与文件签名偶然相等。

/// 封面字节的内容签名。
///
/// 不能用 `Uint8List.hashCode`：它是 identity hash，而每次播放都会新建一份
/// bytes，内容没变也会判成不同，导致缓存反复失效、过渡动画反复重启。
///
/// 取样「长度 + 头部 32KB + 尾部 32KB」做 FNV-1a：封面被重新编码后，容器头与
/// 早期熵编码数据必然变化，误命中旧签名的概率可以忽略；开销与文件大小解耦
/// （几 MB 的大封面也只扫 64KB）。
String artworkBytesSignature(Uint8List bytes) {
  const int sampleSize = 32 * 1024;
  const int fnvPrime = 0x01000193;
  int hash = 0x811c9dc5;

  void mix(int value) {
    hash ^= value & 0xFF;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }

  final int length = bytes.length;
  final int headEnd = length < sampleSize ? length : sampleSize;
  for (int i = 0; i < headEnd; i++) {
    mix(bytes[i]);
  }
  if (length > sampleSize * 2) {
    for (int i = length - sampleSize; i < length; i++) {
      mix(bytes[i]);
    }
  }
  mix(length);
  mix(length >> 8);
  mix(length >> 16);
  mix(length >> 24);
  return 'b${length.toRadixString(16)}_${hash.toRadixString(16)}';
}

/// 封面文件的签名：长度 + 最后修改时间。
///
/// 冷启动还没拿到封面字节时只能拿文件兜底；原地覆盖同一个封面文件同样能换
/// 签名。文件不存在 / 读取失败返回 `null`，调用方据此区分「没封面」与
/// 「还没加载出来」。
String? artworkFileSignature(String? path) {
  if (path == null || path.isEmpty) return null;
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final stat = file.statSync();
    return 'f${stat.size}_${stat.modified.millisecondsSinceEpoch}';
  } catch (_) {
    return null;
  }
}

/// 封面签名的统一入口：有字节按内容算，没字节按文件算。
///
/// 返回 `null` 是「确实没有封面」的信号——调用方据此丢弃上一张已失效的
/// 纹理 / 位图，而不是继续沿用（清除封面后画面不跟着变，就是这么来的）。
String? artworkSignatureOf({Uint8List? bytes, String? filePath}) {
  if (bytes != null && bytes.isNotEmpty) return artworkBytesSignature(bytes);
  return artworkFileSignature(filePath);
}
