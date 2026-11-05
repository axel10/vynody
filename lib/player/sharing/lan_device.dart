class LanDevice {
  final String id;
  final String name;
  final String deviceType; // 'macos', 'windows', 'linux', 'android', 'ios'
  final int httpPort;
  final String ip;
  final DateTime lastSeen;
  final bool isOnline;
  final String? certFingerprint;

  /// 对端声明支持的跨设备同步协议版本（mDNS TXT 的 `sync` 属性）。
  ///
  /// 缺省为 1：老客户端不广播这个属性，也就收不了分块请求和 gzip 请求体，
  /// 发送端要按 v1 的单请求格式发。不能用 `proto` 属性判断 —— 它从 TLS 那一版
  /// 起就恒为 `'2'`，老客户端一样会广播。
  final int syncProtocol;

  LanDevice({
    required this.id,
    required this.name,
    required this.deviceType,
    required this.httpPort,
    required this.ip,
    required this.lastSeen,
    required this.isOnline,
    this.certFingerprint,
    this.syncProtocol = 1,
  });

  /// 是否可以直接用 v2 的分块 / gzip 通道。
  bool get supportsChunkedSync => syncProtocol >= 2;

  LanDevice copyWith({
    String? id,
    String? name,
    String? deviceType,
    int? httpPort,
    String? ip,
    DateTime? lastSeen,
    bool? isOnline,
    String? certFingerprint,
    int? syncProtocol,
  }) {
    return LanDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceType: deviceType ?? this.deviceType,
      httpPort: httpPort ?? this.httpPort,
      ip: ip ?? this.ip,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
      certFingerprint: certFingerprint ?? this.certFingerprint,
      syncProtocol: syncProtocol ?? this.syncProtocol,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'deviceType': deviceType,
      'httpPort': httpPort,
      'ip': ip,
      'isOnline': isOnline,
      if (certFingerprint != null) 'certFingerprint': certFingerprint,
      // 只缓存不参与判断：信任设备列表里存的是离线快照，真正决定发什么格式的
      // 是本次发现时拿到的属性。
      'syncProtocol': syncProtocol,
    };
  }

  factory LanDevice.fromJson(Map<String, dynamic> json, String ipAddress, DateTime timestamp) {
    return LanDevice(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Device',
      deviceType: json['deviceType'] as String? ?? 'unknown',
      httpPort: json['httpPort'] as int? ?? 53536,
      ip: ipAddress,
      lastSeen: timestamp,
      isOnline: json['isOnline'] as bool? ?? true,
      certFingerprint: json['certFingerprint'] as String? ?? json['fp'] as String?,
      syncProtocol: json['syncProtocol'] as int? ?? 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanDevice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'LanDevice{id: $id, name: $name, deviceType: $deviceType, httpPort: $httpPort, ip: $ip, lastSeen: $lastSeen, isOnline: $isOnline, certFingerprint: $certFingerprint, syncProtocol: $syncProtocol}';
  }
}
