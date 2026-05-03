import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'transcode_service.dart';

final transcodeServiceProvider = Provider<TranscodeService>((ref) {
  return TranscodeService();
});
