part of 'gemini_lyrics_service.dart';

class _GeminiFileUploadResult {
  final String name;
  final String uri;
  final String? state;

  const _GeminiFileUploadResult({
    required this.name,
    required this.uri,
    this.state,
  });
}

class _GeminiLyricsApiClient {
  _GeminiLyricsApiClient({NetworkClient? client})
    : _client = client ?? NetworkClient.instance;

  final NetworkClient _client;

  Future<String?> loadApiKey() async {
    return GeminiApiKeyService().loadApiKey();
  }

  Future<_GeminiFileUploadResult?> uploadFile({
    required File file,
    required String apiKey,
    required String mimeType,
    void Function(double progress)? onUploadProgress,
  }) async {
    final fileSize = await file.length();
    final fileName = p.basename(file.path);
    final fileBytes = await file.readAsBytes();

    final initResponse = await _client.post(
      'https://generativelanguage.googleapis.com/upload/v1beta/files',
      queryParameters: {'key': apiKey},
      options: Options(
        headers: {
          'X-Goog-Upload-Protocol': 'resumable',
          'X-Goog-Upload-Command': 'start',
          'X-Goog-Upload-Header-Content-Length': fileSize,
          'X-Goog-Upload-Header-Content-Type': mimeType,
          'Content-Type': 'application/json',
        },
      ),
      data: {
        'file': {'display_name': fileName},
      },
    );

    debugPrint('[GeminiLyrics] upload init fileName=$fileName');
    debugPrint('[GeminiLyrics] upload init mimeType=$mimeType');
    debugPrint('[GeminiLyrics] upload init fileSize=$fileSize');

    final uploadUrl = initResponse.headers.value('X-Goog-Upload-URL');
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw Exception('未能获取 Gemini 上传 URL');
    }

    debugPrint('[GeminiLyrics] upload session url=$uploadUrl');

    final uploadResponse = await _client.post(
      uploadUrl,
      options: Options(
        headers: {
          'X-Goog-Upload-Protocol': 'resumable',
          'X-Goog-Upload-Command': 'upload, finalize',
          'X-Goog-Upload-Offset': 0,
          Headers.contentLengthHeader: fileBytes.length,
        },
        contentType: mimeType,
      ),
      data: fileBytes,
      onSendProgress: (sent, total) {
        if (total <= 0) return;
        onUploadProgress?.call(sent / total);
      },
    );

    debugPrint(
      '[GeminiLyrics] upload response status=${uploadResponse.statusCode}',
    );
    debugPrint('[GeminiLyrics] upload response data=${uploadResponse.data}');

    final uploadedFile = parseUploadedFile(uploadResponse.data);
    if (uploadedFile == null) {
      throw Exception('未能从 Gemini 上传响应中解析文件信息');
    }

    return uploadedFile;
  }

  Future<bool> waitForFileActive({
    required String fileName,
    required String apiKey,
    String? initialState,
  }) async {
    final normalizedInitialState = initialState?.trim().toUpperCase();
    if (normalizedInitialState == null || normalizedInitialState.isEmpty) {
      return true;
    }
    if (normalizedInitialState == 'ACTIVE') {
      return true;
    }

    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));

      final info = await fetchFileInfo(fileName, apiKey);
      final state = info?.state?.trim().toUpperCase();
      if (state == null || state == 'ACTIVE') {
        return true;
      }
      if (state == 'FAILED') {
        throw Exception('Gemini 文件处理失败: $fileName');
      }
    }

    return false;
  }

  Future<_GeminiFileUploadResult?> fetchFileInfo(
    String fileName,
    String apiKey,
  ) async {
    final response = await _client.get(
      'https://generativelanguage.googleapis.com/v1beta/$fileName',
      queryParameters: {'key': apiKey},
    );
    return parseUploadedFile(response.data);
  }

  _GeminiFileUploadResult? parseUploadedFile(dynamic data) {
    if (data is! Map) return null;

    final root = data['file'];
    final fileMap = root is Map ? root : data;
    final name = fileMap['name']?.toString().trim();
    final uri = fileMap['uri']?.toString().trim();
    if (name == null || name.isEmpty || uri == null || uri.isEmpty) {
      return null;
    }

    final state = fileMap['state']?.toString();
    return _GeminiFileUploadResult(name: name, uri: uri, state: state);
  }

  String mimeTypeForFilePath(String filePath) {
    switch (p.extension(filePath).toLowerCase()) {
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
      case '.mp4':
      case '.m4b':
        return 'audio/mp4';
      case '.flac':
        return 'audio/flac';
      case '.wav':
        return 'audio/wav';
      case '.aac':
        return 'audio/aac';
      case '.ogg':
        return 'audio/ogg';
      case '.opus':
        return 'audio/opus';
      case '.webm':
        return 'audio/webm';
      case '.wma':
        return 'audio/x-ms-wma';
      default:
        return 'application/octet-stream';
    }
  }
}
