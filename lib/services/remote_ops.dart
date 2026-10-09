import 'dart:convert';

import '../models/models.dart';
import 'name_guard.dart';
import 'ssh_session.dart';

class RemoteOps {
  RemoteOps(this.session);

  final SshSession session;

  Future<HostMetrics> metrics() async {
    final first = await session.run(
      'cat /proc/stat; echo ---; cat /proc/meminfo; echo ---; cat /proc/loadavg; echo ---; cat /proc/uptime; echo ---; df -Pk /; echo ---; cat /etc/os-release 2>/dev/null; echo ---; nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo',
    );
    if (!first.ok) {
      throw StateError(first.displayError);
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final second = await session.run('cat /proc/stat');
    if (!second.ok) {
      throw StateError(second.displayError);
    }
    return _parseMetrics(first.stdout, second.stdout);
  }

  Future<List<ProcessItem>> topProcesses(ProcessMetricKind kind) async {
    final sortFlag = switch (kind) {
      ProcessMetricKind.cpu => '-%cpu',
      ProcessMetricKind.memory => '-%mem',
      ProcessMetricKind.swap => '-%mem',
    };
    // pid user %cpu %mem rss comm args
    final cmd = 'ps -eo pid,user,%cpu,%mem,rss,comm,args --sort=$sortFlag --no-headers | head -n 25';
    final result = await session.run(cmd);
    if (!result.ok) {
      throw StateError(result.displayError);
    }
    return result.stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(_parseProcessItem)
        .toList();
  }

  Future<void> killProcess(int pid, {bool force = false}) async {
    NameGuard.pid(pid);
    final signal = force ? '-9' : '-15';
    final result = await session.run('kill $signal $pid');
    if (!result.ok) {
      throw StateError(result.displayError);
    }
  }

  Future<List<ServiceUnit>> listServices() async {
    final result = await session.run(
      'systemctl list-units --type=service --all --no-pager --no-legend --plain',
    );
    if (!result.ok) {
      throw StateError(result.displayError);
    }
    return result.stdout
        .split('\n')
        .map((line) => line.trim().replaceFirst(RegExp(r'^[●○•]\s*'), ''))
        .where((line) => line.isNotEmpty)
        .map(_parseUnit)
        .toList();
  }

  Future<void> controlService(String unit, String action) async {
    NameGuard.unitName(unit);
    if (!const {'start', 'stop', 'restart'}.contains(action)) {
      throw const FormatException('不支持的服务操作');
    }
    final result = await session.run('systemctl $action $unit');
    if (!result.ok) {
      throw StateError(result.displayError);
    }
  }

  Future<List<DockerContainer>> listContainers() async {
    final result = await session.run(
      r'''docker ps -a --format '{"id":"{{.ID}}","names":"{{.Names}}","image":"{{.Image}}","status":"{{.Status}}","state":"{{.State}}","ports":"{{.Ports}}"}' ''',
    );
    if (!result.ok) {
      throw StateError(result.displayError);
    }
    return result.stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('{'))
        .map(_parseContainer)
        .toList();
  }

  Future<void> controlContainer(String name, String action) async {
    NameGuard.container(name);
    if (!const {'start', 'stop', 'restart', 'rm', 'pause', 'unpause'}.contains(action)) {
      throw const FormatException('不支持的容器操作');
    }
    final extra = action == 'rm' ? ' -f' : '';
    final result = await session.run('docker $action$extra $name');
    if (!result.ok) {
      throw StateError(result.displayError);
    }
  }

  Future<String> containerLogs(String name, {int tail = 150}) async {
    NameGuard.container(name);
    final result = await session.run('docker logs --tail $tail $name');
    if (!result.ok) {
      throw StateError(result.displayError);
    }
    return result.stdout;
  }

  Future<List<DockerImageInfo>> listImages() async {
    final result = await session.run(
      r'''docker images --format '{"id":"{{.ID}}","repository":"{{.Repository}}","tag":"{{.Tag}}","size":"{{.Size}}"}' ''',
    );
    if (!result.ok) {
      throw StateError(result.displayError);
    }
    return result.stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('{'))
        .map(_parseImage)
        .toList();
  }

  Future<void> pullImage(String ref) async {
    final clean = ref.trim();
    NameGuard.image(clean);
    final result = await session.run(
      'docker pull $clean',
      timeout: const Duration(minutes: 8),
    );
    // 判断是否实际上拉取成功（某些 docker 客户端在输出中包含进度时 exitCode 或 stderr 带有 warning）
    final isSuccessOutput = result.stdout.contains('Status: Downloaded newer image') ||
        result.stdout.contains('Status: Image is up to date') ||
        result.stdout.contains('Digest: sha256:');
    if (!result.ok && !isSuccessOutput) {
      throw StateError(result.displayError);
    }
  }

  Future<String> runContainer({
    required String image,
    required String name,
    List<String> portMappings = const [],
    List<String> envVars = const [],
    List<String> volumeMounts = const [],
    bool restartAlways = true,
  }) async {
    NameGuard.image(image);
    NameGuard.container(name);

    final args = <String>['docker', 'run', '-d', '--name', name];
    if (restartAlways) {
      args.add('--restart=unless-stopped');
    }
    for (final p in portMappings) {
      final trimmed = p.trim();
      if (trimmed.isNotEmpty) {
        args.addAll(['-p', trimmed]);
      }
    }
    for (final e in envVars) {
      final trimmed = e.trim();
      if (trimmed.isNotEmpty) {
        args.addAll(['-e', trimmed]);
      }
    }
    for (final v in volumeMounts) {
      final trimmed = v.trim();
      if (trimmed.isNotEmpty) {
        args.addAll(['-v', trimmed]);
      }
    }
    args.add(image);

    final cmd = args.map((a) => "'${a.replaceAll("'", "'\\''")}'").join(' ');
    final result = await session.run(cmd);
    if (!result.ok) {
      throw StateError(result.displayError);
    }
    return result.stdout.trim();
  }

  /// 在远端主机执行自定义多行准备脚本与 docker run 命令（例如先 mkdir -p data，再启动容器）
  Future<String> runContainerScript(String script) async {
    final cleanScript = script.trim();
    if (cleanScript.isEmpty) {
      throw const FormatException('命令脚本不能为空');
    }
    final b64 = base64Encode(utf8.encode(cleanScript));
    final cmd = "printf '%s' '$b64' | base64 -d | bash";
    final result = await session.run(cmd, timeout: const Duration(minutes: 5));
    if (!result.ok) {
      final err = result.stderr.trim().isNotEmpty ? result.stderr.trim() : result.stdout.trim();
      throw StateError(err.isNotEmpty ? err : '命令执行失败 (exit code ${result.exitCode})');
    }
    return result.stdout.trim();
  }

  Future<void> removeImage(String ref) async {
    NameGuard.image(ref);
    final result = await session.run('docker rmi $ref');
    if (!result.ok) {
      throw StateError(result.displayError);
    }
  }

  Future<String> cleanDanglingImages() async {
    final result = await session.run('docker image prune -f');
    if (!result.ok) {
      throw StateError(result.displayError);
    }
    return result.stdout;
  }

  Future<String> loginRegistry({
    required String registryUrl,
    required String username,
    required String password,
  }) async {
    final cleanReg = registryUrl
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');
    NameGuard.image(cleanReg);
    final escapedUser = username.replaceAll("'", "'\\''");
    final escapedPwd = password.replaceAll("'", "'\\''");
    final cmd =
        "printf '%s' '$escapedPwd' | docker login --username '$escapedUser' --password-stdin '$cleanReg'";
    final result = await session.run(cmd);
    if (!result.ok) {
      throw StateError(result.displayError);
    }
    return result.stdout.trim();
  }

  Future<String> logoutRegistry(String registryUrl) async {
    final cleanReg = registryUrl
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');
    NameGuard.image(cleanReg);
    final cmd = "docker logout '$cleanReg'";
    final result = await session.run(cmd);
    if (!result.ok) {
      throw StateError(result.displayError);
    }
    return result.stdout.trim();
  }

  // ===================== 数据库管理与交互 =====================

  /// 列出当前实例下的所有 Database
  Future<List<String>> listDatabases(
    DatabaseTarget target, {
    String? user,
    String? password,
  }) async {
    if (target.isPostgres) {
      final res = await queryDatabase(
        target,
        database: 'postgres',
        sql: 'SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;',
        user: user,
        password: password,
      );
      if (res.hasError) throw StateError(res.error!);
      return res.rows.map((r) => r.first).where((s) => s.isNotEmpty).toList();
    } else if (target.isMysql) {
      final res = await queryDatabase(
        target,
        database: '', // SHOW DATABASES 不需要预选任何特定数据库
        sql: 'SHOW DATABASES;',
        user: user,
        password: password,
      );
      if (res.hasError) throw StateError(res.error!);
      return res.rows.map((r) => r.first).where((s) => s.isNotEmpty).toList();
    } else {
      return const ['db0', 'db1', 'db2', 'db3'];
    }
  }

  /// 列出选定数据库中的所有数据表
  Future<List<String>> listTables(
    DatabaseTarget target, {
    required String database,
    String? user,
    String? password,
  }) async {
    if (target.isPostgres) {
      final res = await queryDatabase(
        target,
        database: database,
        sql: "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;",
        user: user,
        password: password,
      );
      if (res.hasError) throw StateError(res.error!);
      return res.rows.map((r) => r.first).where((s) => s.isNotEmpty).toList();
    } else if (target.isMysql) {
      final res = await queryDatabase(
        target,
        database: database,
        sql: 'SHOW TABLES;',
        user: user,
        password: password,
      );
      if (res.hasError) throw StateError(res.error!);
      return res.rows.map((r) => r.first).where((s) => s.isNotEmpty).toList();
    } else {
      final res = await queryDatabase(
        target,
        database: database,
        sql: 'KEYS *',
        user: user,
        password: password,
      );
      if (res.hasError) throw StateError(res.error!);
      return res.rows.map((r) => r.first).where((s) => s.isNotEmpty).toList();
    }
  }

  /// 在数据库上执行 SQL 并返回结构化表格数据
  Future<DatabaseQueryResult> queryDatabase(
    DatabaseTarget target, {
    required String database,
    required String sql,
    String? user,
    String? password,
  }) async {
    final stopwatch = Stopwatch()..start();
    final u = (user != null && user.trim().isNotEmpty) ? user.trim() : target.defaultUser;
    final db = database.trim();
    final b64Sql = base64Encode(utf8.encode(sql));

    String remoteCmd;
    if (target.isPostgres) {
      final pgDb = db.isNotEmpty ? db : target.defaultDatabase;
      final passEnv = (password != null && password.isNotEmpty) ? "PGPASSWORD='$password' " : "";
      if (target.kind == DatabaseTargetKind.container) {
        NameGuard.container(target.identifier);
        remoteCmd =
            "printf '%s' '$b64Sql' | base64 -d | docker exec -i ${target.identifier} env ${passEnv}psql -U $u -d $pgDb -A -F '\t'";
      } else {
        if (u == 'postgres' && (password == null || password.isEmpty)) {
          remoteCmd = "printf '%s' '$b64Sql' | base64 -d | sudo -u postgres psql -d $pgDb -A -F '\t'";
        } else {
          remoteCmd =
              "printf '%s' '$b64Sql' | base64 -d | env ${passEnv}psql -U $u -h 127.0.0.1 -d $pgDb -A -F '\t'";
        }
      }
    } else if (target.isMysql) {
      final dbFlag = (db.isNotEmpty && db != '*') ? "-D '$db'" : "";
      final escapedUser = u.replaceAll("'", "'\\''");
      if (target.kind == DatabaseTargetKind.container) {
        NameGuard.container(target.identifier);
        final envFlag = (password != null && password.isNotEmpty)
            ? "-e MYSQL_PWD='${password.replaceAll("'", "'\\''")}'"
            : "";
        remoteCmd =
            "printf '%s' '$b64Sql' | base64 -d | docker exec -i $envFlag ${target.identifier} sh -c \"if command -v mysql >/dev/null 2>&1; then mysql -u '$escapedUser' $dbFlag --batch --raw; else mariadb -u '$escapedUser' $dbFlag --batch --raw; fi\"";
      } else {
        final passEnv = (password != null && password.isNotEmpty)
            ? "MYSQL_PWD='${password.replaceAll("'", "'\\''")}' "
            : "";
        remoteCmd =
            "printf '%s' '$b64Sql' | base64 -d | env $passEnv sh -c \"if command -v mysql >/dev/null 2>&1; then mysql -u '$escapedUser' $dbFlag --batch --raw; else mariadb -u '$escapedUser' $dbFlag --batch --raw; fi\"";
      }
    } else {
      // Redis
      if (target.kind == DatabaseTargetKind.container) {
        NameGuard.container(target.identifier);
        remoteCmd = "docker exec -i ${target.identifier} redis-cli $sql";
      } else {
        remoteCmd = "redis-cli $sql";
      }
    }

    final result = await session.run(remoteCmd);
    stopwatch.stop();
    final duration = stopwatch.elapsedMilliseconds;

    if (!result.ok) {
      final errMsg = result.stderr.trim().isNotEmpty ? result.stderr.trim() : result.stdout.trim();
      return DatabaseQueryResult.error(
        errMsg.isNotEmpty ? errMsg : '查询执行失败 (exit code ${result.exitCode})',
        durationMs: duration,
      );
    }

    return _parseDatabaseOutput(result.stdout, duration);
  }

  DatabaseQueryResult _parseDatabaseOutput(String rawOutput, int durationMs) {
    final trimmed = rawOutput.trim();
    if (trimmed.isEmpty) {
      return DatabaseQueryResult.status('执行成功 (无返回数据集)', durationMs: durationMs);
    }

    final rawLines = trimmed.split('\n');
    final lines = <String>[];
    for (final l in rawLines) {
      final line = l.replaceAll('\r', '');
      // 过滤 PostgreSQL 常见的总结行: (10 rows) 或 (1 row)
      if (RegExp(r'^\(\d+\s+rows?\)$').hasMatch(line.trim())) {
        continue;
      }
      lines.add(line);
    }

    if (lines.isEmpty) {
      return DatabaseQueryResult.status('执行成功 (0 条记录)', durationMs: durationMs);
    }

    // 如果只有一行，且看起来是 DDL/DML 返回信息，如 "CREATE TABLE", "INSERT 0 1", "UPDATE 3"
    if (lines.length == 1) {
      final first = lines.first.trim();
      if (!first.contains('\t') &&
          (first.startsWith('INSERT') ||
              first.startsWith('UPDATE') ||
              first.startsWith('DELETE') ||
              first.startsWith('CREATE') ||
              first.startsWith('DROP') ||
              first.startsWith('ALTER'))) {
        return DatabaseQueryResult.status(first, durationMs: durationMs);
      }
    }

    // 第一行为列名表头
    final columns = lines.first.split('\t').map((c) => c.trim()).toList();
    final rows = <List<String>>[];

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty && i == lines.length - 1) continue;
      final cells = line.split('\t');
      // 对齐列数
      while (cells.length < columns.length) {
        cells.add('');
      }
      rows.add(cells);
    }

    return DatabaseQueryResult(
      columns: columns,
      rows: rows,
      rowCount: rows.length,
      executionDurationMs: durationMs,
    );
  }

  ProcessItem _parseProcessItem(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    final pid = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final user = parts.length > 1 ? parts[1] : '';
    final cpu = double.tryParse(parts.length > 2 ? parts[2] : '') ?? 0.0;
    final mem = double.tryParse(parts.length > 3 ? parts[3] : '') ?? 0.0;
    final rssKb = int.tryParse(parts.length > 4 ? parts[4] : '') ?? 0;
    final comm = parts.length > 5 ? parts[5] : '';
    final args = parts.length > 6 ? parts.sublist(6).join(' ') : comm;

    return ProcessItem(
      pid: pid,
      user: user,
      cpuPercent: cpu,
      memPercent: mem,
      rssBytes: rssKb * 1024,
      comm: comm,
      args: args,
    );
  }

  ServiceUnit _parseUnit(String line) {
    final parts = line.split(RegExp(r'\s+'));
    final name = parts.isNotEmpty ? parts[0] : line;
    final load = parts.length > 1 ? parts[1] : '';
    final active = parts.length > 2 ? parts[2] : '';
    final sub = parts.length > 3 ? parts[3] : '';
    final desc = parts.length > 4 ? parts.sublist(4).join(' ') : '';

    final (isApp, category) = _classifyService(name, desc);

    return ServiceUnit(
      name: name,
      load: load,
      active: active,
      sub: sub,
      description: desc,
      isAppService: isApp,
      category: category,
    );
  }

  (bool, String) _classifyService(String name, String desc) {
    final lowerName = name.toLowerCase().replaceFirst(RegExp(r'\.service$'), '');

    // 1. 数据库类 (PostgreSQL, MySQL, MariaDB, Redis, MongoDB, ClickHouse 等)
    if (lowerName == 'postgresql' ||
        lowerName.startsWith('postgresql@') ||
        lowerName.startsWith('postgres') ||
        lowerName.contains('pgsql') ||
        lowerName == 'mysql' ||
        lowerName.startsWith('mysql@') ||
        lowerName.contains('mariadb') ||
        lowerName.contains('redis') ||
        lowerName.contains('mongod') ||
        lowerName.contains('clickhouse')) {
      return (true, '数据库');
    }

    // 2. Web 与反向代理 (Nginx, Caddy, Apache, Traefik 等)
    if (lowerName.contains('nginx') ||
        lowerName.contains('caddy') ||
        lowerName == 'apache2' ||
        lowerName == 'httpd' ||
        lowerName.contains('traefik') ||
        lowerName.contains('openresty') ||
        lowerName.contains('haproxy')) {
      return (true, 'Web / 代理');
    }

    // 3. 容器基础设施 (Docker, Podman, K3s 等)
    if (lowerName == 'docker' ||
        lowerName == 'containerd' ||
        lowerName == 'podman' ||
        lowerName == 'k3s' ||
        lowerName == 'kubelet') {
      return (true, '容器运行时');
    }

    // 4. 常见自建后台业务与服务中间件
    const knownApps = [
      'pm2',
      'gunicorn',
      'uwsgi',
      'supervisor',
      'supervisord',
      'alist',
      'frpc',
      'frps',
      'v2ray',
      'xray',
      'clash',
      'jenkins',
      'gitlab',
      'halo',
      'wordpress',
      'minio',
      'vaultwarden',
      'nacos',
      'emqx',
      'rabbitmq',
      'kafka',
      'zookeeper',
      'elasticsearch',
      'kibana',
    ];

    for (final app in knownApps) {
      if (lowerName == app || lowerName.startsWith('$app-') || lowerName.startsWith('${app}_')) {
        return (true, '自建 / 业务应用');
      }
    }

    // 默认一律归入系统底层服务（避免将普通守护进程误判为自建应用）
    return (false, '系统底层服务');
  }

  DockerContainer _parseContainer(String line) {
    final map = _jsonMap(line);
    return DockerContainer(
      id: map['id'] ?? '',
      names: map['names'] ?? '',
      image: map['image'] ?? '',
      status: map['status'] ?? '',
      state: map['state'] ?? '',
      ports: map['ports'] ?? '',
    );
  }

  DockerImageInfo _parseImage(String line) {
    final map = _jsonMap(line);
    return DockerImageInfo(
      id: map['id'] ?? '',
      repository: map['repository'] ?? '',
      tag: map['tag'] ?? '',
      size: map['size'] ?? '',
    );
  }

  Map<String, String> _jsonMap(String line) {
    final cleaned = line.replaceAll(r'\"', '"');
    final pairs = RegExp(r'"(\w+)":"(.*?)"').allMatches(cleaned);
    return {for (final m in pairs) m.group(1)!: m.group(2)!};
  }

  HostMetrics _parseMetrics(String blob, String secondStat) {
    final chunks = blob.split('\n---\n');
    final stat1 = chunks.isNotEmpty ? chunks[0] : '';
    final mem = chunks.length > 1 ? chunks[1] : '';
    final load = chunks.length > 2 ? chunks[2] : '';
    final uptimeRaw = chunks.length > 3 ? chunks[3] : '';
    final df = chunks.length > 4 ? chunks[4] : '';
    final osRaw = chunks.length > 5 ? chunks[5] : '';
    final nprocRaw = chunks.length > 6 ? chunks[6] : '';

    final cpu1 = _cpuTimes(stat1);
    final cpu2 = _cpuTimes(secondStat);
    var cpuPercent = 0.0;
    if (cpu1 != null && cpu2 != null) {
      final idle = cpu2.idle - cpu1.idle;
      final total = cpu2.total - cpu1.total;
      if (total > 0) {
        cpuPercent = (1 - idle / total) * 100;
      }
    }

    final memTotal = _memField(mem, 'MemTotal') * 1024;
    final memAvail = _memField(mem, 'MemAvailable') * 1024;
    final swapTotal = _memField(mem, 'SwapTotal') * 1024;
    final swapFree = _memField(mem, 'SwapFree') * 1024;

    final loadParts = load.trim().split(RegExp(r'\s+'));
    final load1 = double.tryParse(loadParts.isNotEmpty ? loadParts[0] : '') ?? 0;
    final load5 = double.tryParse(loadParts.length > 1 ? loadParts[1] : '') ?? 0;
    final load15 = double.tryParse(loadParts.length > 2 ? loadParts[2] : '') ?? 0;

    final uptimeSec =
        double.tryParse(uptimeRaw.trim().split(RegExp(r'\s+')).first) ?? 0;

    final disk = _parseDf(df);

    // 解析 OS 名称
    var osName = 'Linux';
    final prettyMatch = RegExp(r'PRETTY_NAME="?([^"\n]+)"?').firstMatch(osRaw);
    if (prettyMatch != null) {
      osName = prettyMatch.group(1)!;
    }

    // 解析 CPU 核心数
    final cpuCores = int.tryParse(nprocRaw.trim().split('\n').first) ?? 1;

    return HostMetrics(
      cpuPercent: cpuPercent.clamp(0, 100),
      memUsedBytes: (memTotal - memAvail).clamp(0, memTotal),
      memTotalBytes: memTotal,
      swapUsedBytes: (swapTotal - swapFree).clamp(0, swapTotal),
      swapTotalBytes: swapTotal,
      diskUsedBytes: disk.$1,
      diskTotalBytes: disk.$2,
      load1: load1,
      load5: load5,
      load15: load15,
      uptime: _formatUptime(uptimeSec),
      osName: osName,
      cpuCores: cpuCores > 0 ? cpuCores : 1,
    );
  }

  ({double idle, double total})? _cpuTimes(String stat) {
    final line = stat
        .split('\n')
        .firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
    if (line.isEmpty) return null;
    final nums = line
        .split(RegExp(r'\s+'))
        .skip(1)
        .map((e) => double.tryParse(e) ?? 0)
        .toList();
    if (nums.length < 4) return null;
    final idle = nums[3] + (nums.length > 4 ? nums[4] : 0);
    final total = nums.fold<double>(0, (a, b) => a + b);
    return (idle: idle, total: total);
  }

  int _memField(String mem, String key) {
    final match = RegExp('$key:\\s+(\\d+)').firstMatch(mem);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  (int, int) _parseDf(String df) {
    final lines = df.trim().split('\n');
    if (lines.length < 2) return (0, 0);
    final parts = lines.last.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return (0, 0);
    final totalKb = int.tryParse(parts[1]) ?? 0;
    final usedKb = int.tryParse(parts[2]) ?? 0;
    return (usedKb * 1024, totalKb * 1024);
  }

  String _formatUptime(double seconds) {
    final d = Duration(seconds: seconds.floor());
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    if (days > 0) return '$days天 $hours小时';
    if (hours > 0) return '$hours小时 $minutes分';
    return '$minutes分';
  }
}
