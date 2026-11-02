/// 远程元数据「有没有读全」的唯一判定点。
///
/// `metadataTextScanned` 的语义在这里被收紧成三态：
///
/// * `null` —— 还没试过解析；
/// * `< 0`  —— 试过，但读取失败或短读。TagLib 对「读不全的标签」是一声不吭地整块
///   丢掉，产出和「这文件本来就没标签」一模一样（标题回落文件名、艺术家/专辑为空、
///   没有封面，但时长往往还在），所以必须自己记一笔，否则这种行会被当成解析成功
///   永久缓存，用户把文件下载到本地、刷新目录都不会再触发解析。
/// * `> 0`  —— 字节读全了，标签就这么多（哪怕真的为空），不必再联网。
///
/// 写入方是 `RemoteMetadataHelper`；历史版本把截断当成功写的是正数，
/// 由数据库迁移（schema 47）改成 [kRemoteMetadataNotFullyRead]。
library;

/// 「试过，但没读全」的标记值。负数，和真实毫秒时间戳不会撞。
const int kRemoteMetadataNotFullyRead = -1;

/// 这条记录是否需要（重新）联网解析。
bool remoteMetadataNeedsParse(int? metadataTextScanned) {
  if (metadataTextScanned == null) return true;
  return metadataTextScanned < 0;
}

/// 读取失败时写进 `metadataTextScanned` 的值。
int remoteMetadataFailureMarker() => kRemoteMetadataNotFullyRead;
