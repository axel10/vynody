import 'package:flutter/material.dart';

/// 全局返回图标：一笔画成的圆角左向折角，不带横贯箭身的直杆。
///
/// 折角图形比带杆箭头窄一截，同字号下观感偏轻，因此各处在用它时应把
/// `size` 比原来的 `arrow_back` 抬高一档（导航栏/胶囊 20 → 22，圆钮 18 → 20）。
const IconData kAppBackIcon = Icons.chevron_left_rounded;
