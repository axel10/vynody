import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibe_flow/player/library/music_file_utils.dart';
import 'package:vibe_flow/player/scanner/scanner_repository.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'lan_device.dart';
import 'web_share_html.dart';

// Riverpod states for UI communication
class IncomingRequestNotifier extends Notifier<IncomingTransferRequest?> {
  @override
  IncomingTransferRequest? build() => null;
  void setRequest(IncomingTransferRequest? request) => state = request;
}
final incomingRequestProvider = NotifierProvider<IncomingRequestNotifier, IncomingTransferRequest?>(
  IncomingRequestNotifier.new,
);

class ActiveTransfersNotifier extends Notifier<List<TransferSession>> {
  @override
  List<TransferSession> build() => [];

  void addSession(TransferSession session) {
    state = [session, ...state];
  }

  void updateProgress(String id, int bytesTransferred, {TransferStatus? status}) {
    state = [
      for (final s in state)
        if (s.id == id)
          s.copyWith(
            bytesTransferred: bytesTransferred,
            status: status ?? s.status,
          )
        else
          s
    ];
  }

  void updateStatus(String id, TransferStatus status) {
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(status: status) else s
    ];
  }

  void clearCompleted() {
    state = state.where((s) => s.status == TransferStatus.transferring || s.status == TransferStatus.pending).toList();
  }
}
final activeTransfersProvider = NotifierProvider<ActiveTransfersNotifier, List<TransferSession>>(
  ActiveTransfersNotifier.new,
);

class IncomingTransferRequest {
  final String senderId;
  final String senderName;
  final List<TransferFileItem> files;
  final void Function(bool accepted) onDecision;

  IncomingTransferRequest({
    required this.senderId,
    required this.senderName,
    required this.files,
    required this.onDecision,
  });
}

class TransferFileItem {
  final String name;
  final int size;
  final int durationMs;

  TransferFileItem({
    required this.name,
    required this.size,
    required this.durationMs,
  });
}

enum TransferStatus { pending, transferring, success, failed, cancelled }

class TransferSession {
  final String id;
  final String fileName;
  final int totalBytes;
  final int bytesTransferred;
  final bool isSending; // true = upload/send, false = download/receive
  final String deviceName;
  final TransferStatus status;

  TransferSession({
    required this.id,
    required this.fileName,
    required this.totalBytes,
    required this.bytesTransferred,
    required this.isSending,
    required this.deviceName,
    required this.status,
  });

  double get progress => totalBytes > 0 ? bytesTransferred / totalBytes : 0.0;

  TransferSession copyWith({
    String? id,
    String? fileName,
    int? totalBytes,
    int? bytesTransferred,
    bool? isSending,
    String? deviceName,
    TransferStatus? status,
  }) {
    return TransferSession(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      isSending: isSending ?? this.isSending,
      deviceName: deviceName ?? this.deviceName,
      status: status ?? this.status,
    );
  }
}

// ActiveTransfersNotifier relocated to top of file

class SharingService {
  final Ref _ref;
  
  HttpServer? _httpServer;
  RawDatagramSocket? _udpSocket;
  Timer? _udpBroadcastTimer;
  
  String? _localIp;
  int? _httpPort;
  String _deviceId = '';
  String _deviceName = 'Unknown Device';
  String _deviceType = 'unknown';
  String _sharingFolderPath = '';

  final Map<String, _UploadRequestMetadata> _activeTokens = {};
  
  // Discovered devices list managed locally, updated to UI via Riverpod
  final StreamController<List<LanDevice>> _devicesController = StreamController<List<LanDevice>>.broadcast();
  final Map<String, LanDevice> _discoveredDevicesMap = {};
  Timer? _deviceCleanupTimer;

  SharingService(this._ref);

  Stream<List<LanDevice>> get discoveredDevicesStream => _devicesController.stream;
  List<LanDevice> get discoveredDevices => _discoveredDevicesMap.values.toList();
  
  String? get localIp => _localIp;
  int? get httpPort => _httpPort;
  String get deviceName => _deviceName;
  String get deviceType => _deviceType;
  String get sharingFolderPath => _sharingFolderPath;

  Future<void> init() async {
    // 1. Load or Generate Device ID
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('lan_share_device_id') ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1000000)}';
      await prefs.setString('lan_share_device_id', _deviceId);
    }

    // 2. Resolve Device Type and Name
    _deviceType = Platform.operatingSystem;
    _ref.read(scannerServiceProvider); // Make sure scanner service provider is referenced/initialized
    
    // We can query device name from Platform or standard system environment
    _deviceName = Platform.localHostname;
    try {
      if (Platform.isMacOS) {
        _deviceName = Platform.localHostname.replaceAll('.local', '');
      } else if (Platform.isWindows) {
        _deviceName = Platform.environment['COMPUTERNAME'] ?? Platform.localHostname;
      }
    } catch (_) {}

    // 3. Resolve Sharing Path
    await _resolveSharingPath();
  }

  Future<void> _resolveSharingPath() async {
    String basePath = '';
    if (Platform.isIOS) {
      final docDir = await getApplicationDocumentsDirectory();
      basePath = p.join(docDir.path, 'VibeFlow Music');
    } else if (Platform.isAndroid) {
      basePath = '/storage/emulated/0/Music/VibeFlow Music';
    } else if (Platform.isMacOS) {
      basePath = p.join(Platform.environment['HOME'] ?? '', 'Music', 'VibeFlow Music');
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      basePath = p.join(userProfile, 'Music', 'VibeFlow Music');
    } else {
      basePath = p.join(Platform.environment['HOME'] ?? '', 'Music', 'VibeFlow Music');
    }

    _sharingFolderPath = basePath;
    final dir = Directory(_sharingFolderPath);
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (e) {
        debugPrint('[SharingService] Failed to create sharing directory: $e');
        // Fallback to app documents
        final appDoc = await getApplicationDocumentsDirectory();
        _sharingFolderPath = p.join(appDoc.path, 'VibeFlow Music');
        Directory(_sharingFolderPath).createSync(recursive: true);
      }
    }
  }

  Future<void> _ensureRegisteredInScanner() async {
    final scanner = _ref.read(scannerServiceProvider);
    await scanner.ready;

    if (Platform.isIOS) {
      // iOS app sandbox path contains a dynamic UUID that can change on each run/update.
      // Clean up obsolete sharing folders from previous launches.
      final obsoletePaths = scanner.rootPaths.where((path) {
        return !p.equals(path, _sharingFolderPath) &&
            (path.endsWith('/Documents/VibeFlow Music') || path.endsWith('\\Documents\\VibeFlow Music'));
      }).toList();

      if (obsoletePaths.isNotEmpty) {
        debugPrint('[SharingService] Removing obsolete iOS sharing folders: $obsoletePaths');
        await scanner.removeRootPaths(obsoletePaths);
      }
    }

    if (!scanner.rootPaths.any((path) => p.equals(path, _sharingFolderPath))) {
      debugPrint('[SharingService] Adding sharing folder to scanner: $_sharingFolderPath');
      await scanner.addRootPath(_sharingFolderPath);
    }
  }

  Future<void> start() async {
    await init();
    await _ensureRegisteredInScanner();

    // 1. Resolve Local IP
    _localIp = await _getLocalIpAddress();
    if (_localIp == null) {
      debugPrint('[SharingService] No valid IPv4 local address found.');
      return;
    }

    // 2. Start HTTP Server on random port starting at 53536
    int port = 53536;
    while (_httpServer == null && port < 53600) {
      try {
        _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _httpPort = port;
        debugPrint('[SharingService] HTTP Server running on $_localIp:$_httpPort');
      } catch (e) {
        port++;
      }
    }

    if (_httpServer == null) {
      debugPrint('[SharingService] Failed to bind HTTP Server.');
      return;
    }

    _httpServer!.listen(_handleHttpRequest);

    // 3. Bind UDP Socket
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 53535);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen(
        _handleUdpEvent,
        onError: (e) {
          debugPrint('[SharingService] UDP Socket error: $e');
        },
      );
      debugPrint('[SharingService] UDP Discovery listening on port 53535');
    } catch (e) {
      debugPrint('[SharingService] UDP Socket binding failed: $e');
    }

    // 4. Start UDP Broadcast Timer (Every 3 seconds)
    _udpBroadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) => _broadcastDiscoveryPing());
    
    // 5. Start Device Cleanup Timer (Every 5 seconds)
    _deviceCleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) => _cleanupOfflineDevices());
  }

  Future<void> stop() async {
    _udpBroadcastTimer?.cancel();
    _udpBroadcastTimer = null;

    _deviceCleanupTimer?.cancel();
    _deviceCleanupTimer = null;

    await _httpServer?.close(force: true);
    _httpServer = null;

    _udpSocket?.close();
    _udpSocket = null;

    _discoveredDevicesMap.clear();
    _devicesController.add([]);
    
    debugPrint('[SharingService] Sharing service stopped.');
  }

  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        // Skip VPNs, virtual interfaces, loopbacks
        final name = interface.name.toLowerCase();
        if (name.contains('lo') || name.contains('tun') || name.contains('ppp') || name.contains('docker')) {
          continue;
        }
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
      // Fallback
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('[SharingService] Error resolving IP: $e');
    }
    return null;
  }

  // --- UDP Discovery Broadcast & Listening ---

  void _broadcastDiscoveryPing() {
    if (_udpSocket == null || _localIp == null || _httpPort == null) return;
    
    final payload = {
      'app': 'VibeFlow',
      'version': '0.11.0',
      'action': 'ping',
      'id': _deviceId,
      'name': _deviceName,
      'deviceType': _deviceType,
      'httpPort': _httpPort,
    };
    
    final bytes = utf8.encode(jsonEncode(payload));
    try {
      final bytesSent = _udpSocket!.send(bytes, InternetAddress('255.255.255.255'), 53535);
      debugPrint('[SharingService] _broadcastDiscoveryPing sent bytesSent=$bytesSent to 255.255.255.255:53535');
    } catch (e) {
      debugPrint('[SharingService] _broadcastDiscoveryPing send error: $e');
    }
  }

  void _sendUnicastPing(String targetIp, String action) {
    if (_udpSocket == null || _localIp == null || _httpPort == null) return;
    
    final payload = {
      'app': 'VibeFlow',
      'version': '0.11.0',
      'action': action,
      'id': _deviceId,
      'name': _deviceName,
      'deviceType': _deviceType,
      'httpPort': _httpPort,
    };
    
    final bytes = utf8.encode(jsonEncode(payload));
    try {
      final bytesSent = _udpSocket!.send(bytes, InternetAddress(targetIp), 53535);
      debugPrint('[SharingService] Sent unicast $action ($bytesSent bytes) to $targetIp:53535');
    } catch (e) {
      debugPrint('[SharingService] Failed to send unicast $action to $targetIp: $e');
    }
  }

  void _handleUdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _udpSocket == null) return;
    
    final datagram = _udpSocket!.receive();
    if (datagram == null) return;
    
    try {
      final text = utf8.decode(datagram.data);
      debugPrint('[SharingService] Received UDP packet from ${datagram.address.address}:${datagram.port}: $text');
      final json = jsonDecode(text) as Map<String, dynamic>;
      
      if (json['app'] == 'VibeFlow' && json['id'] != _deviceId) {
        final id = json['id'] as String;
        final senderIp = datagram.address.address;
        
        final device = LanDevice.fromJson(json, senderIp, DateTime.now());
        debugPrint('[SharingService] Discovered/Updated device: ${device.name} ($senderIp) isOnline=${device.isOnline}');
        
        _discoveredDevicesMap[id] = device;
        _devicesController.add(_discoveredDevicesMap.values.toList());

        // If we received a broadcast ping, reply with a unicast pong to the sender
        final action = json['action'] as String? ?? 'ping';
        if (action == 'ping') {
          _sendUnicastPing(senderIp, 'pong');
        }
      } else if (json['id'] == _deviceId) {
        // Ignored self ping
      } else {
        debugPrint('[SharingService] Ignored packet: app=${json['app']}, id=${json['id']}');
      }
    } catch (e) {
      debugPrint('[SharingService] Error parsing UDP packet: $e');
    }
  }

  void _cleanupOfflineDevices() {
    final now = DateTime.now();
    bool changed = false;
    
    _discoveredDevicesMap.forEach((id, device) {
      final diff = now.difference(device.lastSeen).inSeconds;
      if (diff >= 10 && device.isOnline) {
        // Change state to disconnected in the UI
        _discoveredDevicesMap[id] = device.copyWith(lastSeen: now.subtract(const Duration(seconds: 15)));
        changed = true;
      }
    });

    if (changed) {
      _devicesController.add(_discoveredDevicesMap.values.toList());
    }
  }

  // --- HTTP Request Handler ---

  Future<void> _handleHttpRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    // Set CORS headers
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization, X-File-Name');

    if (method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    try {
      if (method == 'GET' && path == '/') {
        // Serve Web UI
        request.response.headers.contentType = ContentType.html;
        request.response.write(webShareHtmlContent);
        await request.response.close();
      } else if (method == 'POST' && path == '/api/transfer/request') {
        await _handleTransferRequest(request);
      } else if (method == 'POST' && path == '/api/transfer/upload') {
        await _handleTransferUpload(request);
      } else if (method == 'GET' && path == '/api/songs') {
        await _handleGetSongsList(request);
      } else if (method == 'GET' && path == '/api/download') {
        await _handleDownloadSong(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (e) {
      debugPrint('[SharingService] Error handling request: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleTransferRequest(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    final json = jsonDecode(content) as Map<String, dynamic>;
    
    final senderId = json['sender_id'] as String? ?? 'unknown';
    final senderName = json['sender_name'] as String? ?? 'Unknown';
    final filesJson = json['files'] as List<dynamic>? ?? [];
    
    final files = filesJson.map((f) {
      final map = f as Map<String, dynamic>;
      return TransferFileItem(
        name: map['name'] as String? ?? 'Unnamed',
        size: map['size'] as int? ?? 0,
        durationMs: map['duration_ms'] as int? ?? 0,
      );
    }).toList();

    if (files.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'accepted': false, 'reason': 'No files specified'}));
      await request.response.close();
      return;
    }

    // Trigger UI Prompt
    final completer = Completer<bool>();
    _ref.read(incomingRequestProvider.notifier).setRequest(IncomingTransferRequest(
      senderId: senderId,
      senderName: senderName,
      files: files,
      onDecision: (accepted) {
        completer.complete(accepted);
        _ref.read(incomingRequestProvider.notifier).setRequest(null); // Clear request
      },
    ));

    // Wait for user input
    final accepted = await completer.future;

    if (accepted) {
      final token = 'tkn_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(100000)}';
      _activeTokens[token] = _UploadRequestMetadata(
        fileName: files[0].name,
        fileSize: files[0].size,
        senderName: senderName,
      );

      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({
        'accepted': true,
        'token': token,
      }));
    } else {
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({
        'accepted': false,
        'reason': 'Rejected by receiver',
      }));
    }
    await request.response.close();
  }

  Future<void> _handleTransferUpload(HttpRequest request) async {
    final auth = request.headers.value('Authorization') ?? '';
    final token = auth.replaceFirst('Bearer ', '').trim();
    
    if (!_activeTokens.containsKey(token)) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write(jsonEncode({'error': 'Invalid or expired upload token'}));
      await request.response.close();
      return;
    }

    final metadata = _activeTokens[token]!;
    
    // Fallback if client doesn't use standard request streaming body
    String fileName = metadata.fileName;
    final encodedFileName = request.headers.value('X-File-Name');
    if (encodedFileName != null) {
      try {
        fileName = Uri.decodeComponent(encodedFileName);
      } catch (_) {}
    }

    // Resolve duplicate name
    final extension = p.extension(fileName);
    final baseName = p.basenameWithoutExtension(fileName);
    String targetPath = p.join(_sharingFolderPath, fileName);
    int counter = 1;
    while (File(targetPath).existsSync()) {
      targetPath = p.join(_sharingFolderPath, '$baseName ($counter)$extension');
      counter++;
    }

    final targetFile = File(targetPath);
    final ioSink = targetFile.openWrite();
    
    final sessionId = token;
    _ref.read(activeTransfersProvider.notifier).addSession(TransferSession(
      id: sessionId,
      fileName: p.basename(targetPath),
      totalBytes: metadata.fileSize,
      bytesTransferred: 0,
      isSending: false,
      deviceName: metadata.senderName,
      status: TransferStatus.transferring,
    ));

    int bytesWritten = 0;
    try {
      await for (final chunk in request) {
        ioSink.add(chunk);
        bytesWritten += chunk.length;
        _ref.read(activeTransfersProvider.notifier).updateProgress(sessionId, bytesWritten);
      }
      await ioSink.flush();
      await ioSink.close();
      
      _ref.read(activeTransfersProvider.notifier).updateProgress(
        sessionId, 
        bytesWritten, 
        status: TransferStatus.success
      );
      
      _activeTokens.remove(token);

      // Trigger targeted Scanner rescan
      final scanner = _ref.read(scannerServiceProvider);
      unawaited(scanner.scan(clearScannedRoots: false));

      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({'success': true, 'path': targetPath}));
    } catch (e) {
      await ioSink.close();
      if (targetFile.existsSync()) {
        try {
          targetFile.deleteSync();
        } catch (_) {}
      }
      _ref.read(activeTransfersProvider.notifier).updateStatus(sessionId, TransferStatus.failed);
      
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'error': 'Transfer interrupted: $e'}));
    }
    await request.response.close();
  }

  Future<void> _handleGetSongsList(HttpRequest request) async {
    final repo = ScannerRepository();
    final songs = await repo.getAllSongMetadata();
    
    final list = songs.map((s) {
      return {
        'path': s.path,
        'name': p.basename(s.path),
        'title': s.title.isNotEmpty ? s.title : p.basenameWithoutExtension(s.path),
        'artist': s.artist,
        'album': s.album,
      };
    }).toList();

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(list));
    await request.response.close();
  }

  Future<void> _handleDownloadSong(HttpRequest request) async {
    final path = request.uri.queryParameters['id'] ?? '';
    if (path.isEmpty || !File(path).existsSync() || !MusicFileUtils.isMusicFilePath(path)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final file = File(path);
    final size = file.lengthSync();
    
    request.response.headers.contentType = ContentType('audio', 'mpeg', charset: 'utf-8');
    request.response.headers.contentLength = size;
    request.response.headers.add('Content-Disposition', 'attachment; filename="${Uri.encodeComponent(p.basename(path))}"');

    try {
      await file.openRead().pipe(request.response);
    } catch (_) {
      // Stream interrupted
    }
  }

  // --- Sending File to Remote App ---

  Future<bool> sendFile(LanDevice targetDevice, String filePath) async {
    if (!File(filePath).existsSync()) return false;
    
    final file = File(filePath);
    final size = file.lengthSync();
    final fileName = p.basename(filePath);
    
    final sessionId = 'send_${DateTime.now().millisecondsSinceEpoch}';
    _ref.read(activeTransfersProvider.notifier).addSession(TransferSession(
      id: sessionId,
      fileName: fileName,
      totalBytes: size,
      bytesTransferred: 0,
      isSending: true,
      deviceName: targetDevice.name,
      status: TransferStatus.pending,
    ));

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);

    try {
      // 1. Post Preflight Request
      final requestUri = Uri.parse('http://${targetDevice.ip}:${targetDevice.httpPort}/api/transfer/request');
      final request = await client.postUrl(requestUri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'sender_id': _deviceId,
        'sender_name': _deviceName,
        'files': [{ 'name': fileName, 'size': size, 'duration_ms': 0 }]
      }));
      
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        _ref.read(activeTransfersProvider.notifier).updateStatus(sessionId, TransferStatus.failed);
        return false;
      }
      
      final responseBody = await utf8.decoder.bind(response).join();
      final responseJson = jsonDecode(responseBody) as Map<String, dynamic>;
      
      if (!responseJson['accepted']) {
        _ref.read(activeTransfersProvider.notifier).updateStatus(sessionId, TransferStatus.cancelled);
        return false;
      }

      final token = responseJson['token'] as String;
      
      // 2. Perform Upload
      _ref.read(activeTransfersProvider.notifier).updateStatus(sessionId, TransferStatus.transferring);
      
      final uploadUri = Uri.parse('http://${targetDevice.ip}:${targetDevice.httpPort}/api/transfer/upload');
      final uploadRequest = await client.postUrl(uploadUri);
      uploadRequest.headers.add('Authorization', 'Bearer $token');
      uploadRequest.headers.add('X-File-Name', Uri.encodeComponent(fileName));
      uploadRequest.headers.contentType = ContentType.binary;
      uploadRequest.contentLength = size;

      final fileStream = file.openRead();
      int bytesSent = 0;
      
      await for (final chunk in fileStream) {
        uploadRequest.add(chunk);
        bytesSent += chunk.length;
        _ref.read(activeTransfersProvider.notifier).updateProgress(sessionId, bytesSent);
      }
      
      final uploadResponse = await uploadRequest.close();
      if (uploadResponse.statusCode == HttpStatus.ok) {
        _ref.read(activeTransfersProvider.notifier).updateProgress(sessionId, size, status: TransferStatus.success);
        return true;
      } else {
        _ref.read(activeTransfersProvider.notifier).updateStatus(sessionId, TransferStatus.failed);
        return false;
      }
    } catch (e) {
      debugPrint('[SharingService] Failed to send file: $e');
      _ref.read(activeTransfersProvider.notifier).updateStatus(sessionId, TransferStatus.failed);
      return false;
    } finally {
      client.close();
    }
  }
}

class _UploadRequestMetadata {
  final String fileName;
  final int fileSize;
  final String senderName;

  _UploadRequestMetadata({
    required this.fileName,
    required this.fileSize,
    required this.senderName,
  });
}
