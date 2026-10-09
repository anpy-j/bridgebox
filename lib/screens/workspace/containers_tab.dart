import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/remote_ops.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import 'container_log_sheet.dart';
import 'database_explorer_dialog.dart';
import 'run_container_dialog.dart';

class ContainersTab extends StatefulWidget {
  const ContainersTab({super.key, required this.ops});
  final RemoteOps ops;

  @override
  State<ContainersTab> createState() => _ContainersTabState();
}

class _ContainersTabState extends State<ContainersTab> {
  late Future<List<DockerContainer>> _future;
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, running, stopped

  @override
  void initState() {
    super.initState();
    _future = widget.ops.listContainers();
  }

  void _reload() => setState(() {
        _future = widget.ops.listContainers();
      });

  void _openDatabase(DockerContainer c) {
    DatabaseExplorerDialog.show(
      context,
      ops: widget.ops,
      target: DatabaseTarget(
        kind: DatabaseTargetKind.container,
        identifier: c.primaryName,
        type: c.databaseType ?? 'postgres',
        displayName: c.primaryName,
        defaultPort: c.databaseType == 'mysql' ? 3306 : (c.databaseType == 'redis' ? 6379 : 5432),
        defaultUser: c.databaseType == 'mysql' ? 'root' : 'postgres',
        defaultDatabase: c.databaseType == 'mysql' ? 'mysql' : 'postgres',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DockerContainer>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 36, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text('获取容器列表失败：${snapshot.error}', style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2.5),
                SizedBox(height: 12),
                Text('正在拉取 Docker 容器台账...', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          );
        }

        final allContainers = snapshot.data!;

        // 过滤
        final filtered = allContainers.where((c) {
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            if (!c.names.toLowerCase().contains(q) &&
                !c.image.toLowerCase().contains(q) &&
                !c.id.toLowerCase().contains(q)) {
              return false;
            }
          }
          if (_statusFilter == 'running') return c.isRunning;
          if (_statusFilter == 'stopped') return c.isStopped;
          return true;
        }).toList();

        final runningCount = allContainers.where((c) => c.isRunning).length;
        final stoppedCount = allContainers.where((c) => c.isStopped).length;

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 顶部搜索与过滤
              _buildTopBar(allContainers.length, runningCount, stoppedCount),
              const SizedBox(height: 12),

              if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.inbox_outlined, size: 36, color: AppColors.textMuted),
                      const SizedBox(height: 8),
                      Text(
                        _searchQuery.isNotEmpty ? '没有找到匹配的容器' : '当前主机上暂无容器',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else ...[
                // 表头提示栏
                _buildHeaderBar(),
                const SizedBox(height: 6),
                ...filtered.map((c) => _ContainerCard(
                      container: c,
                      onAction: (action, desc, isDanger) =>
                          _handleAction(c, action, desc, isDanger),
                      onShowLogs: () => ContainerLogSheet.show(
                        context,
                        ops: widget.ops,
                        containerName: c.primaryName,
                      ),
                      onOpenDatabase: () => _openDatabase(c),
                    )),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(int total, int running, int stopped) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '按容器名称、镜像或 ID 搜索...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('运行新容器'),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () async {
                final ok = await RunContainerDialog.show(
                  context,
                  ops: widget.ops,
                  image: '',
                );
                if (ok == true) _reload();
              },
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: '刷新容器',
              onPressed: _reload,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: Text('全部 ($total)', style: const TextStyle(fontSize: 12)),
              selected: _statusFilter == 'all',
              onSelected: (_) => setState(() => _statusFilter = 'all'),
              showCheckmark: false,
              selectedColor: AppColors.primaryGlow,
              side: BorderSide(
                color: _statusFilter == 'all' ? AppColors.primary : AppColors.darkBorder,
              ),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('运行中 ($running)', style: const TextStyle(fontSize: 12)),
              selected: _statusFilter == 'running',
              onSelected: (_) => setState(() => _statusFilter = 'running'),
              showCheckmark: false,
              selectedColor: AppColors.successGlow,
              side: BorderSide(
                color: _statusFilter == 'running' ? AppColors.success : AppColors.darkBorder,
              ),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('已停止 ($stopped)', style: const TextStyle(fontSize: 12)),
              selected: _statusFilter == 'stopped',
              onSelected: (_) => setState(() => _statusFilter = 'stopped'),
              showCheckmark: false,
              selectedColor: AppColors.muted.withValues(alpha: 0.15),
              side: BorderSide(
                color: _statusFilter == 'stopped' ? AppColors.muted : AppColors.darkBorder,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.darkSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        children: [
          SizedBox(width: 21, child: Text('#', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
          Expanded(
            flex: 3,
            child: Text('容器名称 / 镜像', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text('运行状态', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text('端口映射', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 175,
            child: Text('操作', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
    DockerContainer c,
    String action,
    String body,
    bool isDanger,
  ) async {
    final ok = await confirmAction(
      context,
      title: '容器操作确认',
      body: body,
      confirmText: action == 'rm' ? '强制删除' : '确认执行',
      isDanger: isDanger,
    );
    if (!ok || !mounted) return;
    try {
      await widget.ops.controlContainer(c.primaryName, action);
      if (!mounted) return;
      showAppSuccess(context, '容器 ${c.primaryName} 操作完成 ($action)');
      _reload();
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }
}

class _ContainerCard extends StatelessWidget {
  const _ContainerCard({
    required this.container,
    required this.onAction,
    required this.onShowLogs,
    required this.onOpenDatabase,
  });

  final DockerContainer container;
  final Function(String action, String desc, bool isDanger) onAction;
  final VoidCallback onShowLogs;
  final VoidCallback onOpenDatabase;

  @override
  Widget build(BuildContext context) {
    final c = container;
    final isRunning = c.isRunning;
    final isStopped = c.isStopped;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isRunning
              ? AppColors.primary.withValues(alpha: 0.25)
              : AppColors.darkBorder,
        ),
      ),
      child: Row(
        children: [
          // 运行状态指示灯
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRunning
                  ? AppColors.success
                  : (c.isRestarting ? AppColors.warning : AppColors.muted),
              boxShadow: isRunning
                  ? [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.5),
                        blurRadius: 5,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 12),

          // 容器主名称与镜像
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.primaryName,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Text(
                        c.shortId,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    if (c.isDatabase) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          c.databaseType?.toUpperCase() ?? 'DB',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  c.image,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // 运行状态描述
          Expanded(
            flex: 2,
            child: Text(
              c.status,
              style: TextStyle(
                fontSize: 11.5,
                color: isRunning ? AppColors.textPrimary : AppColors.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 8),

          // 端口映射
          Expanded(
            flex: 2,
            child: c.formattedPorts.isEmpty
                ? const Text('-', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted))
                : Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: c.formattedPorts.map((portStr) {
                      return InkWell(
                        onTap: () {
                          final hostPort = portStr.split(':').first;
                          Clipboard.setData(ClipboardData(text: hostPort));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已复制端口: $hostPort'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.darkSurface,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            portStr,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10.5,
                              color: AppColors.primaryLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),

          const SizedBox(width: 8),

          // 紧凑操作按钮组 (固定 175px 宽度，彻底杜绝 RenderFlex overflow)
          SizedBox(
            width: 175,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (c.isDatabase) ...[
                  IconButton(
                    icon: Icon(
                      Icons.storage_rounded,
                      size: 18,
                      color: isRunning ? AppColors.primaryLight : AppColors.textMuted.withValues(alpha: 0.25),
                    ),
                    tooltip: isRunning ? '连接数据库 / 查看数据' : '容器未运行，无法连接',
                    onPressed: isRunning ? onOpenDatabase : null,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(3),
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  ),
                ],
                IconButton(
                  icon: Icon(
                    Icons.play_arrow_rounded,
                    size: 19,
                    color: isRunning ? AppColors.textMuted.withValues(alpha: 0.25) : AppColors.success,
                  ),
                  tooltip: isRunning ? '容器已在运行中' : '启动容器',
                  onPressed: isRunning
                      ? null
                      : () => onAction('start', '确定启动容器 ${c.primaryName}？', false),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(3),
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                ),
                IconButton(
                  icon: Icon(
                    Icons.stop_rounded,
                    size: 19,
                    color: isStopped ? AppColors.textMuted.withValues(alpha: 0.25) : AppColors.error,
                  ),
                  tooltip: isStopped ? '容器已处于停止状态' : '停止容器',
                  onPressed: isStopped
                      ? null
                      : () => onAction('stop', '确定停止容器 ${c.primaryName}？', true),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(3),
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                ),
                IconButton(
                  icon: const Icon(Icons.restart_alt_rounded, size: 17, color: AppColors.warning),
                  tooltip: '重启容器',
                  onPressed: () => onAction('restart', '确定重启容器 ${c.primaryName}？', false),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(3),
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                ),
                IconButton(
                  icon: const Icon(Icons.terminal_rounded, size: 17, color: AppColors.textSecondary),
                  tooltip: '查看容器日志',
                  onPressed: onShowLogs,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(3),
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 17, color: AppColors.textMuted),
                  tooltip: '更多操作',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onSelected: (val) {
                    if (val == 'db') {
                      onOpenDatabase();
                    } else if (val == 'logs') {
                      onShowLogs();
                    } else if (val == 'rm') {
                      onAction('rm', '确定删除容器 ${c.primaryName} 吗？\n镜像：${c.image}\n如果容器正在运行，将被强制删除！', true);
                    }
                  },
                  itemBuilder: (_) => [
                    if (c.isDatabase) ...[
                      const PopupMenuItem(
                        value: 'db',
                        height: 36,
                        child: Row(
                          children: [
                            Icon(Icons.storage_rounded, size: 15, color: AppColors.primaryLight),
                            SizedBox(width: 8),
                            Text('连接数据库', style: TextStyle(fontSize: 13, color: AppColors.primaryLight)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(height: 1),
                    ],
                    const PopupMenuItem(
                      value: 'logs',
                      height: 36,
                      child: Row(
                        children: [
                          Icon(Icons.terminal, size: 15),
                          SizedBox(width: 8),
                          Text('查看日志', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    const PopupMenuItem(
                      value: 'rm',
                      height: 36,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 15, color: AppColors.error),
                          SizedBox(width: 8),
                          Text('删除容器', style: TextStyle(color: AppColors.error, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
