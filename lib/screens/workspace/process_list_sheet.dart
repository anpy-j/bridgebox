import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/remote_ops.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/metric_tile.dart';

class ProcessListSheet extends StatefulWidget {
  const ProcessListSheet({
    super.key,
    required this.ops,
    required this.initialKind,
  });

  final RemoteOps ops;
  final ProcessMetricKind initialKind;

  static Future<void> show(
    BuildContext context, {
    required RemoteOps ops,
    required ProcessMetricKind kind,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      builder: (_) => ProcessListSheet(ops: ops, initialKind: kind),
    );
  }

  @override
  State<ProcessListSheet> createState() => _ProcessListSheetState();
}

class _ProcessListSheetState extends State<ProcessListSheet> {
  late ProcessMetricKind _kind;
  List<ProcessItem>? _processes;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.ops.topProcesses(_kind);
      if (!mounted) return;
      setState(() {
        _processes = list;
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
    final title = switch (_kind) {
      ProcessMetricKind.cpu => 'CPU 占用分析 (Top 25)',
      ProcessMetricKind.memory => '内存占用分析 (Top 25)',
      ProcessMetricKind.swap => 'Swap 占用分析 (Top 25)',
    };

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.85,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部拖动把手
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.darkBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 标题与切换
          Row(
            children: [
              const Icon(Icons.analytics_outlined, color: AppColors.primaryLight, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: '刷新排行',
                onPressed: _loading ? null : _fetch,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 维度切换 SegmentedButton
          SegmentedButton<ProcessMetricKind>(
            segments: const [
              ButtonSegment(
                value: ProcessMetricKind.cpu,
                label: Text('CPU 占用'),
                icon: Icon(Icons.speed, size: 16),
              ),
              ButtonSegment(
                value: ProcessMetricKind.memory,
                label: Text('内存占用'),
                icon: Icon(Icons.memory, size: 16),
              ),
              ButtonSegment(
                value: ProcessMetricKind.swap,
                label: Text('Swap 占用'),
                icon: Icon(Icons.swap_horiz, size: 16),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (set) {
              setState(() {
                _kind = set.first;
              });
              _fetch();
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 12),
          // 列表区域
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _processes == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 12),
            Text('正在采集远程进程指标...', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }
    if (_error != null && _processes == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 36),
            const SizedBox(height: 12),
            Text('获取进程失败：$_error', style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _fetch, child: const Text('重试')),
          ],
        ),
      );
    }

    final list = _processes ?? [];
    if (list.isEmpty) {
      return const Center(child: Text('暂无进程数据', style: TextStyle(color: AppColors.textMuted)));
    }

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = list[index];
        return _ProcessItemCard(
          item: item,
          rank: index + 1,
          kind: _kind,
          onKill: () => _handleKill(item),
        );
      },
    );
  }

  Future<void> _handleKill(ProcessItem p) async {
    final ok = await confirmAction(
      context,
      title: '结束进程警告',
      body: '确定向进程 PID: ${p.pid} (${p.comm}) 发送终止信号 (SIGTERM) 吗？\n'
          '所属用户：${p.user}\n'
          '运行命令：${p.args}',
      confirmText: '强制结束',
      isDanger: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.ops.killProcess(p.pid);
      if (!mounted) return;
      showAppSuccess(context, '已向 PID ${p.pid} 发送终止信号');
      _fetch();
    } catch (e) {
      if (!mounted) return;
      showAppError(context, e);
    }
  }
}

class _ProcessItemCard extends StatelessWidget {
  const _ProcessItemCard({
    required this.item,
    required this.rank,
    required this.kind,
    required this.onKill,
  });

  final ProcessItem item;
  final int rank;
  final ProcessMetricKind kind;
  final VoidCallback onKill;

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;
    final badgeColor = isTop3 ? AppColors.primary : AppColors.muted;

    final primaryStat = switch (kind) {
      ProcessMetricKind.cpu => 'CPU: ${item.cpuPercent.toStringAsFixed(1)}%',
      ProcessMetricKind.memory => '内存: ${formatBytes(item.rssBytes)} (${item.memPercent.toStringAsFixed(1)}%)',
      ProcessMetricKind.swap => '内存占用: ${formatBytes(item.rssBytes)}',
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 排名
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 进程名称
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.comm,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Text(
                        'PID ${item.pid}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.user,
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              // 主指标数值
              Text(
                primaryStat,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 完整命令行
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.darkBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.args,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 14),
                  tooltip: '复制完整命令',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.args));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制启动参数'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.error),
                  tooltip: '结束进程',
                  visualDensity: VisualDensity.compact,
                  onPressed: onKill,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
