import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/registry_repository.dart';
import '../../services/remote_ops.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import 'registry_dialog.dart';

class PullImageDialog extends StatefulWidget {
  const PullImageDialog({super.key, required this.ops});
  final RemoteOps ops;

  static Future<bool?> show(BuildContext context, {required RemoteOps ops}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PullImageDialog(ops: ops),
    );
  }

  @override
  State<PullImageDialog> createState() => _PullImageDialogState();
}

class _PullImageDialogState extends State<PullImageDialog> {
  final TextEditingController _imageController = TextEditingController();
  List<DockerRegistryConfig> _customRegistries = [];
  String _selectedRegistryPrefix = '';
  bool _isLoadingRegistries = true;
  bool _pulling = false;
  String? _pullError;

  @override
  void initState() {
    super.initState();
    _loadRegistries();
  }

  Future<void> _loadRegistries() async {
    try {
      final list = await context.read<RegistryRepository>().list();
      if (!mounted) return;
      setState(() {
        _customRegistries = list;
        _isLoadingRegistries = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingRegistries = false);
    }
  }

  @override
  void dispose() {
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _doPull() async {
    final input = _imageController.text.trim();
    if (input.isEmpty) return;

    var fullRef = input;
    if (_selectedRegistryPrefix.isNotEmpty) {
      if (fullRef.startsWith(_selectedRegistryPrefix)) {
        // 用户已包含前缀
      } else {
        fullRef = fullRef.replaceFirst(RegExp(r'^/+'), '');
        fullRef = '$_selectedRegistryPrefix$fullRef';
      }
    }
    fullRef = fullRef.replaceAll(RegExp(r'(?<!:)/{2,}'), '/');

    setState(() {
      _pulling = true;
      _pullError = null;
    });

    try {
      await widget.ops.pullImage(fullRef);
      if (!mounted) return;
      showAppSuccess(context, '镜像 $fullRef 拉取成功');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pulling = false;
        _pullError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTarget = _selectedRegistryPrefix.isEmpty
        ? 'docker.io (Docker 官方公有仓库)'
        : _selectedRegistryPrefix;

    return Dialog(
      backgroundColor: AppColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.cloud_download_outlined, color: AppColors.primaryLight, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '拉取 Docker 镜像',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '从 Docker Hub、阿里云或私有 Registry 检索并下载镜像',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                    tooltip: '关闭',
                    onPressed: _pulling ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 目标仓库源提示条 + 管理私有仓库入口
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hub_outlined, size: 15, color: AppColors.primaryLight),
                    const SizedBox(width: 8),
                    const Text(
                      '目标源：',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                    ),
                    Expanded(
                      child: Text(
                        currentTarget,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryLight,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: _pulling
                          ? null
                          : () async {
                              await RegistryManagerSheet.show(context, ops: widget.ops);
                              _loadRegistries();
                            },
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.tune, size: 13, color: AppColors.primaryLight),
                            SizedBox(width: 4),
                            Text(
                              '管理私有仓库',
                              style: TextStyle(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 预设仓库选择芯片
              const Text(
                '快捷选择镜像源：',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              if (_isLoadingRegistries)
                const SizedBox(height: 32, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _PresetChip(
                      label: 'Docker Hub 官方',
                      selected: _selectedRegistryPrefix == '',
                      onTap: () => setState(() => _selectedRegistryPrefix = ''),
                    ),
                    ..._customRegistries.map(
                      (r) => _PresetChip(
                        label: '${r.name}${r.namespace.isNotEmpty ? " (${r.namespace})" : ""}',
                        isCustom: true,
                        selected: _selectedRegistryPrefix == r.prefix,
                        onTap: () => setState(() => _selectedRegistryPrefix = r.prefix),
                      ),
                    ),
                    _PresetChip(
                      label: '阿里云加速',
                      selected: _selectedRegistryPrefix == 'registry.cn-hangzhou.aliyuncs.com/',
                      onTap: () => setState(() => _selectedRegistryPrefix = 'registry.cn-hangzhou.aliyuncs.com/'),
                    ),
                    _PresetChip(
                      label: 'GitHub Packages',
                      selected: _selectedRegistryPrefix == 'ghcr.io/',
                      onTap: () => setState(() => _selectedRegistryPrefix = 'ghcr.io/'),
                    ),
                    _PresetChip(
                      label: '腾讯云源',
                      selected: _selectedRegistryPrefix == 'ccr.ccs.tencentyun.com/',
                      onTap: () => setState(() => _selectedRegistryPrefix = 'ccr.ccs.tencentyun.com/'),
                    ),
                  ],
                ),
              const SizedBox(height: 16),

              // 镜像名称输入框
              TextField(
                controller: _imageController,
                enabled: !_pulling,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '镜像名称与标签',
                  hintText: '例如 nginx:alpine 或 postgres:16-alpine',
                  prefixText: _selectedRegistryPrefix.isNotEmpty ? _selectedRegistryPrefix : null,
                  prefixStyle: const TextStyle(
                    fontFamily: 'monospace',
                    color: AppColors.primaryLight,
                    fontSize: 13,
                  ),
                ),
                onSubmitted: (_) => _doPull(),
              ),

              // 报错信息展示
              if (_pullError != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _pullError!,
                          style: const TextStyle(fontSize: 12, color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // 底部按钮栏
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _pulling ? null : () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _pulling ? null : _doPull,
                    icon: _pulling
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download, size: 16),
                    label: Text(_pulling ? '正在拉取...' : '开始拉取'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isCustom = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCustom) ...[
            const Icon(Icons.lock_outline, size: 11, color: AppColors.warning),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(fontSize: 12, color: selected ? AppColors.primaryLight : AppColors.textSecondary)),
        ],
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: AppColors.primary.withValues(alpha: 0.18),
      side: BorderSide(
        color: selected
            ? AppColors.primaryLight
            : (isCustom ? AppColors.warning.withValues(alpha: 0.4) : AppColors.darkBorder),
      ),
    );
  }
}
