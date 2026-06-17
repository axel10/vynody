import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/player/scanner/scanner_repository.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:bonsoir/bonsoir.dart';
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

  void updateProgress(String id, int bytesTransferred, {TransferStatus? status, int? completedFilesCount}) {
    state = [
      for (final s in state)
        if (s.id == id)
          s.copyWith(
            bytesTransferred: bytesTransferred,
            status: status ?? s.status,
            completedFilesCount: completedFilesCount ?? s.completedFilesCount,
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
  final String? title;
  final String? artist;
  final String? album;
  final Map<String, dynamic>? lyricsPackage;

  TransferFileItem({
    required this.name,
    required this.size,
    required this.durationMs,
    this.title,
    this.artist,
    this.album,
    this.lyricsPackage,
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
  final int? filesCount;
  final int? completedFilesCount;

  TransferSession({
    required this.id,
    required this.fileName,
    required this.totalBytes,
    required this.bytesTransferred,
    required this.isSending,
    required this.deviceName,
    required this.status,
    this.filesCount,
    this.completedFilesCount,
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
    int? filesCount,
    int? completedFilesCount,
  }) {
    return TransferSession(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      isSending: isSending ?? this.isSending,
      deviceName: deviceName ?? this.deviceName,
      status: status ?? this.status,
      filesCount: filesCount ?? this.filesCount,
      completedFilesCount: completedFilesCount ?? this.completedFilesCount,
    );
  }
}

// ActiveTransfersNotifier relocated to top of file

class SharingService {
  final Ref _ref;
  
  HttpServer? _httpServer;
  BonsoirBroadcast? _bonsoirBroadcast;
  BonsoirDiscovery? _bonsoirDiscovery;
  
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
      } else if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        if (androidInfo.brand.isNotEmpty && !androidInfo.model.toLowerCase().startsWith(androidInfo.brand.toLowerCase())) {
          _deviceName = '${androidInfo.brand} ${androidInfo.model}';
        } else {
          _deviceName = androidInfo.model;
        }
      } else if (Platform.isIOS) {
        final deviceInfo = DeviceInfoPlugin();
        final iosInfo = await deviceInfo.iosInfo;
        _deviceName = iosInfo.name;
      }
    } catch (_) {}

    // 3. Resolve Sharing Path
    await _resolveSharingPath();
  }

  Future<void> _resolveSharingPath() async {
    String basePath = '';
    if (Platform.isIOS) {
      final docDir = await getApplicationDocumentsDirectory();
      basePath = p.join(docDir.path, 'Vynody Music');
    } else if (Platform.isAndroid) {
      basePath = '/storage/emulated/0/Music/Vynody Music';
    } else if (Platform.isMacOS) {
      basePath = p.join(Platform.environment['HOME'] ?? '', 'Music', 'Vynody Music');
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      basePath = p.join(userProfile, 'Music', 'Vynody Music');
    } else {
      basePath = p.join(Platform.environment['HOME'] ?? '', 'Music', 'Vynody Music');
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
        _sharingFolderPath = p.join(appDoc.path, 'Vynody Music');
        Directory(_sharingFolderPath).createSync(recursive: true);
      }
    }
  }

  Future<void> _cleanObsoleteIosPaths() async {
    if (!Platform.isIOS) return;
    final scanner = _ref.read(scannerServiceProvider);
    await scanner.ready;

    // iOS app sandbox path contains a dynamic UUID that can change on each run/update.
    // Clean up obsolete sharing folders from previous launches.
    final obsoletePaths = scanner.rootPaths.where((path) {
      return !p.equals(path, _sharingFolderPath) &&
          (path.endsWith('/Documents/Vynody Music') || path.endsWith('\\Documents\\Vynody Music'));
    }).toList();

    if (obsoletePaths.isNotEmpty) {
      debugPrint('[SharingService] Removing obsolete iOS sharing folders: $obsoletePaths');
      await scanner.removeRootPaths(obsoletePaths);
    }
  }

  Future<void> _ensureRegisteredInScanner() async {
    final scanner = _ref.read(scannerServiceProvider);
    await scanner.ready;

    if (!scanner.rootPaths.any((path) => p.equals(path, _sharingFolderPath))) {
      debugPrint('[SharingService] Adding sharing folder to scanner: $_sharingFolderPath');
      await scanner.addRootPath(_sharingFolderPath);
    }
  }

  Future<void> start() async {
    await init();
    await _cleanObsoleteIosPaths();

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

    // 3. Start Bonsoir Broadcast
    final service = BonsoirService(
      name: 'Vynody_$_deviceId',
      type: '_vynody-share._tcp',
      port: _httpPort!,
      attributes: {
        'id': _deviceId,
        'name': _deviceName,
        'deviceType': _deviceType,
        'version': '0.11.0',
      },
    );
    _bonsoirBroadcast = BonsoirBroadcast(service: service);
    try {
      await _bonsoirBroadcast!.initialize();
      await _bonsoirBroadcast!.start();
      debugPrint('[SharingService] Bonsoir broadcast started: Vynody_$_deviceId on port $_httpPort');
    } catch (e) {
      debugPrint('[SharingService] Bonsoir broadcast starting failed: $e');
    }

    // 4. Start Bonsoir Discovery
    _bonsoirDiscovery = BonsoirDiscovery(type: '_vynody-share._tcp');
    try {
      await _bonsoirDiscovery!.initialize();
      _bonsoirDiscovery!.eventStream!.listen((event) {
        if (_bonsoirDiscovery == null) return;
        
        if (event is BonsoirDiscoveryServiceFoundEvent) {
          debugPrint('[SharingService] mDNS Service found: ${event.service.name}');
          event.service.resolve(_bonsoirDiscovery!.serviceResolver);
        } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
          debugPrint('[SharingService] mDNS Service resolved: ${event.service.name}');
          final resolvedService = event.service;
          final attrs = resolvedService.attributes;
          
          final id = attrs['id'] ?? resolvedService.name.replaceFirst('Vynody_', '');
          if (id == _deviceId) {
            // Ignore self
            return;
          }
          
          final name = attrs['name'] ?? 'Unknown Device';
          final deviceType = attrs['deviceType'] ?? 'unknown';
          final httpPort = resolvedService.port;
          
          String? resolvedIp;
          for (final addressStr in resolvedService.hostAddresses) {
            final addr = InternetAddress.tryParse(addressStr);
            if (addr != null && addr.type == InternetAddressType.IPv4) {
              resolvedIp = addressStr;
              break;
            }
          }
          
          if (resolvedIp != null) {
            final device = LanDevice(
              id: id,
              name: name,
              deviceType: deviceType,
              httpPort: httpPort,
              ip: resolvedIp,
              lastSeen: DateTime.now(),
              isOnline: true,
            );
            debugPrint('[SharingService] Discovered/Updated device: ${device.name} ($resolvedIp) isOnline=${device.isOnline}');
            _discoveredDevicesMap[id] = device;
            _devicesController.add(_discoveredDevicesMap.values.toList());
          }
        } else if (event is BonsoirDiscoveryServiceLostEvent) {
          debugPrint('[SharingService] mDNS Service lost: ${event.service.name}');
          final lostService = event.service;
          final id = lostService.name.replaceFirst('Vynody_', '');
          if (_discoveredDevicesMap.containsKey(id)) {
            final device = _discoveredDevicesMap[id]!;
            if (device.isOnline) {
              _discoveredDevicesMap[id] = device.copyWith(
                isOnline: false,
              );
              _devicesController.add(_discoveredDevicesMap.values.toList());
            }
          }
        }
      });
      await _bonsoirDiscovery!.start();
      debugPrint('[SharingService] Bonsoir discovery started');
    } catch (e) {
      debugPrint('[SharingService] Bonsoir discovery starting failed: $e');
    }
  }

  Future<void> stop() async {
    if (_bonsoirBroadcast != null) {
      try {
        await _bonsoirBroadcast!.stop();
      } catch (e) {
        debugPrint('[SharingService] Error stopping Bonsoir broadcast: $e');
      }
      _bonsoirBroadcast = null;
    }

    if (_bonsoirDiscovery != null) {
      try {
        await _bonsoirDiscovery!.stop();
      } catch (e) {
        debugPrint('[SharingService] Error stopping Bonsoir discovery: $e');
      }
      _bonsoirDiscovery = null;
    }

    await _httpServer?.close(force: true);
    _httpServer = null;

    _discoveredDevicesMap.clear();
    _devicesController.add([]);
    
    debugPrint('[SharingService] Sharing service stopped.');
  }

  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      
      // Filter out unwanted interfaces (cellular, virtual, VPN, loopback, AWDL)
      final filteredInterfaces = interfaces.where((interface) {
        final name = interface.name.toLowerCase();
        
        // Skip loopback, VPNs, tunnels, virtual machines
        if (name.contains('lo') || 
            name.contains('tun') || 
            name.contains('ppp') || 
            name.contains('docker') || 
            name.contains('vbox') || 
            name.contains('vmnet')) {
          return false;
        }
        
        // Skip cellular interfaces
        if (name.contains('pdp_ip') || 
            name.contains('rmnet') || 
            name.contains('ccmni') || 
            name.contains('cellular') || 
            name.contains('mobile')) {
          return false;
        }
        
        // Skip Apple Wireless Direct Link (AirDrop, etc.)
        if (name.contains('awdl')) {
          return false;
        }
        
        return true;
      }).toList();

      // Prioritize Wi-Fi and Ethernet interfaces
      filteredInterfaces.sort((a, b) {
        final nameA = a.name.toLowerCase();
        final nameB = b.name.toLowerCase();
        
        final isWifiOrEthA = nameA.contains('en') || 
                             nameA.contains('wlan') || 
                             nameA.contains('eth') || 
                             nameA.contains('wifi') || 
                             nameA.contains('ethernet');
                            
        final isWifiOrEthB = nameB.contains('en') || 
                             nameB.contains('wlan') || 
                             nameB.contains('eth') || 
                             nameB.contains('wifi') || 
                             nameB.contains('ethernet');
        
        if (isWifiOrEthA && !isWifiOrEthB) return -1;
        if (!isWifiOrEthA && isWifiOrEthB) return 1;
        return 0;
      });

      for (final interface in filteredInterfaces) {
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

  // --- mDNS Discovery (Bonsoir) Helper methods ---

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
      } else if (method == 'GET' && path == '/api/lyrics/export') {
        await _handleExportLyrics(request);
      } else if (method == 'POST' && path == '/api/lyrics/import') {
        await _handleImportLyrics(request);
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

  String _deriveSessionName(List<TransferFileItem> files) {
    if (files.isEmpty) return '未命名传输';
    if (files.length == 1) return files[0].name;
    
    final firstPath = files[0].name;
    final parts = p.split(firstPath);
    if (parts.length > 1) {
      return parts[0];
    }
    return '批量传输 (${files.length} 个文件)';
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
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        lyricsPackage: map['lyrics_package'] as Map<String, dynamic>?,
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
      final totalSize = files.fold<int>(0, (sum, f) => sum + f.size);
      final sessionName = _deriveSessionName(files);

      _activeTokens[token] = _UploadRequestMetadata(
        sessionName: sessionName,
        files: files,
        totalSize: totalSize,
        senderName: senderName,
      );

      // Add TransferSession on receiver side immediately upon acceptance
      _ref.read(activeTransfersProvider.notifier).addSession(TransferSession(
        id: token,
        fileName: files.length > 1 ? '$sessionName (${files.length}个文件)' : sessionName,
        totalBytes: totalSize,
        bytesTransferred: 0,
        isSending: false,
        deviceName: senderName,
        status: TransferStatus.transferring,
        filesCount: files.length,
        completedFilesCount: 0,
      ));

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
    String relativePath = metadata.sessionName;
    final encodedFileName = request.headers.value('X-File-Name');
    if (encodedFileName != null) {
      try {
        relativePath = Uri.decodeComponent(encodedFileName);
      } catch (_) {}
    }

    // Resolve target path (which may contain relative subfolders)
    String targetPath = p.join(_sharingFolderPath, relativePath);
    
    // Resolve duplicate name, keeping relative subfolder structure
    final file = File(targetPath);
    if (file.existsSync()) {
      final extension = p.extension(relativePath);
      final dirName = p.dirname(relativePath);
      final baseName = p.basenameWithoutExtension(relativePath);
      int counter = 1;
      while (true) {
        final newRelative = dirName == '.' 
            ? '$baseName ($counter)$extension'
            : p.join(dirName, '$baseName ($counter)$extension');
        targetPath = p.join(_sharingFolderPath, newRelative);
        if (!File(targetPath).existsSync()) {
          break;
        }
        counter++;
      }
    }

    final targetFile = File(targetPath);
    // Ensure parent directories exist
    final parentDir = targetFile.parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }

    final ioSink = targetFile.openWrite();
    final sessionId = token;

    try {
      await for (final chunk in request) {
        ioSink.add(chunk);
        
        final newCumulative = metadata.bytesTransferredCumulative + chunk.length;
        metadata.bytesTransferredCumulative = newCumulative;
        
        _ref.read(activeTransfersProvider.notifier).updateProgress(
          sessionId, 
          newCumulative,
        );
      }
      await ioSink.flush();
      await ioSink.close();

      // Ensure the sharing folder is added to scanner now that we have received a file
      await _ensureRegisteredInScanner();
      
      // Save lyrics package if available
      try {
        final fileItem = metadata.files.firstWhere(
          (f) => f.name == relativePath,
          orElse: () => metadata.files.firstWhere(
            (f) => p.basename(f.name) == p.basename(relativePath),
            orElse: () => TransferFileItem(name: '', size: 0, durationMs: 0),
          ),
        );
        if (fileItem.name.isNotEmpty && fileItem.lyricsPackage != null) {
          final localQuery = LyricsQuery(
            filePath: targetPath,
            fileName: p.basename(targetPath),
            title: fileItem.title ?? p.basenameWithoutExtension(targetPath),
            artist: fileItem.artist,
            album: fileItem.album,
            duration: fileItem.durationMs > 0 ? Duration(milliseconds: fileItem.durationMs) : null,
          );
          await _importLyricsPackageWithConflict(
            localCacheKey: localQuery.cacheKey,
            incomingPackage: fileItem.lyricsPackage!,
          );
        }
      } catch (e) {
        debugPrint('[SharingService] Error importing lyrics package: $e');
      }

      // Track completed file
      metadata.completedFiles.add(relativePath);
      
      // Check if all files in the metadata session are completed
      final allFiles = metadata.files.map((f) => f.name).toSet();
      final isFinished = metadata.completedFiles.containsAll(allFiles) ||
                         metadata.completedFiles.length >= metadata.files.length;
      
      if (isFinished) {
        _ref.read(activeTransfersProvider.notifier).updateProgress(
          sessionId, 
          metadata.totalSize, 
          status: TransferStatus.success,
          completedFilesCount: metadata.completedFiles.length,
        );
        _activeTokens.remove(token);

        // Trigger targeted Scanner rescan
        final scanner = _ref.read(scannerServiceProvider);
        unawaited(scanner.scan(clearScannedRoots: false));
      } else {
        _ref.read(activeTransfersProvider.notifier).updateProgress(
          sessionId,
          metadata.bytesTransferredCumulative,
          completedFilesCount: metadata.completedFiles.length,
        );
      }

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
      _activeTokens.remove(token);
      
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

  Future<bool> sendFile(LanDevice targetDevice, String filePath) {
    return sendFiles(
      targetDevice: targetDevice,
      filePaths: [filePath],
    );
  }

  Future<bool> sendFiles({
    required LanDevice targetDevice,
    required List<String> filePaths,
    String? baseSourcePath,
  }) async {
    final List<Map<String, dynamic>> filesPayload = [];
    final List<_FileToSend> filesToSend = [];
    int totalSize = 0;

    for (final path in filePaths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      
      final size = file.lengthSync();
      totalSize += size;
      
      String relativeName = p.basename(path);
      if (baseSourcePath != null) {
        relativeName = p.relative(path, from: baseSourcePath);
      }

      Map<String, dynamic>? lyricsPackage;
      SongMetadata? song;
      try {
        song = await MetadataDatabase().getSongMetadata(path);
        if (song != null) {
          final query = LyricsQuery(
            filePath: song.path,
            fileName: p.basename(song.path),
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: song.duration != null ? Duration(milliseconds: song.duration!) : null,
          );
          final cacheRecord = await MetadataDatabase().getLyricsCache(query.cacheKey);
          if (cacheRecord != null && cacheRecord.source != LyricsCacheSource.none) {
            final translations = await MetadataDatabase().getLyricsTranslationCaches(query.cacheKey);
            lyricsPackage = {
              'lyrics_cache': cacheRecord.toMap(),
              'translations': translations.map((t) => t.toMap()).toList(),
            };
          }
        }
      } catch (e) {
        debugPrint('[SharingService] Error reading local lyrics for file $path: $e');
      }
      
      filesPayload.add({
        'name': relativeName,
        'size': size,
        'duration_ms': song?.duration ?? 0,
        'title': song?.title,
        'artist': song?.artist,
        'album': song?.album,
        'lyrics_package': lyricsPackage,
      });
      
      filesToSend.add(_FileToSend(path: path, relativeName: relativeName, size: size));
    }

    if (filesToSend.isEmpty) return false;

    // Derive display name for progress dialog
    final firstRelPath = filesToSend[0].relativeName;
    final parts = p.split(firstRelPath);
    final sessionName = parts.length > 1 ? parts[0] : p.basename(filesToSend[0].path);

    final sessionId = 'send_${DateTime.now().millisecondsSinceEpoch}';
    _ref.read(activeTransfersProvider.notifier).addSession(TransferSession(
      id: sessionId,
      fileName: filesToSend.length > 1 ? '$sessionName (${filesToSend.length}个文件)' : sessionName,
      totalBytes: totalSize,
      bytesTransferred: 0,
      isSending: true,
      deviceName: targetDevice.name,
      status: TransferStatus.pending,
      filesCount: filesToSend.length,
      completedFilesCount: 0,
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
        'files': filesPayload,
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
      
      // 2. Perform Uploads sequentially
      _ref.read(activeTransfersProvider.notifier).updateStatus(sessionId, TransferStatus.transferring);
      
      int totalBytesSent = 0;
      int completedFilesCount = 0;

      for (final fileInfo in filesToSend) {
        final uploadUri = Uri.parse('http://${targetDevice.ip}:${targetDevice.httpPort}/api/transfer/upload');
        final uploadRequest = await client.postUrl(uploadUri);
        uploadRequest.headers.add('Authorization', 'Bearer $token');
        uploadRequest.headers.add('X-File-Name', Uri.encodeComponent(fileInfo.relativeName));
        uploadRequest.headers.contentType = ContentType.binary;
        uploadRequest.contentLength = fileInfo.size;

        final fileStream = File(fileInfo.path).openRead();
        
        try {
          await for (final chunk in fileStream) {
            uploadRequest.add(chunk);
            totalBytesSent += chunk.length;
            _ref.read(activeTransfersProvider.notifier).updateProgress(
              sessionId, 
              totalBytesSent,
              completedFilesCount: completedFilesCount,
            );
          }
          final uploadResponse = await uploadRequest.close();
          if (uploadResponse.statusCode != HttpStatus.ok) {
            _ref.read(activeTransfersProvider.notifier).updateStatus(sessionId, TransferStatus.failed);
            return false;
          }
          completedFilesCount++;
          _ref.read(activeTransfersProvider.notifier).updateProgress(
            sessionId, 
            totalBytesSent,
            completedFilesCount: completedFilesCount,
          );
        } catch (e) {
          debugPrint('[SharingService] Error uploading file ${fileInfo.relativeName}: $e');
          _ref.read(activeTransfersProvider.notifier).updateStatus(sessionId, TransferStatus.failed);
          return false;
        }
      }
      
      _ref.read(activeTransfersProvider.notifier).updateProgress(
        sessionId, 
        totalSize, 
        status: TransferStatus.success,
        completedFilesCount: filesToSend.length,
      );
      return true;
    } catch (e) {
      debugPrint('[SharingService] Failed to send files: $e');
      _ref.read(activeTransfersProvider.notifier).updateStatus(sessionId, TransferStatus.failed);
      return false;
    } finally {
      client.close();
    }
  }

  Future<bool> _importLyricsPackageWithConflict({
    required String localCacheKey,
    required Map<String, dynamic> incomingPackage,
  }) async {
    final rawIncomingLyrics = incomingPackage['lyrics_cache'] as Map<String, dynamic>?;
    if (rawIncomingLyrics == null) return false;

    final incomingLyrics = LyricsCacheRecord.fromMap(rawIncomingLyrics);
    final incomingTranslations = (incomingPackage['translations'] as List<dynamic>?)
        ?.map((t) => LyricsTranslationCacheRecord.fromMap(t as Map<String, dynamic>))
        .toList() ?? [];

    final localLyrics = await MetadataDatabase().getLyricsCache(localCacheKey);
    bool shouldOverwrite = false;

    if (localLyrics == null) {
      shouldOverwrite = true;
    } else {
      final incomingPriority = _getLyricsSourcePriority(incomingLyrics.source);
      final localPriority = _getLyricsSourcePriority(localLyrics.source);

      if (incomingPriority > localPriority) {
        shouldOverwrite = true;
      } else if (incomingPriority == localPriority) {
        if (incomingLyrics.updatedAtMillis > localLyrics.updatedAtMillis) {
          shouldOverwrite = true;
        }
      }
    }

    if (shouldOverwrite) {
      debugPrint('[SharingService] Overwriting lyrics for cacheKey: $localCacheKey');
      
      final newRecord = LyricsCacheRecord(
        cacheKey: localCacheKey,
        source: incomingLyrics.source,
        isSynced: incomingLyrics.isSynced,
        syncedLyrics: incomingLyrics.syncedLyrics,
        syncedLines: incomingLyrics.syncedLines,
        timelineOffsetMillis: incomingLyrics.timelineOffsetMillis,
        updatedAtMillis: incomingLyrics.updatedAtMillis,
      );
      await MetadataDatabase().insertOrUpdateLyricsCache(newRecord);

      await MetadataDatabase().clearLyricsTranslationCacheByKey(localCacheKey);
      for (final translation in incomingTranslations) {
        final newTranslation = LyricsTranslationCacheRecord(
          cacheKey: localCacheKey,
          languageCode: translation.languageCode,
          translatedText: translation.translatedText,
          translatedLines: translation.translatedLines,
          provider: translation.provider,
          updatedAtMillis: translation.updatedAtMillis,
        );
        await MetadataDatabase().insertOrUpdateLyricsTranslationCache(newTranslation);
      }
      return true;
    }
    return false;
  }

  int _getLyricsSourcePriority(LyricsCacheSource source) {
    switch (source) {
      case LyricsCacheSource.manualAdjust:
        return 4;
      case LyricsCacheSource.ai:
      case LyricsCacheSource.aiTimeline:
      case LyricsCacheSource.aiGenerate:
        return 3;
      case LyricsCacheSource.lrclib:
        return 2;
      case LyricsCacheSource.none:
        return 1;
    }
  }

  bool _isMetadataMatch(String? a, String? b) {
    final normA = _normalizeMetadataString(a);
    final normB = _normalizeMetadataString(b);
    if (normA.isEmpty || normB.isEmpty) {
      return normA == normB;
    }
    return normA == normB;
  }

  String _normalizeMetadataString(String? s) {
    if (s == null) return '';
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '').trim();
  }

  Future<Map<String, int>> _importLyricsList(List<dynamic> lyrics) async {
    final localSongs = await MetadataDatabase().getAllSongMetadata();
    int matchedCount = 0;
    int overwrittenCount = 0;
    int skippedCount = 0;

    for (final item in lyrics) {
      final map = item as Map<String, dynamic>;
      final title = map['title'] as String? ?? '';
      final artist = map['artist'] as String? ?? '';
      final durationMs = map['duration_ms'] as int?;

      final matches = localSongs.where((song) {
        final titleMatch = _isMetadataMatch(song.title, title);
        final artistMatch = _isMetadataMatch(song.artist, artist);
        
        bool durationMatch = true;
        if (durationMs != null && song.duration != null) {
          durationMatch = (song.duration! - durationMs).abs() <= 3000;
        }
        return titleMatch && artistMatch && durationMatch;
      }).toList();

      if (matches.isEmpty) {
        skippedCount++;
        continue;
      }

      matchedCount += matches.length;

      for (final song in matches) {
        final localQuery = LyricsQuery(
          filePath: song.path,
          fileName: p.basename(song.path),
          title: song.title,
          artist: song.artist,
          album: song.album,
          duration: song.duration != null ? Duration(milliseconds: song.duration!) : null,
        );
        final localCacheKey = localQuery.cacheKey;
        
        final success = await _importLyricsPackageWithConflict(
          localCacheKey: localCacheKey,
          incomingPackage: map,
        );
        if (success) {
          overwrittenCount++;
        } else {
          skippedCount++;
        }
      }
    }

    return {
      'matched': matchedCount,
      'overwritten': overwrittenCount,
      'skipped': skippedCount,
    };
  }

  Future<Map<String, int>> syncLyricsToDevice(LanDevice targetDevice) async {
    final songs = await MetadataDatabase().getAllSongMetadata();
    final List<Map<String, dynamic>> exportedList = [];

    for (final song in songs) {
      final query = LyricsQuery(
        filePath: song.path,
        fileName: p.basename(song.path),
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration != null ? Duration(milliseconds: song.duration!) : null,
      );
      final cacheKey = query.cacheKey;
      final cacheRecord = await MetadataDatabase().getLyricsCache(cacheKey);

      if (cacheRecord != null && cacheRecord.source != LyricsCacheSource.none) {
        final translations = await MetadataDatabase().getLyricsTranslationCaches(cacheKey);
        exportedList.add({
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'duration_ms': song.duration,
          'lyrics_cache': cacheRecord.toMap(),
          'translations': translations.map((t) => t.toMap()).toList(),
        });
      }
    }

    if (exportedList.isEmpty) {
      return {'matched': 0, 'overwritten': 0, 'skipped': 0};
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse('http://${targetDevice.ip}:${targetDevice.httpPort}/api/lyrics/import');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'lyrics': exportedList}));
      
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        return {
          'matched': json['matched'] as int? ?? 0,
          'overwritten': json['overwritten'] as int? ?? 0,
          'skipped': json['skipped'] as int? ?? 0,
        };
      } else {
        throw Exception('Server returned status code ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<Map<String, int>> pullLyricsFromDevice(LanDevice targetDevice) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse('http://${targetDevice.ip}:${targetDevice.httpPort}/api/lyrics/export');
      final request = await client.getUrl(uri);
      final response = await request.close();
      
      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        
        final lyrics = json['lyrics'] as List<dynamic>? ?? [];
        return await _importLyricsList(lyrics);
      } else {
        throw Exception('Server returned status code ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> _handleExportLyrics(HttpRequest request) async {
    final songs = await MetadataDatabase().getAllSongMetadata();
    final List<Map<String, dynamic>> exportedList = [];

    for (final song in songs) {
      final query = LyricsQuery(
        filePath: song.path,
        fileName: p.basename(song.path),
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration != null ? Duration(milliseconds: song.duration!) : null,
      );
      final cacheKey = query.cacheKey;
      final cacheRecord = await MetadataDatabase().getLyricsCache(cacheKey);

      if (cacheRecord != null && cacheRecord.source != LyricsCacheSource.none) {
        final translations = await MetadataDatabase().getLyricsTranslationCaches(cacheKey);
        exportedList.add({
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'duration_ms': song.duration,
          'lyrics_cache': cacheRecord.toMap(),
          'translations': translations.map((t) => t.toMap()).toList(),
        });
      }
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'lyrics': exportedList}));
    await request.response.close();
  }

  Future<void> _handleImportLyrics(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final lyrics = json['lyrics'] as List<dynamic>? ?? [];
    
    final stats = await _importLyricsList(lyrics);
    
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(stats));
    await request.response.close();
  }
}

class _UploadRequestMetadata {
  final String sessionName;
  final List<TransferFileItem> files;
  final int totalSize;
  final String senderName;
  int bytesTransferredCumulative = 0;
  final Set<String> completedFiles = {};

  _UploadRequestMetadata({
    required this.sessionName,
    required this.files,
    required this.totalSize,
    required this.senderName,
  });
}

class _FileToSend {
  final String path;
  final String relativeName;
  final int size;
  _FileToSend({
    required this.path,
    required this.relativeName,
    required this.size,
  });
}
