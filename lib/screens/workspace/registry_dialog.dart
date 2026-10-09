import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/registry_repository.dart';
import '../../services/remote_ops.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';

class RegistryManagerSheet extends StatefulWidget {
  const RegistryManagerSheet({super.key, required this.ops});
  final RemoteOps ops;

  static Future<void> show(BuildContext context, {required RemoteOps ops}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      builder: (_) => RegistryManagerSheet(ops: ops),
    );
  }

  @override
  State<RegistryManagerSheet> createState() => _RegistryManagerSheetState();
}

class _RegistryManagerSheetState extends State<RegistryManagerSheet> {
  late Future<List<DockerRegistryConfig>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = context.read<RegistryRepository>().list();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.85,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          Row(
            children: [
              const Icon(Icons.hub_outlined, color: AppColors.primaryLight, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '自定义镜像仓库管理',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加仓库'),
                onPressed: () => _openEditor(null),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '配置你的私有镜像仓库（如阿里云个人版 ACR、腾讯云 TCR、Harbor 等），一键执行 docker login 并快捷填充拉取前缀。',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),

          Expanded(
            child: FutureBuilder<List<DockerRegistryConfig>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }
                final list = snapshot.data!;
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 40, color: AppColors.textMuted),
                        const SizedBox(height: 12),
                        const Text(
                          '暂未配置任何私有镜像仓库',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '点击右上角「添加仓库」快速接入你的阿里云个人镜像仓库',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('立即添加阿里云个人仓库'),
                          onPressed: () => _openEditor(null),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = list[index];
                    return _RegistryItemCard(
                      item: item,
                      ops: widget.ops,
                      onEdit: () => _openEditor(item),
                      onDelete: () => _remove(item),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(DockerRegistryConfig? existing) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _RegistryEditDialog(existing: existing, ops: widget.ops),
    );
    if (result == true && mounted) {
      setState(_reload);
    }
  }

  Future<void> _remove(DockerRegistryConfig item) async {
    final ok = await confirmAction(
      context,
      title: '删除镜像仓库配置',
      body: '确定删除镜像仓库【${item.name}】(${item.prefix})？\n对应的账号密码也将从安全存储中删除。',
      confirmText: '确认删除',
      isDanger: true,
    );
    if (!ok || !mounted) return;
    await context.read<RegistryRepository>().remove(item.id);
    if (!mounted) return;
    showAppSuccess(context, '已删除镜像仓库配置');
    setState(_reload);
  }
}

class _RegistryItemCard extends StatefulWidget {
  const _RegistryItemCard({
    required this.item,
    required this.ops,
    required this.onEdit,
    required this.onDelete,
  });

  final DockerRegistryConfig item;
  final RemoteOps ops;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_RegistryItemCard> createState() => _RegistryItemCardState();
}

class _RegistryItemCardState extends State<_RegistryItemCard> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.item;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.cloud_queue_rounded, size: 20, color: AppColors.primaryLight),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '前缀: ${r.prefix}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: '编辑',
                onPressed: widget.onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                tooltip: '删除',
                onPressed: widget.onDelete,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                r.username.isNotEmpty ? '用户名: ${r.username}' : '未配置认证凭据',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const Spacer(),
              // 在服务器登录测试
              FilledButton.tonalIcon(
                onPressed: _testing ? null : _testLogin,
                icon: _testing
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.login, size: 14),
                label: Text(_testing ? '登录中...' : '在服务器登录'),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _testLogin() async {
    setState(() => _testing = true);
    final repo = context.read<RegistryRepository>();
    try {
      final pwd = await repo.getPassword(widget.item.id);
      if (pwd == null || pwd.isEmpty) {
        throw StateError('未配置仓库密码，请先编辑填入访问密码');
      }
      final res = await widget.ops.loginRegistry(
        registryUrl: widget.item.registryUrl,
        username: widget.item.username,
        password: pwd,
      );
      if (!mounted) return;
      showAppSuccess(context, '登录成功：$res');
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }
}

class _RegistryEditDialog extends StatefulWidget {
  const _RegistryEditDialog({this.existing, required this.ops});

  final DockerRegistryConfig? existing;
  final RemoteOps ops;

  @override
  State<_RegistryEditDialog> createState() => _RegistryEditDialogState();
}

class _RegistryEditDialogState extends State<_RegistryEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _namespaceController;
  late final TextEditingController _userController;
  late final TextEditingController _pwdController;
  bool _obscurePwd = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '阿里云个人镜像仓库');
    _urlController = TextEditingController(
      text: e?.registryUrl ?? 'registry.cn-hangzhou.aliyuncs.com',
    );
    _namespaceController = TextEditingController(text: e?.namespace ?? '');
    _userController = TextEditingController(text: e?.username ?? '');
    _pwdController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _namespaceController.dispose();
    _userController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  void _applyTemplate(String name, String url) {
    setState(() {
      _nameController.text = name;
      _urlController.text = url;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.add_to_photos_rounded, color: AppColors.primaryLight, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    widget.existing == null ? '添加镜像仓库配置' : '编辑镜像仓库配置',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 快速模板推荐
              const Text('快速填充常用私有仓库模板：', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: const Text('阿里云杭州 ACR', style: TextStyle(fontSize: 11)),
                    onPressed: () => _applyTemplate('阿里云杭州个人仓库', 'registry.cn-hangzhou.aliyuncs.com'),
                  ),
                  ActionChip(
                    label: const Text('阿里云北京 ACR', style: TextStyle(fontSize: 11)),
                    onPressed: () => _applyTemplate('阿里云北京个人仓库', 'registry.cn-beijing.aliyuncs.com'),
                  ),
                  ActionChip(
                    label: const Text('腾讯云 TCR', style: TextStyle(fontSize: 11)),
                    onPressed: () => _applyTemplate('腾讯云镜像仓库', 'ccr.ccs.tencentyun.com'),
                  ),
                  ActionChip(
                    label: const Text('自建 Harbor', style: TextStyle(fontSize: 11)),
                    onPressed: () => _applyTemplate('自建 Harbor', 'harbor.example.com'),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '仓库备注名称',
                  hintText: '如: 阿里云个人 ACR',
                ),
                validator: (v) => v == null || v.trim().isEmpty ? '必填' : null,
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Registry 域名地址',
                  hintText: '例如: registry.cn-hangzhou.aliyuncs.com',
                ),
                validator: (v) => v == null || v.trim().isEmpty ? '必填' : null,
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _namespaceController,
                decoration: const InputDecoration(
                  labelText: '命名空间 (Namespace)',
                  hintText: '在阿里云控制台创建的命名空间，如 anpy-dev',
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _userController,
                      decoration: const InputDecoration(
                        labelText: '登录用户名',
                        hintText: '阿里云登录账号/RAM账号',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _pwdController,
                      obscureText: _obscurePwd,
                      decoration: InputDecoration(
                        labelText: widget.existing != null ? '登录密码 (留空不改)' : '登录固定密码',
                        hintText: 'ACR设置的独立密码',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePwd ? Icons.visibility_off : Icons.visibility,
                            size: 16,
                          ),
                          onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中...' : '保存配置'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = context.read<RegistryRepository>();
    try {
      await repo.save(
        existingId: widget.existing?.id,
        name: _nameController.text.trim(),
        registryUrl: _urlController.text.trim(),
        namespace: _namespaceController.text.trim(),
        username: _userController.text.trim(),
        password: _pwdController.text.isNotEmpty ? _pwdController.text : null,
      );
      if (!mounted) return;
      showAppSuccess(context, '镜像仓库配置已保存');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
