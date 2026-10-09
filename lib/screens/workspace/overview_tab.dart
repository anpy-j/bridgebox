import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/remote_ops.dart';
import '../../theme/app_theme.dart';
import '../../widgets/metric_tile.dart';
import 'process_list_sheet.dart';

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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 12),
            Text('正在采集主机运行指标...', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    if (_error != null && _metrics == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppColors.error),
              const SizedBox(height: 12),
              Text('读取指标失败：$_error', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final m = _metrics!;
    final wide = MediaQuery.sizeOf(context).width >= 840;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部系统状态摘要横幅
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
                gradient: const LinearGradient(
                  colors: [Color(0xFF192332), Color(0xFF131B26)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.dns, color: AppColors.primaryLight, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.osName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'CPU核心: ${m.cpuCores} 核 · 系统已稳定运行: ${m.uptime}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 平均负载卡片
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.darkBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          '平均负载 (1/5/15m)',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${m.load1.toStringAsFixed(2)} · ${m.load5.toStringAsFixed(2)} · ${m.load15.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 核心指标网格
            const Row(
              children: [
                Icon(Icons.speed, size: 18, color: AppColors.primaryLight),
                SizedBox(width: 8),
                Text(
                  '资源监控 (点击卡片查看占用排行榜)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            GridView.extent(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              maxCrossAxisExtent: wide ? 420 : 360,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: wide ? 1.9 : 1.7,
              children: [
                MetricTile(
                  icon: Icons.speed,
                  label: 'CPU 使用率',
                  value: '${m.cpuPercent.toStringAsFixed(1)}%',
                  subValue: '${m.cpuCores} 核',
                  percent: m.cpuPercent,
                  onTap: () => ProcessListSheet.show(
                    context,
                    ops: widget.ops,
                    kind: ProcessMetricKind.cpu,
                  ),
                ),
                MetricTile(
                  icon: Icons.memory,
                  label: '物理内存',
                  value: formatBytes(m.memUsedBytes),
                  subValue: '/ ${formatBytes(m.memTotalBytes)}',
                  percent: m.memPercent,
                  onTap: () => ProcessListSheet.show(
                    context,
                    ops: widget.ops,
                    kind: ProcessMetricKind.memory,
                  ),
                ),
                MetricTile(
                  icon: Icons.swap_horiz,
                  label: 'Swap 交换分区',
                  value: formatBytes(m.swapUsedBytes),
                  subValue: '/ ${formatBytes(m.swapTotalBytes)}',
                  percent: m.swapPercent,
                  onTap: () => ProcessListSheet.show(
                    context,
                    ops: widget.ops,
                    kind: ProcessMetricKind.swap,
                  ),
                ),
                MetricTile(
                  icon: Icons.storage,
                  label: '根分区 (/)',
                  value: formatBytes(m.diskUsedBytes),
                  subValue: '/ ${formatBytes(m.diskTotalBytes)}',
                  percent: m.diskPercent,
                  onTap: null, // 磁盘暂不下钻
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
