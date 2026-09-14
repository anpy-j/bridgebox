import '../models/models.dart';
import 'name_guard.dart';
import 'ssh_session.dart';

class RemoteOps {
  RemoteOps(this.session);

  final SshSession session;

  Future<HostMetrics> metrics() async {
    final first = await session.run('cat /proc/stat; echo ---; cat /proc/meminfo; echo ---; cat /proc/loadavg; echo ---; cat /proc/uptime; echo ---; df -Pk /');
    if (!first.ok) {
      throw StateError(first.displayError);
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final second = await session.run('cat /proc/stat');
    if (!second.ok) {
      throw StateError(second.displayError);
    }
    return _parseMetrics(first.stdout, second.stdout);
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
      throw FormatException('不支持的服务操作');
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
    if (!const {'start', 'stop', 'restart', 'rm'}.contains(action)) {
      throw FormatException('不支持的容器操作');
    }
    final extra = action == 'rm' ? ' -f' : '';
    final result = await session.run('docker $action$extra $name');
    if (!result.ok) {
      throw StateError(result.displayError);
    }
  }

  Future<String> containerLogs(String name) async {
    NameGuard.container(name);
    final result = await session.run('docker logs --tail 120 $name');
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
    NameGuard.image(ref);
    final result = await session.run(
      'docker pull $ref',
      timeout: const Duration(minutes: 5),
    );
    if (!result.ok) {
      throw StateError(result.displayError);
    }
  }

  Future<void> removeImage(String ref) async {
    NameGuard.image(ref);
    final result = await session.run('docker rmi $ref');
    if (!result.ok) {
      throw StateError(result.displayError);
    }
  }

  ServiceUnit _parseUnit(String line) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 4) {
      return ServiceUnit(
        name: line,
        load: '',
        active: '',
        sub: '',
        description: '',
      );
    }
    return ServiceUnit(
      name: parts[0],
      load: parts[1],
      active: parts[2],
      sub: parts[3],
      description: parts.length > 4 ? parts.sublist(4).join(' ') : '',
    );
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

    final load1 = double.tryParse(load.trim().split(RegExp(r'\s+')).first) ?? 0;
    final uptimeSec =
        double.tryParse(uptimeRaw.trim().split(RegExp(r'\s+')).first) ?? 0;

    final disk = _parseDf(df);

    return HostMetrics(
      cpuPercent: cpuPercent.clamp(0, 100),
      memUsedBytes: (memTotal - memAvail).clamp(0, memTotal),
      memTotalBytes: memTotal,
      swapUsedBytes: (swapTotal - swapFree).clamp(0, swapTotal),
      swapTotalBytes: swapTotal,
      diskUsedBytes: disk.$1,
      diskTotalBytes: disk.$2,
      load1: load1,
      uptime: _formatUptime(uptimeSec),
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
    if (days > 0) return '${days}天 $hours小时';
    if (hours > 0) return '$hours小时 $minutes分';
    return '$minutes分';
  }
}
