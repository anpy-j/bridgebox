import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/host_repository.dart';
import '../widgets/metric_tile.dart';

class HostEditorPage extends StatefulWidget {
  const HostEditorPage({super.key, this.existing});

  final HostProfile? existing;

  @override
  State<HostEditorPage> createState() => _HostEditorPageState();
}

class _HostEditorPageState extends State<HostEditorPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _password;
  late final TextEditingController _passphrase;
  AuthKind _auth = AuthKind.privateKey;
  String? _pem;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.host ?? '');
    _port = TextEditingController(text: '${e?.port ?? 22}');
    _user = TextEditingController(text: e?.username ?? '');
    _password = TextEditingController();
    _passphrase = TextEditingController();
    _auth = e?.authKind ?? AuthKind.privateKey;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑主机' : '添加主机'),
        actions: [
          if (editing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '显示名称'),
              validator: _required,
            ),
            TextFormField(
              controller: _host,
              decoration: const InputDecoration(labelText: '主机 / IP'),
              validator: _required,
            ),
            TextFormField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'SSH 端口'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1 || n > 65535) return '端口无效';
                return null;
              },
            ),
            TextFormField(
              controller: _user,
              decoration: const InputDecoration(labelText: '用户名'),
              validator: _required,
            ),
            const SizedBox(height: 16),
            SegmentedButton<AuthKind>(
              segments: const [
                ButtonSegment(
                  value: AuthKind.privateKey,
                  label: Text('私钥'),
                  icon: Icon(Icons.key_outlined),
                ),
                ButtonSegment(
                  value: AuthKind.password,
                  label: Text('密码'),
                  icon: Icon(Icons.password),
                ),
              ],
              selected: {_auth},
              onSelectionChanged: (next) => setState(() => _auth = next.first),
            ),
            const SizedBox(height: 16),
            if (_auth == AuthKind.password)
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: editing ? '密码（留空则不改）' : '密码',
                ),
                validator: (v) {
                  if (!editing && (v == null || v.isEmpty)) return '请填写密码';
                  return null;
                },
              )
            else ...[
              FilledButton.tonalIcon(
                onPressed: _pickKey,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(_pem == null ? '从本机选择私钥文件' : '已导入私钥（未写入项目目录）'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passphrase,
                obscureText: true,
                decoration: const InputDecoration(labelText: '私钥口令（可选）'),
              ),
              if (!editing && _pem == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('添加主机时请导入私钥。文件只读入内存并写入系统安全存储。'),
                ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? '必填' : null;

  Future<void> _pickKey() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.any,
    );
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) showAppError(context, '无法读取该文件');
      return;
    }
    setState(() => _pem = String.fromCharCodes(bytes));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_auth == AuthKind.privateKey &&
        widget.existing == null &&
        _pem == null) {
      showAppError(context, '请先选择私钥文件');
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<HostRepository>().upsert(
            existing: widget.existing,
            name: _name.text.trim(),
            host: _host.text.trim(),
            port: int.parse(_port.text.trim()),
            username: _user.text.trim(),
            authKind: _auth,
            password: _password.text,
            privateKeyPem: _pem,
            keyPassphrase: _passphrase.text,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final host = widget.existing;
    if (host == null) return;
    final ok = await confirmAction(
      context,
      title: '删除主机',
      body: '将删除本机保存的连接信息和密钥，不影响服务器。',
    );
    if (!ok || !mounted) return;
    await context.read<HostRepository>().remove(host.id);
    if (mounted) Navigator.of(context).pop();
  }
}
