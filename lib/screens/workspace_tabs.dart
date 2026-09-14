import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/remote_ops.dart';
import '../widgets/metric_tile.dart';

class WorkspaceTabs extends StatelessWidget {
  const WorkspaceTabs({super.key, required this.ops, required this.index});

  final RemoteOps ops;
  final int index;

  @override
  Widget build(BuildContext context) {
    return switch (index) {
      0 => OverviewTab(ops: ops),
      1 => ServicesTab(ops: ops),
      2 => ContainersTab(ops: ops),
      _ => ImagesTab(ops: ops),
    };
  }
}

class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key, required this.ops});
  final RemoteOps ops;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  HostMetrics? _metrics;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.ops.metrics();
      if (!mounted) return;
      setState(() {
        _metrics = next;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _metrics == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _metrics == null) {
      return Center(child: Text('读取指标失败：$_error'));
    }
    final m = _metrics!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.extent(
        maxCrossAxisExtent: 360,
        padding: const EdgeInsets.all(16),
        childAspectRatio: 1.6,
        children: [
          MetricTile(
            label: 'CPU',
            value: '${m.cpuPercent.toStringAsFixed(1)}%',
            percent: m.cpuPercent,
          ),
          MetricTile(
            label: '内存',
            value: '${formatBytes(m.memUsedBytes)} / ${formatBytes(m.memTotalBytes)}',
            percent: m.memPercent,
          ),
          MetricTile(
            label: 'Swap',
            value: '${formatBytes(m.swapUsedBytes)} / ${formatBytes(m.swapTotalBytes)}',
            percent: m.swapPercent,
          ),
          MetricTile(
            label: '根分区',
            value: '${formatBytes(m.diskUsedBytes)} / ${formatBytes(m.diskTotalBytes)}',
            percent: m.diskPercent,
          ),
          MetricTile(
            label: '负载 / 运行时间',
            value: 'load ${m.load1.toStringAsFixed(2)} · ${m.uptime}',
            percent: 0,
          ),
        ],
      ),
    );
  }
}

class ServicesTab extends StatefulWidget {
  const ServicesTab({super.key, required this.ops});
  final RemoteOps ops;

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> {
  late Future<List<ServiceUnit>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.ops.listServices();
  }

  void _reload() => setState(() => _future = widget.ops.listServices());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ServiceUnit>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final unit = items[index];
              return ListTile(
                title: Text(unit.name),
                subtitle: Text('${unit.active} / ${unit.sub}  ${unit.description}'),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: '启动',
                      onPressed: () => _act(unit.name, 'start', '启动 ${unit.name}？'),
                      icon: const Icon(Icons.play_arrow),
                    ),
                    IconButton(
                      tooltip: '停止',
                      onPressed: () => _act(unit.name, 'stop', '停止 ${unit.name}？'),
                      icon: const Icon(Icons.stop),
                    ),
                    IconButton(
                      tooltip: '重启',
                      onPressed: () => _act(unit.name, 'restart', '重启 ${unit.name}？'),
                      icon: const Icon(Icons.restart_alt),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _act(String unit, String action, String body) async {
    final ok = await confirmAction(context, title: '确认操作', body: body);
    if (!ok || !mounted) return;
    try {
      await widget.ops.controlService(unit, action);
      _reload();
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }
}

class ContainersTab extends StatefulWidget {
  const ContainersTab({super.key, required this.ops});
  final RemoteOps ops;

  @override
  State<ContainersTab> createState() => _ContainersTabState();
}

class _ContainersTabState extends State<ContainersTab> {
  late Future<List<DockerContainer>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.ops.listContainers();
  }

  void _reload() => setState(() => _future = widget.ops.listContainers());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DockerContainer>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final c = items[index];
              return ListTile(
                leading: Icon(
                  c.running ? Icons.play_circle : Icons.pause_circle_outline,
                ),
                title: Text(c.names),
                subtitle: Text('${c.image}\n${c.status}\n${c.ports}'),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => _onMenu(c, value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'start', child: Text('启动')),
                    PopupMenuItem(value: 'stop', child: Text('停止')),
                    PopupMenuItem(value: 'restart', child: Text('重启')),
                    PopupMenuItem(value: 'logs', child: Text('日志')),
                    PopupMenuItem(value: 'rm', child: Text('删除')),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _onMenu(DockerContainer c, String action) async {
    if (action == 'logs') {
      try {
        final logs = await widget.ops.containerLogs(c.primaryName);
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(logs.isEmpty ? '（无日志）' : logs),
            ),
          ),
        );
      } catch (e) {
        if (mounted) showAppError(context, e);
      }
      return;
    }
    final ok = await confirmAction(
      context,
      title: '容器操作',
      body: '$action ${c.names}？',
    );
    if (!ok || !mounted) return;
    try {
      await widget.ops.controlContainer(c.primaryName, action);
      _reload();
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }
}

class ImagesTab extends StatefulWidget {
  const ImagesTab({super.key, required this.ops});
  final RemoteOps ops;

  @override
  State<ImagesTab> createState() => _ImagesTabState();
}

class _ImagesTabState extends State<ImagesTab> {
  late Future<List<DockerImageInfo>> _future;
  final _pull = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = widget.ops.listImages();
  }

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = widget.ops.listImages());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pull,
                  decoration: const InputDecoration(
                    labelText: '拉取镜像，例如 nginx:alpine',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _doPull, child: const Text('拉取')),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<DockerImageInfo>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data!;
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final image = items[index];
                    return ListTile(
                      title: Text(image.ref),
                      subtitle: Text('${image.id} · ${image.size}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(image),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _doPull() async {
    final ref = _pull.text.trim();
    if (ref.isEmpty) return;
    try {
      await widget.ops.pullImage(ref);
      _pull.clear();
      _reload();
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  Future<void> _remove(DockerImageInfo image) async {
    final ok = await confirmAction(
      context,
      title: '删除镜像',
      body: '删除 ${image.ref}？',
    );
    if (!ok || !mounted) return;
    try {
      await widget.ops.removeImage(image.ref);
      _reload();
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }
}
