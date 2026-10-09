import 'package:flutter/material.dart';
import '../../services/remote_ops.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';

enum RunContainerMode {
  form,
  script,
}

class RunContainerDialog extends StatefulWidget {
  const RunContainerDialog({
    super.key,
    required this.ops,
    required this.initialImage,
  });

  final RemoteOps ops;
  final String initialImage;

  static Future<bool?> show(
    BuildContext context, {
    required RemoteOps ops,
    required String image,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => RunContainerDialog(ops: ops, initialImage: image),
    );
  }

  @override
  State<RunContainerDialog> createState() => _RunContainerDialogState();
}

class _RunContainerDialogState extends State<RunContainerDialog> {
  RunContainerMode _mode = RunContainerMode.form;
  final _formKey = GlobalKey<FormState>();
  final _scriptFormKey = GlobalKey<FormState>();

  late final TextEditingController _imageController;
  late final TextEditingController _nameController;
  late final TextEditingController _portsController;
  late final TextEditingController _envController;
  late final TextEditingController _volumesController;
  late final TextEditingController _scriptController;

  bool _restartAlways = true;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _imageController = TextEditingController(text: widget.initialImage);

    // 从镜像名称中智能提取默认容器名称
    var defaultName = widget.initialImage.split('/').last.split(':').first;
    defaultName = defaultName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '-');
    if (defaultName.isEmpty || defaultName == '<none>') {
      defaultName = 'app-${DateTime.now().millisecondsSinceEpoch % 1000}';
    } else {
      defaultName = '$defaultName-1';
    }

    _nameController = TextEditingController(text: defaultName);
    _portsController = TextEditingController();
    _envController = TextEditingController();
    _volumesController = TextEditingController();

    // 初始化命令行脚本模板
    _scriptController = TextEditingController(
      text: _buildDefaultScript(
        image: widget.initialImage.isNotEmpty
            ? widget.initialImage
            : 'registry.cn-hangzhou.aliyuncs.com/<你的命名空间>/qianchuan-backend:latest',
        name: defaultName,
      ),
    );
  }

  @override
  void dispose() {
    _imageController.dispose();
    _nameController.dispose();
    _portsController.dispose();
    _envController.dispose();
    _volumesController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  String _buildDefaultScript({required String image, required String name}) {
    return '''mkdir -p data
docker run -d \\
  --name $name \\
  --restart always \\
  -p 8088:8088 \\
  -v "\$(pwd)/data:/app/data" \\
  -e TZ=Asia/Shanghai \\
  -e DB_PATH=/app/data/qianchuan.db \\
  $image''';
  }

  String _generateScriptFromForm() {
    final img = _imageController.text.trim().isNotEmpty
        ? _imageController.text.trim()
        : (widget.initialImage.isNotEmpty ? widget.initialImage : 'nginx:latest');
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'my-service';
    final ports = _portsController.text
        .split(RegExp(r'[,;\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final envs = _envController.text
        .split(RegExp(r'[,;\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final volumes = _volumesController.text
        .split(RegExp(r'[,;\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final buffer = StringBuffer();

    // 解析挂载的本地目录并生成 mkdir -p 前置命令
    final hostDirs = <String>{};
    if (volumes.isNotEmpty) {
      for (final v in volumes) {
        final hostPart = v.split(':').first.trim();
        if (hostPart.isNotEmpty && !hostPart.startsWith('/var/run/docker.sock')) {
          final clean = hostPart.replaceAll(RegExp(r'["\$\(\)]'), '').trim();
          if (clean.isNotEmpty) {
            hostDirs.add(clean);
          }
        }
      }
    } else {
      hostDirs.add('data');
    }

    if (hostDirs.isNotEmpty) {
      for (final d in hostDirs) {
        buffer.writeln('mkdir -p $d');
      }
    }

    buffer.write('docker run -d \\\n  --name $name');
    if (_restartAlways) {
      buffer.write(' \\\n  --restart always');
    }
    if (ports.isNotEmpty) {
      for (final p in ports) {
        buffer.write(' \\\n  -p $p');
      }
    } else {
      buffer.write(' \\\n  -p 8080:8080');
    }
    if (volumes.isNotEmpty) {
      for (final v in volumes) {
        buffer.write(' \\\n  -v "$v"');
      }
    } else {
      buffer.write(' \\\n  -v "\$(pwd)/data:/app/data"');
    }
    if (envs.isNotEmpty) {
      for (final e in envs) {
        buffer.write(' \\\n  -e $e');
      }
    } else {
      buffer.write(' \\\n  -e TZ=Asia/Shanghai');
    }
    buffer.write(' \\\n  $img');

    return buffer.toString();
  }

  void _syncFormToScript() {
    setState(() {
      _scriptController.text = _generateScriptFromForm();
      _mode = RunContainerMode.script;
    });
    showAppSuccess(context, '已将当前表单内容转换为命令行脚本');
  }

  void _insertScriptSnippet(String snippet) {
    final text = _scriptController.text;
    final selection = _scriptController.selection;
    if (selection.isValid && selection.start >= 0 && selection.end >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, snippet);
      _scriptController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + snippet.length),
      );
    } else {
      _scriptController.text = '$text\n$snippet';
    }
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
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题栏
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.successGlow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.rocket_launch_rounded, color: AppColors.success, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '创建并启动新容器',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 模式切换 SegmentedButton
              SegmentedButton<RunContainerMode>(
                segments: const [
                  ButtonSegment(
                    value: RunContainerMode.form,
                    label: Text('逐项表单模式'),
                    icon: Icon(Icons.format_list_bulleted_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: RunContainerMode.script,
                    label: Text('命令行脚本模式'),
                    icon: Icon(Icons.terminal_rounded, size: 16),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (set) {
                  setState(() => _mode = set.first);
                },
              ),
              const SizedBox(height: 16),

              // 模式内容
              if (_mode == RunContainerMode.form) _buildFormMode() else _buildScriptMode(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormMode() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 镜像名称
          TextFormField(
            controller: _imageController,
            decoration: const InputDecoration(
              labelText: '镜像引用 (Image Ref)',
              prefixIcon: Icon(Icons.layers_outlined, size: 18),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? '镜像不能为空' : null,
          ),
          const SizedBox(height: 12),

          // 容器名称
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '容器名称 (--name)',
              hintText: '如 my-service',
              prefixIcon: Icon(Icons.inventory_2_outlined, size: 18),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return '容器名称不能为空';
              if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$').hasMatch(v.trim())) {
                return '名称仅支持字母、数字、点、横杠与下划线';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // 端口映射
          TextFormField(
            controller: _portsController,
            decoration: const InputDecoration(
              labelText: '端口映射 (-p 宿主机:容器端口)',
              hintText: '例如: 8080:80 或 5432:5432 (多个端口逗号隔开)',
              prefixIcon: Icon(Icons.lan_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 12),

          // 环境变量
          TextFormField(
            controller: _envController,
            decoration: const InputDecoration(
              labelText: '环境变量 (-e KEY=VALUE)',
              hintText: '例如: ENV=prod,PORT=80 (多个变量逗号隔开)',
              prefixIcon: Icon(Icons.tune_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 12),

          // 挂载目录
          TextFormField(
            controller: _volumesController,
            decoration: const InputDecoration(
              labelText: '数据卷挂载 (-v 宿主机目录:容器目录)',
              hintText: '例如: /data/db:/var/lib/data',
              prefixIcon: Icon(Icons.folder_open_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 10),

          // 选项：自动重启
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('异常自动重启 (--restart always)', style: TextStyle(fontSize: 13)),
            value: _restartAlways,
            onChanged: (v) => setState(() => _restartAlways = v),
          ),
          const SizedBox(height: 16),

          // 底部操作区
          Row(
            children: [
              TextButton.icon(
                onPressed: _syncFormToScript,
                icon: const Icon(Icons.code_rounded, size: 16),
                label: const Text('转为命令脚本', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _running ? null : _doRunForm,
                icon: _running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(_running ? '启动中...' : '立即启动容器'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScriptMode() {
    return Form(
      key: _scriptFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 快捷模板与动作
          Row(
            children: [
              const Text(
                'Shell & Docker 脚本',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _scriptController.text = _generateScriptFromForm();
                  });
                  showAppSuccess(context, '已从当前表单重新生成脚本');
                },
                icon: const Icon(Icons.sync_rounded, size: 14),
                label: const Text('从表单同步', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _scriptController.text = _buildDefaultScript(
                      image: _imageController.text.trim().isNotEmpty
                          ? _imageController.text.trim()
                          : (widget.initialImage.isNotEmpty
                              ? widget.initialImage
                              : 'registry.cn-hangzhou.aliyuncs.com/<你的命名空间>/qianchuan-backend:latest'),
                      name: _nameController.text.trim().isNotEmpty
                          ? _nameController.text.trim()
                          : 'qianchuan-backend',
                    );
                  });
                },
                icon: const Icon(Icons.restore_rounded, size: 14),
                label: const Text('恢复示例', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 快速插入常用参数小芯片
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickChip(
                  label: '+ mkdir -p data',
                  onTap: () => _insertScriptSnippet('mkdir -p data\n'),
                ),
                const SizedBox(width: 6),
                _buildQuickChip(
                  label: '+ -p 8080:80',
                  onTap: () => _insertScriptSnippet('  -p 8080:80 \\\n'),
                ),
                const SizedBox(width: 6),
                _buildQuickChip(
                  label: '+ -v "\$(pwd)/data:/app/data"',
                  onTap: () => _insertScriptSnippet('  -v "\$(pwd)/data:/app/data" \\\n'),
                ),
                const SizedBox(width: 6),
                _buildQuickChip(
                  label: '+ -e TZ=Asia/Shanghai',
                  onTap: () => _insertScriptSnippet('  -e TZ=Asia/Shanghai \\\n'),
                ),
                const SizedBox(width: 6),
                _buildQuickChip(
                  label: '+ --restart always',
                  onTap: () => _insertScriptSnippet('  --restart always \\\n'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 脚本输入框
          Container(
            decoration: BoxDecoration(
              color: AppColors.darkBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.darkBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: TextFormField(
              controller: _scriptController,
              maxLines: 12,
              minLines: 8,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '请输入 Shell 脚本与 docker run 命令...',
                hintStyle: TextStyle(
                  color: AppColors.textMuted,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? '命令脚本不能为空' : null,
            ),
          ),
          const SizedBox(height: 10),

          // 说明卡片
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryGlow.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: AppColors.primaryLight),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '支持按顺序执行多行 Shell 组合命令。若命令中包含 mkdir -p 创建目录，系统会先在主机当前目录下创建对应文件夹，随后无缝执行 docker run 完成挂载并启动容器。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 底部操作区
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  _scriptController.clear();
                },
                icon: const Icon(Icons.clear_all_rounded, size: 16),
                label: const Text('清空', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _running ? null : _doRunScript,
                icon: _running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(_running ? '执行中...' : '立即执行并启动'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: AppColors.primaryLight,
          ),
        ),
      ),
    );
  }

  Future<void> _doRunForm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _running = true);

    try {
      final ports = _portsController.text
          .split(RegExp(r'[,;\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final envs = _envController.text
          .split(RegExp(r'[,;\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final volumes = _volumesController.text
          .split(RegExp(r'[,;\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final containerId = await widget.ops.runContainer(
        image: _imageController.text.trim(),
        name: _nameController.text.trim(),
        portMappings: ports,
        envVars: envs,
        volumeMounts: volumes,
        restartAlways: _restartAlways,
      );

      if (!mounted) return;
      final shortId = containerId.length > 12 ? containerId.substring(0, 12) : containerId;
      showAppSuccess(context, '容器 ${_nameController.text} ($shortId) 已成功启动！');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _doRunScript() async {
    if (!_scriptFormKey.currentState!.validate()) return;
    setState(() => _running = true);

    try {
      final output = await widget.ops.runContainerScript(_scriptController.text);

      if (!mounted) return;

      // 提取输出中最后的容器 ID 或输出内容
      final lines = output
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final lastLine = lines.isNotEmpty ? lines.last : '';
      final shortId = lastLine.length > 12 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(lastLine)
          ? lastLine.substring(0, 12)
          : lastLine;

      final successMsg = shortId.isNotEmpty
          ? '命令已成功执行，容器启动完毕！(ID: $shortId)'
          : '命令已成功执行，容器已启动！';

      showAppSuccess(context, successMsg);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}

