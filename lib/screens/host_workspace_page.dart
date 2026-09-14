import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/remote_ops.dart';
import '../services/secure_secrets.dart';
import '../services/ssh_session.dart';
import '../widgets/metric_tile.dart';
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
    try {
      await _session.connect();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
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
    final destinations = const [
      NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), label: '概览'),
      NavigationDestination(icon: Icon(Icons.settings_suggest_outlined), label: '服务'),
      NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: '容器'),
      NavigationDestination(icon: Icon(Icons.layers_outlined), label: '镜像'),
    ];

    Widget body;
    if (_error != null && !_ready) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('连接失败：$_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _connect, child: const Text('重试')),
            ],
          ),
        ),
      );
    } else if (!_ready) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = WorkspaceTabs(ops: _ops, index: _index);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile.name),
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.monitor_heart_outlined),
                      label: Text('概览'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_suggest_outlined),
                      label: Text('服务'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      label: Text('容器'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.layers_outlined),
                      label: Text('镜像'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              destinations: destinations,
              onDestinationSelected: (i) => setState(() => _index = i),
            ),
    );
  }
}
