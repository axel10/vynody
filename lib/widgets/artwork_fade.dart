import 'package:flutter/widgets.dart';

/// 所有封面/缩略图/头像从「未就位」到「就位」时使用的统一淡入时长。
///
/// 抽成常量是为了让 [SongThumbnail]、[ArtistAvatar] 这类各自管图片的组件
/// 用同一个节奏，不要再各写一个 280ms / 300ms。
const Duration kArtworkFadeInDuration = Duration(milliseconds: 280);

/// 统一的「首帧到达即淡入」`frameBuilder`。
///
/// 语义：图片源还没解出第一帧时**不绘制任何内容**（缩略图区保持空白），
/// 首帧到达后按 [kArtworkFadeInDuration] 淡入。
///
/// [wasSynchronouslyLoaded] 为 true 表示这一帧直接来自已解码的 ImageCache，
/// 本来就不存在「未就位」阶段 —— 直接展示，否则列表滚动时会整片抖动。
Widget artworkFadeInFrameBuilder(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) {
    return child;
  }
  return AnimatedOpacity(
    opacity: frame == null ? 0.0 : 1.0,
    duration: kArtworkFadeInDuration,
    curve: Curves.easeOutCubic,
    child: child,
  );
}
