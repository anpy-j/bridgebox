import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/remote_ops.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import '../../widgets/status_badge.dart';
import 'database_explorer_dialog.dart';

class ServicesTab extends StatefulWidget {
  const ServicesTab({super.key, required this.ops});
  final RemoteOps ops;

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> {
  late Future<List<ServiceUnit>> _future;
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, running, stopped, failed
  bool _sysExpanded = false;

  @override
  void initState() {
    super.initState();
    _future = widget.ops.listServices();
  }

  void _reload() => setState(() {
        _future = widget.ops.listServices();
      });

  void _openDatabase(ServiceUnit unit) {
    DatabaseExplorerDialog.show(
      context,
      ops: widget.ops,
      target: DatabaseTarget(
        kind: DatabaseTargetKind.service,
        identifier: unit.name,
        type: unit.databaseType,
        displayName: unit.name,
        defaultPort: unit.databaseType == 'mysql' ? 3306 : (unit.databaseType == 'redis' ? 6379 : 5432),
        defaultUser: unit.databaseType == 'mysql' ? 'root' : 'postgres',
        defaultDatabase: unit.databaseType == 'mysql' ? 'mysql' : 'postgres',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ServiceUnit>>(
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
                  Text('加载服务列表失败：${snapshot.error}', style: const TextStyle(color: AppColors.textSecondary)),
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
                Text('正在获取 systemd 服务状态...', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          );
        }

        final allItems = snapshot.data!;
        
        // 过滤
        final filtered = allItems.where((u) {
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            if (!u.name.toLowerCase().contains(q) &&
                !u.description.toLowerCase().contains(q)) {
              return false;
            }
          }
          if (_statusFilter == 'running') return u.running;
          if (_statusFilter == 'stopped') return !u.running && !u.failed;
          if (_statusFilter == 'failed') return u.failed;
          return true;
        }).toList();

        // 拆分为 自建/应用服务 vs 系统服务
        final appServices = filtered.where((u) => u.isAppService).toList();
        final sysServices = filtered.where((u) => !u.isAppService).toList();

        final appRunningCount = appServices.where((u) => u.running).length;
        final sysRunningCount = sysServices.where((u) => u.running).length;

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 顶部搜索与过滤栏
              _buildFilterBar(allItems.length, appServices.length, sysServices.length),
              const SizedBox(height: 16),

              // 自建与业务服务区域（高亮突出，默认展示）
              Row(
                children: [
                  const Icon(Icons.apps_rounded, color: AppColors.primaryLight, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '自建与应用服务',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGlow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${appServices.length} 个 ($appRunningCount 运行中)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (appServices.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _searchQuery.isNotEmpty ? '没有匹配的应用服务' : '未检测到常见应用服务',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                )
              else
                ...appServices.map((u) => _ServiceCard(
                      unit: u,
                      onControl: (action, desc) => _act(u.name, action, desc),
                      onOpenDatabase: () => _openDatabase(u),
                    )),

              const SizedBox(height: 24),

              // 系统服务区域（默认折叠）
              Container(
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: _sysExpanded,
                    onExpansionChanged: (v) => setState(() => _sysExpanded = v),
                    leading: const Icon(Icons.settings_system_daydream, color: AppColors.textMuted, size: 22),
                    title: Row(
                      children: [
                        const Text(
                          '系统底层服务',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(${sysServices.length} 个 · $sysRunningCount 运行中)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      _sysExpanded ? '已展开系统底层服务' : '已自动折叠系统底层守护进程，点击可展开排查',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                    children: [
                      const Divider(height: 1, color: AppColors.darkBorder),
                      if (sysServices.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('无匹配的系统服务', style: TextStyle(color: AppColors.textMuted)),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: sysServices.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.darkBorder),
                          itemBuilder: (context, index) {
                            final unit = sysServices[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                unit.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                unit.description.isNotEmpty ? unit.description : '${unit.load} / ${unit.sub}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  unit.running
                                      ? StatusBadge.running('运行中')
                                      : StatusBadge.stopped('已停止'),
                                  const SizedBox(width: 8),
                                   PopupMenuButton<String>(
                                     icon: const Icon(Icons.more_vert, size: 18),
                                     onSelected: (action) {
                                       if (action == 'db') {
                                         _openDatabase(unit);
                                       } else {
                                         _act(unit.name, action, '$action ${unit.name}？');
                                       }
                                     },
                                     itemBuilder: (_) => [
                                       if (unit.isDatabase) ...[
                                         const PopupMenuItem(
                                           value: 'db',
                                           child: Row(
                                             children: [
                                               Icon(Icons.storage_rounded, size: 15, color: AppColors.primaryLight),
                                               SizedBox(width: 8),
                                               Text('连接数据库', style: TextStyle(color: AppColors.primaryLight)),
                                             ],
                                           ),
                                         ),
                                         const PopupMenuDivider(),
                                       ],
                                       const PopupMenuItem(value: 'start', child: Text('启动')),
                                       const PopupMenuItem(value: 'stop', child: Text('停止')),
                                       const PopupMenuItem(value: 'restart', child: Text('重启')),
                                     ],
                                   ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterBar(int total, int appCount, int sysCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 42,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索服务名称或描述 (如: postgresql, nginx, docker)...',
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
            const SizedBox(width: 10),
            IconButton.filledTonal(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: '刷新服务',
              onPressed: _reload,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            _FilterChip(
              label: '全部',
              selected: _statusFilter == 'all',
              onSelected: () => setState(() => _statusFilter = 'all'),
            ),
            _FilterChip(
              label: '运行中',
              selected: _statusFilter == 'running',
              onSelected: () => setState(() => _statusFilter = 'running'),
            ),
            _FilterChip(
              label: '已停止',
              selected: _statusFilter == 'stopped',
              onSelected: () => setState(() => _statusFilter = 'stopped'),
            ),
            _FilterChip(
              label: '启动失败',
              selected: _statusFilter == 'failed',
              onSelected: () => setState(() => _statusFilter = 'failed'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _act(String unit, String action, String body) async {
    final ok = await confirmAction(
      context,
      title: '服务控制确认',
      body: body,
      confirmText: action == 'stop' ? '确认停止' : '确认执行',
      isDanger: action == 'stop',
    );
    if (!ok || !mounted) return;
    try {
      await widget.ops.controlService(unit, action);
      if (!mounted) return;
      showAppSuccess(context, '已发送 $action 指令给 $unit');
      _reload();
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      selectedColor: AppColors.primaryGlow,
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.darkBorder,
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.unit,
    required this.onControl,
    required this.onOpenDatabase,
  });

  final ServiceUnit unit;
  final Function(String action, String desc) onControl;
  final VoidCallback onOpenDatabase;

  @override
  Widget build(BuildContext context) {
    final iconData = switch (unit.category) {
      '数据库' => Icons.storage_rounded,
      'Web / 代理' => Icons.public_rounded,
      '容器 / 运行时' => Icons.inventory_2_rounded,
      _ => Icons.terminal_rounded,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unit.failed
              ? AppColors.error.withValues(alpha: 0.5)
              : AppColors.darkBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图标
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Icon(iconData, size: 20, color: AppColors.primaryLight),
          ),
          const SizedBox(width: 12),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        unit.name,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Text(
                        unit.category,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  unit.description.isNotEmpty ? unit.description : '单元状态: ${unit.load} · ${unit.sub}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (unit.running)
                      StatusBadge.running('运行中 (Active)')
                    else if (unit.failed)
                      StatusBadge.failed('异常失败 (Failed)')
                    else
                      StatusBadge.stopped('已停止 (${unit.active})'),
                  ],
                ),
              ],
            ),
          ),
          // 操作按钮组
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unit.isDatabase) ...[
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.storage_rounded, size: 14),
                  label: const Text('连接数据库', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: unit.running ? onOpenDatabase : null,
                ),
                const SizedBox(width: 6),
              ],
              IconButton(
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                tooltip: '启动服务',
                color: AppColors.success,
                onPressed: unit.running
                    ? null
                    : () => onControl('start', '确定启动服务 ${unit.name} 吗？'),
              ),
              IconButton(
                icon: const Icon(Icons.stop_rounded, size: 20),
                tooltip: '停止服务',
                color: AppColors.error,
                onPressed: !unit.running
                    ? null
                    : () => onControl('stop', '确定停止服务 ${unit.name} 吗？这可能影响正在运行的业务！'),
              ),
              IconButton(
                icon: const Icon(Icons.restart_alt_rounded, size: 20),
                tooltip: '重启服务',
                color: AppColors.warning,
                onPressed: () => onControl('restart', '确定重启服务 ${unit.name} 吗？'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
