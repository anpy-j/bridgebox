import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/remote_ops.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';
import 'pull_image_dialog.dart';
import 'registry_dialog.dart';
import 'run_container_dialog.dart';

class ImagesTab extends StatefulWidget {
  const ImagesTab({super.key, required this.ops});
  final RemoteOps ops;

  @override
  State<ImagesTab> createState() => _ImagesTabState();
}

class _ImagesTabState extends State<ImagesTab> {
  late Future<List<DockerImageInfo>> _future;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _future = widget.ops.listImages();
  }

  void _reload() {
    setState(() {
      _future = widget.ops.listImages();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DockerImageInfo>>(
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
                  Text('获取镜像列表失败：${snapshot.error}', style: const TextStyle(color: AppColors.textSecondary)),
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

        final allImages = snapshot.data ?? [];
        final filtered = allImages.where((img) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return img.repository.toLowerCase().contains(q) ||
              img.tag.toLowerCase().contains(q) ||
              img.registry.toLowerCase().contains(q);
        }).toList();

        final danglingCount = allImages.where((i) => i.isDangling).length;

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 顶部精简工具条：搜索 + 拉取新镜像弹窗按钮 + 私有仓库入口 + 清理悬空 + 刷新
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: '按仓库名、Tag 或 Registry 搜索...',
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
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('拉取新镜像'),
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () async {
                      final ok = await PullImageDialog.show(context, ops: widget.ops);
                      if (ok == true) _reload();
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.settings_outlined, size: 15),
                    label: const Text('管理私有仓库'),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => RegistryManagerSheet.show(context, ops: widget.ops),
                  ),
                  if (danglingCount > 0) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.cleaning_services_outlined, size: 15, color: AppColors.warning),
                      label: Text('清理悬空 ($danglingCount)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _cleanDangling,
                    ),
                  ],
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: '刷新镜像',
                    onPressed: _reload,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (!snapshot.hasData)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              else if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _searchQuery.isNotEmpty ? '未找到匹配的镜像' : '当前主机暂无 Docker 镜像',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...filtered.map((img) => _ImageCard(
                      image: img,
                      onRun: () => RunContainerDialog.show(
                        context,
                        ops: widget.ops,
                        image: img.ref,
                      ),
                      onDelete: () => _remove(img),
                    )),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cleanDangling() async {
    final ok = await confirmAction(
      context,
      title: '清理悬空镜像',
      body: '将执行 docker image prune -f，删除所有未被容器使用的无标签 (<none>:<none>) 镜像。确认继续？',
      confirmText: '清理释放空间',
      isDanger: false,
    );
    if (!ok || !mounted) return;
    try {
      final res = await widget.ops.cleanDanglingImages();
      if (!mounted) return;
      showAppSuccess(context, '已清理悬空镜像：$res');
      _reload();
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  Future<void> _remove(DockerImageInfo image) async {
    final ok = await confirmAction(
      context,
      title: '删除镜像确认',
      body: '确定删除镜像 ${image.ref} (${image.shortId})？\n大小：${image.size}\n请确保没有容器正在依赖该镜像。',
      confirmText: '确认删除',
      isDanger: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.ops.removeImage(image.ref);
      if (!mounted) return;
      showAppSuccess(context, '已删除镜像 ${image.ref}');
      _reload();
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.image,
    required this.onRun,
    required this.onDelete,
  });

  final DockerImageInfo image;
  final VoidCallback onRun;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDangling = image.isDangling;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDangling
              ? AppColors.warning.withValues(alpha: 0.4)
              : AppColors.darkBorder,
        ),
      ),
      child: Row(
        children: [
          // 左侧图标
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Icon(
              isDangling ? Icons.broken_image_outlined : Icons.layers_rounded,
              size: 18,
              color: isDangling ? AppColors.warning : AppColors.primaryLight,
            ),
          ),
          const SizedBox(width: 12),

          // 核心信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 明确突出的 Registry 仓库地址徽章 (关键需求)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDangling
                            ? AppColors.warning.withValues(alpha: 0.15)
                            : AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDangling
                              ? AppColors.warning.withValues(alpha: 0.4)
                              : AppColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_queue,
                            size: 11,
                            color: isDangling ? AppColors.warning : AppColors.primaryLight,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            image.registry,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: isDangling ? AppColors.warning : AppColors.primaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Tag 标签
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Text(
                        image.tag,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 镜像仓库名
                Text(
                  image.repositoryName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // 尺寸与 Short ID
                Row(
                  children: [
                    Text(
                      '大小: ${image.size}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'ID: ${image.shortId}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 核心操作：启动/运行为容器
          FilledButton.tonalIcon(
            onPressed: isDangling ? null : onRun,
            icon: const Icon(Icons.rocket_launch_rounded, size: 14),
            label: const Text('运行'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
          const SizedBox(width: 4),

          // 复制引用与删除按钮
          IconButton(
            icon: const Icon(Icons.copy, size: 16, color: AppColors.textSecondary),
            tooltip: '复制完整镜像引用',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: image.ref));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制镜像引用'), duration: Duration(seconds: 1)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
            tooltip: '删除镜像',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
