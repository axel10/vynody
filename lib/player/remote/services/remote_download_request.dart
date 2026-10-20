import '../../../models/music_file.dart';
import '../remote_server_models.dart';

/// 远程下载的落盘层级，由「触发下载的页面 / 栏目」决定，与勾选一首还是多首无关。
///
/// 同一页面里的单曲下载和批量下载必须用同一个 layout，否则用户会看到同样是
/// 「下载这首歌」，勾一首落 [album]、勾多首落 [artist]，目录凭空多一层。
///
/// - [album]：专辑页、歌曲列表、搜索到的歌曲 → `<专辑>/NN - 曲目`
/// - [artist]：艺术家页 → `<艺术家>/<专辑>/NN - 曲目`
/// - [playlist]：歌单页 → `<歌单>/NN - 曲目`
enum RemoteDownloadLayout {
  album,
  artist,
  playlist,
}

/// 一批「同一个集合」的曲目 + 该集合的落盘规则。
///
/// 勾选多个艺术家 / 多个歌单时，每个集合各成一批，这样集合目录名能跟着
/// 各自的集合走，而不是全库共用一个目录。
class RemoteDownloadBatch {
  const RemoteDownloadBatch({
    required this.songs,
    this.layout = RemoteDownloadLayout.album,
    this.collectionFolder,
  });

  final List<MusicFile> songs;

  /// 落盘层级，语义见 [RemoteDownloadLayout]。
  final RemoteDownloadLayout layout;

  /// 集合目录名（艺术家名 / 歌单名）；[RemoteDownloadLayout.album] 不需要。
  final String? collectionFolder;

  int get songCount => songs.length;
  bool get isEmpty => songs.isEmpty;
}

/// 一次远程下载请求。
///
/// 这是结构化媒体服务器（Subsonic / Jellyfin）唯一的入队入口：调用方只描述
/// 「哪些曲目、按什么层级落盘」，不再关心协议、去重、并发调度和进度上报。
class RemoteDownloadRequest {
  /// 单集合请求：整张专辑、一位艺术家、一个歌单，或一首歌。
  RemoteDownloadRequest({
    required this.server,
    required this.password,
    required List<MusicFile> songs,
    RemoteDownloadLayout layout = RemoteDownloadLayout.album,
    String? collectionFolder,
  }) : batches = songs.isEmpty
            ? const []
            : [
                RemoteDownloadBatch(
                  songs: songs,
                  layout: layout,
                  collectionFolder: collectionFolder,
                ),
              ];

  /// 多集合请求：勾选了多个艺术家 / 多个歌单时，每个集合一批。
  const RemoteDownloadRequest.grouped({
    required this.server,
    required this.password,
    required this.batches,
  });

  final RemoteServer server;
  final String password;

  /// 按「集合」拆分的曲目批次，空批次会被入队流程忽略。
  final List<RemoteDownloadBatch> batches;

  int get songCount =>
      batches.fold(0, (sum, batch) => sum + batch.songs.length);

  bool get isEmpty => songCount == 0;

  Iterable<MusicFile> get songs => batches.expand((batch) => batch.songs);

  List<RemoteDownloadBatch> get nonEmptyBatches =>
      batches.where((batch) => !batch.isEmpty).toList();
}
