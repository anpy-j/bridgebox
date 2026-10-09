import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/host_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';
import 'host_editor_page.dart';
import 'host_workspace_page.dart';

class HostListPage extends StatefulWidget {
  const HostListPage({super.key});

  @override
  State<HostListPage> createState() => _HostListPageState();
}

class _HostListPageState extends State<HostListPage> {
  late Future<List<HostProfile>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = context.read<HostRepository>().list();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primaryGlow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.hub_rounded, size: 20, color: AppColors.primaryLight),
            ),
            const SizedBox(width: 10),
            const Text('桥坞 Bridgebox'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: const Text(
                'v0.1.0',
                style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: '刷新列表',
            onPressed: () => setState(_reload),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<HostProfile>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
          }
          final hosts = snapshot.data!;
          if (hosts.isEmpty) {
            return _buildEmptyView();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(18),
            itemCount: hosts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final host = hosts[index];
              return _HostCard(
                host: host,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HostWorkspacePage(profile: host),
                    ),
                  );
                  if (!mounted) return;
                  setState(_reload);
                },
                onEdit: () => _openEditor(host),
                onDelete: () => _deleteHost(host),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(null),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加服务器', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: const Icon(Icons.dns_rounded, size: 48, color: AppColors.primaryLight),
            ),
            const SizedBox(height: 20),
            const Text(
              '还没有添加任何服务器',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            const Text(
              '点击下方按钮添加你的第一台 Linux 主机。\n支持通过 SSH 密码或私钥安全管理 Docker、服务与监控，私钥仅保存于本机安全存储。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _openEditor(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('立即添加主机'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteHost(HostProfile host) async {
    final ok = await confirmAction(
      context,
      title: '删除主机',
      body: '确定从本地删除主机【${host.name}】(${host.host})？\n对应的连接凭据也将从系统钥匙串中彻底清除。',
      confirmText: '确认删除',
      isDanger: true,
    );
    if (!ok || !mounted) return;
    await context.read<HostRepository>().remove(host.id);
    if (!mounted) return;
    showAppSuccess(context, '已删除主机 ${host.name}');
    setState(_reload);
  }

  Future<void> _openEditor(HostProfile? host) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostEditorPage(existing: host),
      ),
    );
    if (!mounted) return;
    setState(_reload);
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({
    required this.host,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final HostProfile host;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isKeyAuth = host.authKind == AuthKind.privateKey;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          hoverColor: AppColors.darkCardHover,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 主机图标
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  child: const Icon(Icons.storage_rounded, size: 24, color: AppColors.primaryLight),
                ),
                const SizedBox(width: 14),

                // 主机信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            host.name,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 鉴权类型徽章
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AppColors.darkSurface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.darkBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isKeyAuth ? Icons.key_rounded : Icons.password_rounded,
                                  size: 11,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isKeyAuth ? 'SSH 私钥' : '密码认证',
                                  style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${host.username}@${host.host}:${host.port}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // 右侧操作
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                  tooltip: '编辑主机',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                  tooltip: '删除主机',
                  onPressed: onDelete,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
