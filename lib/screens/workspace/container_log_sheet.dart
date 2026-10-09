import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/remote_ops.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialogs.dart';

class ContainerLogSheet extends StatefulWidget {
  const ContainerLogSheet({
    super.key,
    required this.ops,
    required this.containerName,
  });

  final RemoteOps ops;
  final String containerName;

  static Future<void> show(
    BuildContext context, {
    required RemoteOps ops,
    required String containerName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF070B11),
      builder: (_) => ContainerLogSheet(
        ops: ops,
        containerName: containerName,
      ),
    );
  }

  @override
  State<ContainerLogSheet> createState() => _ContainerLogSheetState();
}

class _ContainerLogSheetState extends State<ContainerLogSheet> {
  final ScrollController _scrollController = ScrollController();
  int _tail = 200;
  String _logs = '';
  bool _loading = true;
  String _filter = '';
  Object? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await widget.ops.containerLogs(widget.containerName, tail: _tail);
      if (!mounted) return;
      setState(() {
        _logs = text;
        _loading = false;
      });
      // 自动滚屏到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF070B11),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 顶部控制栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.darkBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.terminal, color: AppColors.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '容器日志: ${widget.containerName}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 行数选择
                    DropdownButton<int>(
                      value: _tail,
                      underline: const SizedBox(),
                      dropdownColor: AppColors.darkSurface,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      items: const [
                        DropdownMenuItem(value: 100, child: Text('最近 100 行')),
                        DropdownMenuItem(value: 200, child: Text('最近 200 行')),
                        DropdownMenuItem(value: 500, child: Text('最近 500 行')),
                        DropdownMenuItem(value: 1000, child: Text('最近 1000 行')),
                      ],
                      onChanged: (v) {
                        if (v != null && v != _tail) {
                          setState(() => _tail = v);
                          _fetch();
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: '刷新日志',
                      onPressed: _loading ? null : _fetch,
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: '复制全部日志',
                      onPressed: _logs.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: _logs));
                              showAppSuccess(context, '已复制日志内容');
                            },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 搜索过滤
                SizedBox(
                  height: 36,
                  child: TextField(
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: '按关键字过滤日志...',
                      prefixIcon: const Icon(Icons.filter_list, size: 16),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      suffixIcon: _filter.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () => setState(() => _filter = ''),
                            )
                          : null,
                    ),
                    onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
                  ),
                ),
              ],
            ),
          ),

          // 日志终端输出内容
          Expanded(
            child: _buildLogView(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogView() {
    if (_loading && _logs.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_error != null && _logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 36),
            const SizedBox(height: 12),
            Text('读取日志失败：$_error', style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _fetch, child: const Text('重试')),
          ],
        ),
      );
    }

    final rawLines = _logs.split('\n');
    final lines = _filter.isEmpty
        ? rawLines
        : rawLines.where((l) => l.toLowerCase().contains(_filter)).toList();

    if (lines.isEmpty) {
      return const Center(
        child: Text('（无日志输出）', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      );
    }

    return Container(
      color: const Color(0xFF070B11),
      child: SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            final line = lines[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFE2E8F0),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
