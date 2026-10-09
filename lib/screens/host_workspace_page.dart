import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/remote_ops.dart';
import '../services/secure_secrets.dart';
import '../services/ssh_session.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'workspace_tabs.dart';

class HostWorkspacePage extends StatefulWidget {
  const HostWorkspacePage({super.key, required this.profile});

  final HostProfile profile;

  @override
  State<HostWorkspacePage> createState() => _HostWorkspacePageState();
}

class _HostWorkspacePageState extends State<HostWorkspacePage> {
  late final SshSession _session;
  late final RemoteOps _ops;
  Object? _error;
  bool _ready = false;
  bool _connecting = true;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _session = SshSession(
      profile: widget.profile,
      secrets: context.read<SecureSecrets>(),
    );
    _ops = RemoteOps(_session);
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await _session.connect();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _connecting = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _connecting = false;
      });
    }
  }

  @override
  void dispose() {
    _session.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;

    Widget mainContent;
    if (_connecting) {
      mainContent = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 16),
            Text(
              '正在建立 SSH 安全会话至 ${widget.profile.host}:${widget.profile.port}...',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
            ),
          ],
        ),
      );
    } else if (_error != null && !_ready) {
      mainContent = Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              const Text(
                'SSH 连接失败',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('返回列表'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _connect,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重新连接'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      mainContent = WorkspaceTabs(ops: _ops, index: _index);
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Text(
              widget.profile.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 10),
            // IP & 端口小徽章
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.terminal, size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.profile.username}@${widget.profile.host}:${widget.profile.port}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // 在线状态
            if (_ready)
              StatusBadge.running('在线 (Connected)')
            else if (_connecting)
              StatusBadge.restarting('连接中...')
            else
              StatusBadge.failed('连接断开'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, size: 18),
            tooltip: '重连 SSH 会话',
            onPressed: _connect,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(
              children: [
                // 桌面端专属专业运维控制台侧边栏
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  minWidth: 84,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGlow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.dns_rounded, color: AppColors.primaryLight, size: 22),
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.speed_rounded),
                      selectedIcon: Icon(Icons.speed_rounded, color: AppColors.primaryLight),
                      label: Text('概览'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.miscellaneous_services_rounded),
                      selectedIcon: Icon(Icons.miscellaneous_services_rounded, color: AppColors.primaryLight),
                      label: Text('服务'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_rounded),
                      selectedIcon: Icon(Icons.inventory_2_rounded, color: AppColors.primaryLight),
                      label: Text('容器'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.layers_rounded),
                      selectedIcon: Icon(Icons.layers_rounded, color: AppColors.primaryLight),
                      label: Text('镜像'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: mainContent),
              ],
            )
          : mainContent,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.speed_rounded),
                  label: '概览',
                ),
                NavigationDestination(
                  icon: Icon(Icons.miscellaneous_services_rounded),
                  label: '服务',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_rounded),
                  label: '容器',
                ),
                NavigationDestination(
                  icon: Icon(Icons.layers_rounded),
                  label: '镜像',
                ),
              ],
            ),
    );
  }
}
