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
    required this.load5,
    required this.load15,
    required this.uptime,
    this.osName = 'Linux',
    this.cpuCores = 1,
  });

  final double cpuPercent;
  final int memUsedBytes;
  final int memTotalBytes;
  final int swapUsedBytes;
  final int swapTotalBytes;
  final int diskUsedBytes;
  final int diskTotalBytes;
  final double load1;
  final double load5;
  final double load15;
  final String uptime;
  final String osName;
  final int cpuCores;

  double get memPercent =>
      memTotalBytes == 0 ? 0 : memUsedBytes / memTotalBytes * 100;
  double get swapPercent =>
      swapTotalBytes == 0 ? 0 : swapUsedBytes / swapTotalBytes * 100;
  double get diskPercent =>
      diskTotalBytes == 0 ? 0 : diskUsedBytes / diskTotalBytes * 100;
}

enum ProcessMetricKind { cpu, memory, swap }

class ProcessItem {
  const ProcessItem({
    required this.pid,
    required this.user,
    required this.cpuPercent,
    required this.memPercent,
    required this.rssBytes,
    required this.comm,
    required this.args,
  });

  final int pid;
  final String user;
  final double cpuPercent;
  final double memPercent;
  final int rssBytes;
  final String comm;
  final String args;
}

class ServiceUnit {
  const ServiceUnit({
    required this.name,
    required this.load,
    required this.active,
    required this.sub,
    required this.description,
    this.isAppService = false,
    this.category = '系统服务',
  });

  final String name;
  final String load;
  final String active;
  final String sub;
  final String description;
  final bool isAppService;
  final String category;

  bool get running => active == 'active';
  bool get failed => active == 'failed';

  bool get isDatabase {
    if (category == '数据库') return true;
    final l = name.toLowerCase();
    return l.contains('postgres') ||
        l.contains('pgsql') ||
        l.contains('mysql') ||
        l.contains('mariadb') ||
        l.contains('redis');
  }

  String get databaseType {
    final l = name.toLowerCase();
    if (l.contains('postgres') || l.contains('pgsql')) return 'postgres';
    if (l.contains('mysql') || l.contains('mariadb')) return 'mysql';
    if (l.contains('redis')) return 'redis';
    return 'postgres';
  }
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

  bool get isRunning => state.toLowerCase() == 'running';
  bool get isStopped =>
      state.toLowerCase() == 'exited' ||
      state.toLowerCase() == 'created' ||
      state.toLowerCase() == 'dead';
  bool get isPaused => state.toLowerCase() == 'paused';
  bool get isRestarting => state.toLowerCase() == 'restarting';

  bool get running => isRunning;

  String get shortId => id.length > 12 ? id.substring(0, 12) : id;
  String get primaryName => names.split(',').first.replaceFirst(RegExp(r'^/'), '');

  bool get isDatabase => databaseType != null;

  String? get databaseType {
    final lImg = image.toLowerCase();
    final lName = names.toLowerCase();
    if (lImg.contains('postgres') ||
        lImg.contains('pgsql') ||
        lName.contains('postgres') ||
        lName.contains('pgsql') ||
        ports.contains('5432')) {
      return 'postgres';
    }
    if (lImg.contains('mysql') ||
        lImg.contains('mariadb') ||
        lName.contains('mysql') ||
        lName.contains('mariadb') ||
        ports.contains('3306')) {
      return 'mysql';
    }
    if (lImg.contains('redis') || lName.contains('redis') || ports.contains('6379')) {
      return 'redis';
    }
    return null;
  }

  List<String> get formattedPorts {
    if (ports.trim().isEmpty) return const [];
    // 匹配例如 0.0.0.0:5432->5432/tcp 或 80/tcp
    final results = <String>[];
    for (final part in ports.split(',')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final match = RegExp(r'(\d+(?:\.\d+)*):(\d+)->(\d+/\w+)').firstMatch(p);
      if (match != null) {
        results.add('${match.group(2)}:${match.group(3)}');
      } else {
        results.add(p);
      }
    }
    return results;
  }
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

  String get shortId => id.replaceFirst('sha256:', '').substring(0, 12.clamp(0, id.length));

  bool get isDangling => repository == '<none>' || tag == '<none>';

  String get ref {
    if (isDangling) return shortId;
    return '$repository:$tag';
  }

  /// 提取所属 Registry 仓库地址或类型
  String get registry {
    if (isDangling) return '本地悬空镜像';
    if (!repository.contains('/')) {
      return 'Docker Hub (Official)';
    }
    final firstPart = repository.split('/').first;
    if (firstPart.contains('.') || firstPart.contains(':')) {
      if (firstPart.contains('aliyun') || firstPart.contains('aliyuncs')) {
        return '阿里云 Registry';
      }
      if (firstPart.contains('tencent') || firstPart.contains('myqcloud')) {
        return '腾讯云 Registry';
      }
      if (firstPart.contains('ghcr.io')) {
        return 'GitHub GHCR';
      }
      if (firstPart.contains('gcr.io')) {
        return 'Google GCR';
      }
      if (firstPart.contains('quay.io')) {
        return 'Quay.io';
      }
      return firstPart;
    }
    return 'Docker Hub';
  }

  String get repositoryName {
    if (isDangling) return '<未命名悬空镜像>';
    if (!repository.contains('/')) return repository;
    final parts = repository.split('/');
    final first = parts.first;
    if (first.contains('.') || first.contains(':')) {
      return parts.sublist(1).join('/');
    }
    return repository;
  }
}

class DockerRegistryConfig {
  const DockerRegistryConfig({
    required this.id,
    required this.name,
    required this.registryUrl,
    required this.namespace,
    this.username = '',
  });

  final String id;
  final String name;
  final String registryUrl; // 例如: registry.cn-hangzhou.aliyuncs.com
  final String namespace;   // 例如: anpy-dev
  final String username;

  String get prefix {
    final cleanReg = registryUrl.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');
    final cleanNs = namespace.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
    if (cleanNs.isEmpty) {
      return '$cleanReg/';
    }
    return '$cleanReg/$cleanNs/';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'registryUrl': registryUrl,
        'namespace': namespace,
        'username': username,
      };

  factory DockerRegistryConfig.fromJson(Map<String, Object?> json) {
    return DockerRegistryConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      registryUrl: json['registryUrl'] as String,
      namespace: (json['namespace'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
    );
  }
}

enum DatabaseTargetKind { container, service }

class DatabaseTarget {
  const DatabaseTarget({
    required this.kind,
    required this.identifier,
    required this.type,
    this.displayName,
    this.defaultPort = 5432,
    this.defaultUser = 'postgres',
    this.defaultDatabase = 'postgres',
  });

  final DatabaseTargetKind kind;
  final String identifier; // container name or service unit name
  final String type;       // 'postgres', 'mysql', 'redis'
  final String? displayName;
  final int defaultPort;
  final String defaultUser;
  final String defaultDatabase;

  String get label => displayName ?? identifier;
  bool get isPostgres => type == 'postgres';
  bool get isMysql => type == 'mysql';
  bool get isRedis => type == 'redis';
}

class DatabaseQueryResult {
  const DatabaseQueryResult({
    required this.columns,
    required this.rows,
    required this.rowCount,
    this.executionDurationMs = 0,
    this.statusMessage,
    this.error,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final int rowCount;
  final int executionDurationMs;
  final String? statusMessage;
  final String? error;

  bool get hasError => error != null && error!.isNotEmpty;
  bool get isTabular => columns.isNotEmpty;

  factory DatabaseQueryResult.error(String err, {int durationMs = 0}) {
    return DatabaseQueryResult(
      columns: const [],
      rows: const [],
      rowCount: 0,
      executionDurationMs: durationMs,
      error: err,
    );
  }

  factory DatabaseQueryResult.status(String message, {int durationMs = 0}) {
    return DatabaseQueryResult(
      columns: const [],
      rows: const [],
      rowCount: 0,
      executionDurationMs: durationMs,
      statusMessage: message,
    );
  }
}

