import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/host_repository.dart';
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
      appBar: AppBar(title: const Text('桥坞')),
      body: FutureBuilder<List<HostProfile>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final hosts = snapshot.data!;
          if (hosts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有主机。点右下角添加。\n密钥和密码只保存在本机安全存储，不会进项目目录。',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: hosts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final host = hosts[index];
              return ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(host.name),
                subtitle: Text('${host.username}@${host.host}:${host.port}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openEditor(host),
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HostWorkspacePage(profile: host),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(null),
        icon: const Icon(Icons.add),
        label: const Text('添加主机'),
      ),
    );
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
