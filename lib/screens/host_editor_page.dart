import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/host_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialogs.dart';

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
  String? _pemFileName;
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscurePassphrase = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.host ?? '');
    _port = TextEditingController(text: '${e?.port ?? 22}');
    _user = TextEditingController(text: e?.username ?? 'root');
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
        title: Text(editing ? '编辑服务器配置' : '添加新服务器'),
        actions: [
          if (editing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              tooltip: '删除此服务器',
              onPressed: _delete,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // 分组 1：基础连接参数
            _buildSectionCard(
              title: '基础连接参数',
              icon: Icons.dns_rounded,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '主机别名 / 备注名称',
                    hintText: '例如: 腾讯云香港生产机',
                    prefixIcon: Icon(Icons.badge_outlined, size: 18),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 7,
                      child: TextFormField(
                        controller: _host,
                        decoration: const InputDecoration(
                          labelText: 'IP 地址 / 域名',
                          hintText: '1.2.3.4 或 server.example.com',
                          prefixIcon: Icon(Icons.public_outlined, size: 18),
                        ),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _port,
                        decoration: const InputDecoration(
                          labelText: 'SSH 端口',
                          hintText: '22',
                          prefixIcon: Icon(Icons.numbers, size: 18),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n < 1 || n > 65535) return '端口无效';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _user,
                  decoration: const InputDecoration(
                    labelText: '登录用户名',
                    hintText: '如 root, ubuntu, debian',
                    prefixIcon: Icon(Icons.person_outline, size: 18),
                  ),
                  validator: _required,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 分组 2：SSH 鉴权凭据
            _buildSectionCard(
              title: 'SSH 安全认证方式',
              icon: Icons.security_rounded,
              children: [
                SegmentedButton<AuthKind>(
                  segments: const [
                    ButtonSegment(
                      value: AuthKind.privateKey,
                      label: Text('SSH 密钥 (推荐)'),
                      icon: Icon(Icons.key_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: AuthKind.password,
                      label: Text('密码认证'),
                      icon: Icon(Icons.password_rounded, size: 16),
                    ),
                  ],
                  selected: {_auth},
                  onSelectionChanged: (next) => setState(() => _auth = next.first),
                ),
                const SizedBox(height: 16),

                if (_auth == AuthKind.password) ...[
                  TextFormField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: editing ? 'SSH 登录密码（留空则保持原密码）' : 'SSH 登录密码',
                      prefixIcon: const Icon(Icons.lock_outline, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (!editing && (v == null || v.isEmpty)) return '请填写密码';
                      return null;
                    },
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.darkSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _pem != null
                            ? AppColors.primaryLight.withValues(alpha: 0.5)
                            : AppColors.darkBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _pem != null ? Icons.check_circle_rounded : Icons.file_present_rounded,
                              color: _pem != null ? AppColors.success : AppColors.textMuted,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _pemFileName != null
                                    ? '已选择: $_pemFileName'
                                    : (editing && _pem == null)
                                        ? '已配置私钥（点击下方按钮可更换）'
                                        : '尚未选择私钥文件',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _pem != null ? AppColors.textPrimary : AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: _pickKey,
                              child: Text(_pem == null ? '导入私钥' : '重新选择'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '支持 id_rsa, id_ed25519, .pem 等格式，私钥文件仅在读取后存入系统钥匙串，绝不落地。',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passphrase,
                    obscureText: _obscurePassphrase,
                    decoration: InputDecoration(
                      labelText: '私钥口令 Passphrase (若私钥未加密请留空)',
                      prefixIcon: const Icon(Icons.vpn_key_outlined, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassphrase ? Icons.visibility_off : Icons.visibility,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _obscurePassphrase = !_obscurePassphrase),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // 安全承诺说明卡片
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.darkCard.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.darkBorder.withValues(alpha: 0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: AppColors.primaryLight),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '安全存储：所有密码与私钥使用系统级 Keychain 加密保护，配置文件仅保留服务器网络元数据。',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 保存按钮
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(editing ? '保存修改' : '立即添加服务器'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryLight),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? '此项为必填项' : null;

  Future<void> _pickKey() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.any,
    );
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) showAppError(context, '无法读取该文件，请检查文件权限');
      return;
    }
    setState(() {
      _pem = String.fromCharCodes(bytes);
      _pemFileName = file.name;
    });
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
    final repo = context.read<HostRepository>();
    try {
      await repo.upsert(
        existing: widget.existing,
        name: _name.text.trim(),
        host: _host.text.trim(),
        port: int.parse(_port.text.trim()),
        username: _user.text.trim(),
        authKind: _auth,
        password: _password.text.isEmpty ? null : _password.text,
        privateKeyPem: _pem,
        keyPassphrase: _passphrase.text.isEmpty ? null : _passphrase.text,
      );
      if (!mounted) return;
      showAppSuccess(context, '服务器配置已安全保存');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmAction(
      context,
      title: '删除服务器',
      body: '确定删除此服务器配置？保存的密钥也将从系统钥匙串中彻底清除。',
      confirmText: '确认删除',
      isDanger: true,
    );
    if (!ok || !mounted) return;
    await context.read<HostRepository>().remove(widget.existing!.id);
    if (!mounted) return;
    showAppSuccess(context, '已删除该服务器');
    Navigator.pop(context);
  }
}
