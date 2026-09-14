enum AuthKind { password, privateKey }

class HostProfile {
  const HostProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authKind,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final AuthKind authKind;

  HostProfile copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    AuthKind? authKind,
  }) {
    return HostProfile(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authKind: authKind ?? this.authKind,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'authKind': authKind.name,
      };

  factory HostProfile.fromJson(Map<String, Object?> json) {
    return HostProfile(
      id: json['id']! as String,
      name: json['name']! as String,
      host: json['host']! as String,
      port: (json['port'] as num).toInt(),
      username: json['username']! as String,
      authKind: AuthKind.values.byName(json['authKind']! as String),
    );
  }
}

class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;

  String get displayError {
    final err = stderr.trim();
    if (err.isNotEmpty) return err;
    if (!ok) return '退出码 $exitCode';
    return '';
  }
}

class HostMetrics {
  const HostMetrics({
    required this.cpuPercent,
    required this.memUsedBytes,
    required this.memTotalBytes,
    required this.swapUsedBytes,
    required this.swapTotalBytes,
    required this.diskUsedBytes,
    required this.diskTotalBytes,
    required this.load1,
    required this.uptime,
  });

  final double cpuPercent;
  final int memUsedBytes;
  final int memTotalBytes;
  final int swapUsedBytes;
  final int swapTotalBytes;
  final int diskUsedBytes;
  final int diskTotalBytes;
  final double load1;
  final String uptime;

  double get memPercent =>
      memTotalBytes == 0 ? 0 : memUsedBytes / memTotalBytes * 100;
  double get swapPercent =>
      swapTotalBytes == 0 ? 0 : swapUsedBytes / swapTotalBytes * 100;
  double get diskPercent =>
      diskTotalBytes == 0 ? 0 : diskUsedBytes / diskTotalBytes * 100;
}

class ServiceUnit {
  const ServiceUnit({
    required this.name,
    required this.load,
    required this.active,
    required this.sub,
    required this.description,
  });

  final String name;
  final String load;
  final String active;
  final String sub;
  final String description;

  bool get running => active == 'active';
}

class DockerContainer {
  const DockerContainer({
    required this.id,
    required this.names,
    required this.image,
    required this.status,
    required this.state,
    required this.ports,
  });

  final String id;
  final String names;
  final String image;
  final String status;
  final String state;
  final String ports;

  bool get running => state.toLowerCase() == 'running';

  String get primaryName => names.split(',').first;
}

class DockerImageInfo {
  const DockerImageInfo({
    required this.id,
    required this.repository,
    required this.tag,
    required this.size,
  });

  final String id;
  final String repository;
  final String tag;
  final String size;

  String get ref {
    if (repository == '<none>' || tag == '<none>') return id;
    return '$repository:$tag';
  }
}
