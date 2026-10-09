import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/remote_ops.dart';
import '../../theme/app_theme.dart';

class DatabaseExplorerDialog extends StatefulWidget {
  const DatabaseExplorerDialog({
    super.key,
    required this.ops,
    required this.target,
  });

  final RemoteOps ops;
  final DatabaseTarget target;

  static Future<void> show(
    BuildContext context, {
    required RemoteOps ops,
    required DatabaseTarget target,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => DatabaseExplorerDialog(ops: ops, target: target),
    );
  }

  @override
  State<DatabaseExplorerDialog> createState() => _DatabaseExplorerDialogState();
}

class _DatabaseExplorerDialogState extends State<DatabaseExplorerDialog> {
  late TextEditingController _userController;
  late TextEditingController _passwordController;
  late TextEditingController _sqlController;
  late TextEditingController _tableSearchController;
  final ScrollController _hScrollController = ScrollController();
  final ScrollController _vScrollController = ScrollController();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _showPassword = false;
  bool _connecting = false;
  bool _executing = false;

  List<String> _databases = [];
  String _selectedDatabase = '';

  List<String> _tables = [];
  String _selectedTable = '';
  String _tableSearch = '';

  DatabaseQueryResult? _queryResult;
  String? _connectError;

  @override
  void initState() {
    super.initState();
    _userController = TextEditingController(text: widget.target.defaultUser);
    _passwordController = TextEditingController();
    _sqlController = TextEditingController();
    _tableSearchController = TextEditingController();
    _selectedDatabase = widget.target.defaultDatabase;

    _loadDatabases();
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    _sqlController.dispose();
    _tableSearchController.dispose();
    _hScrollController.dispose();
    _vScrollController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDatabases() async {
    setState(() {
      _connecting = true;
      _connectError = null;
    });

    try {
      final list = await widget.ops.listDatabases(
        widget.target,
        user: _userController.text.trim(),
        password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
      );

      if (!mounted) return;
      setState(() {
        _databases = list;
        if (!_databases.contains(_selectedDatabase) || _selectedDatabase.isEmpty) {
          // 优先选中非系统库
          final nonSystem = list
              .where((db) => !const {'information_schema', 'performance_schema', 'sys'}
                  .contains(db))
              .toList();
          _selectedDatabase = nonSystem.isNotEmpty
              ? nonSystem.first
              : (list.isNotEmpty ? list.first : '');
        }
        _connecting = false;
      });

      if (_selectedDatabase.isNotEmpty) {
        _loadTables();
      }
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() {
        _connecting = false;
        _connectError = errMsg;
      });
      if (errMsg.contains('Access denied') ||
          errMsg.contains('password') ||
          errMsg.contains('using password')) {
        Future.microtask(() {
          if (mounted) _passwordFocusNode.requestFocus();
        });
      }
    }
  }

  Future<void> _loadTables() async {
    if (_selectedDatabase.isEmpty) return;
    try {
      final list = await widget.ops.listTables(
        widget.target,
        database: _selectedDatabase,
        user: _userController.text.trim(),
        password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
      );
      if (!mounted) return;
      setState(() {
        _tables = list;
      });

      // 如果有表，默认预览第一个表的数据
      if (list.isNotEmpty && _selectedTable.isEmpty) {
        _selectTable(list.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectError = '获取数据表失败: $e';
      });
    }
  }

  void _selectTable(String table) {
    setState(() {
      _selectedTable = table;
    });
    final sql = widget.target.isPostgres
        ? 'SELECT * FROM "$table" LIMIT 50;'
        : 'SELECT * FROM `$table` LIMIT 50;';
    _sqlController.text = sql;
    _runQuery(sql);
  }

  Future<void> _runQuery([String? customSql]) async {
    final sql = (customSql ?? _sqlController.text).trim();
    if (sql.isEmpty) return;

    setState(() {
      _executing = true;
    });

    try {
      final result = await widget.ops.queryDatabase(
        widget.target,
        database: _selectedDatabase,
        sql: sql,
        user: _userController.text.trim(),
        password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
      );
      if (!mounted) return;
      setState(() {
        _queryResult = result;
        _executing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _queryResult = DatabaseQueryResult.error(e.toString());
        _executing = false;
      });
    }
  }

  void _copyResultsAsCsv() {
    final res = _queryResult;
    if (res == null || !res.isTabular) return;

    final buffer = StringBuffer();
    buffer.writeln(res.columns.join(','));
    for (final row in res.rows) {
      buffer.writeln(row.map((cell) => '"${cell.replaceAll('"', '""')}"').join(','));
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制 CSV 数据到剪贴板'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredTables = _tables.where((t) {
      if (_tableSearch.isEmpty) return true;
      return t.toLowerCase().contains(_tableSearch.toLowerCase());
    }).toList();

    return Dialog(
      backgroundColor: AppColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 720),
        child: Column(
          children: [
            // 1. 顶部标题栏与连接配置
            _buildTopBar(),
            const Divider(height: 1, color: AppColors.darkBorder),

            // 2. 主体区（左侧数据表树 + 右侧数据浏览与 SQL 控制台）
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左侧导航栏 (表列表)
                  _buildSidebar(filteredTables),
                  const VerticalDivider(width: 1, color: AppColors.darkBorder),
                  // 右侧主视图 (SQL 控制台 + 数据展示)
                  Expanded(child: _buildMainView()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.storage_rounded, color: AppColors.primaryLight, size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${widget.target.type.toUpperCase()} 数据库管理',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.darkCard,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.darkBorder),
                        ),
                        child: Text(
                          widget.target.kind == DatabaseTargetKind.container
                              ? '容器: ${widget.target.label}'
                              : '服务: ${widget.target.label}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '直连远程数据库实例，支持实时查询与数据网格查看',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 连接凭据与 Database 选择栏
          Row(
            children: [
              // 用户名
              Container(
                width: 130,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: TextField(
                  controller: _userController,
                  style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '用户名',
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 密码
              Container(
                width: 180,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _connectError != null ? AppColors.warning : AppColors.darkBorder,
                  ),
                ),
                padding: const EdgeInsets.only(left: 10, right: 6),
                alignment: Alignment.center,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        obscureText: !_showPassword,
                        style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: AppColors.textPrimary),
                        onSubmitted: (_) => _loadDatabases(),
                        decoration: const InputDecoration(
                          hintText: '输入数据库密码',
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => setState(() => _showPassword = !_showPassword),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _showPassword ? Icons.visibility_off : Icons.visibility,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 数据库下拉框
              const Text('Database:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
              const SizedBox(width: 6),
              if (_databases.isEmpty && _connecting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  alignment: Alignment.center,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _databases.contains(_selectedDatabase) ? _selectedDatabase : null,
                      hint: const Text('选择库', style: TextStyle(fontSize: 12)),
                      dropdownColor: AppColors.darkCard,
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: 'monospace'),
                      items: _databases.map((db) {
                        return DropdownMenuItem(
                          value: db,
                          child: Text(db),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedDatabase = val;
                            _selectedTable = '';
                            _tables = [];
                            _queryResult = null;
                          });
                          _loadTables();
                        }
                      },
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: _connecting ? null : _loadDatabases,
                icon: _connecting
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8))
                    : const Icon(Icons.refresh, size: 14),
                label: const Text('刷新/连接', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),

          if (_connectError != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline, size: 14, color: AppColors.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _connectError!,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.error),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (_connectError!.contains('Access denied') || _connectError!.contains('using password')) ...[
                    const SizedBox(height: 4),
                    const Text(
                      '提示：MySQL 默认通常需要密码，请在上方输入连接密码后点击「刷新/连接」。',
                      style: TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSidebar(List<String> tables) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _tableSearchController,
                decoration: InputDecoration(
                  hintText: '按数据表搜索...',
                  prefixIcon: const Icon(Icons.search, size: 15),
                  contentPadding: EdgeInsets.zero,
                  suffixIcon: _tableSearch.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: () {
                            _tableSearchController.clear();
                            setState(() => _tableSearch = '');
                          },
                        )
                      : null,
                ),
                style: const TextStyle(fontSize: 12),
                onChanged: (v) => setState(() => _tableSearch = v.trim()),
              ),
            ),
          ),

          // 表头计数
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.table_view_outlined, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  '数据表 (${tables.length})',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                const Spacer(),
                InkWell(
                  onTap: _loadTables,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.refresh, size: 14, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 8, color: AppColors.darkBorder),

          // 列表
          Expanded(
            child: tables.isEmpty
                ? Center(
                    child: Text(
                      _tableSearch.isNotEmpty ? '无匹配表' : '暂无数据表',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: tables.length,
                    itemBuilder: (context, index) {
                      final table = tables[index];
                      final isSelected = table == _selectedTable;

                      return InkWell(
                        onTap: () => _selectTable(table),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : null,
                            border: Border(
                              left: BorderSide(
                                color: isSelected ? AppColors.primary : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.table_chart_outlined,
                                size: 14,
                                color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  table,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? AppColors.primaryLight : AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // SQL 控制台
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: AppColors.darkSurface,
            border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 快捷查询芯片
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (_selectedTable.isNotEmpty) ...[
                    _QuickQueryChip(
                      label: '前 50 条数据',
                      onTap: () => _selectTable(_selectedTable),
                    ),
                    _QuickQueryChip(
                      label: '总行数 COUNT(*)',
                      onTap: () {
                        final sql = widget.target.isPostgres
                            ? 'SELECT COUNT(*) AS total FROM "$_selectedTable";'
                            : 'SELECT COUNT(*) AS total FROM `$_selectedTable`;';
                        _sqlController.text = sql;
                        _runQuery(sql);
                      },
                    ),
                    _QuickQueryChip(
                      label: '表结构 Schema',
                      onTap: () {
                        final sql = widget.target.isPostgres
                            ? "SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name = '$_selectedTable';"
                            : "DESCRIBE `$_selectedTable`;";
                        _sqlController.text = sql;
                        _runQuery(sql);
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // 输入框与执行按钮
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sqlController,
                      maxLines: 2,
                      minLines: 1,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: '输入 SQL 查询语句并执行 (例如: SELECT * FROM users LIMIT 10;)...',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _executing ? null : () => _runQuery(),
                    icon: _executing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow_rounded, size: 16),
                    label: Text(_executing ? '执行中' : '执行'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 数据结果面板
        Expanded(child: _buildDataResultView()),
      ],
    );
  }

  Widget _buildDataResultView() {
    if (_executing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 12),
            Text('正在远程执行 SQL 查询...', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      );
    }

    final res = _queryResult;
    if (res == null) {
      return const Center(
        child: Text('在左侧选择数据表，或在上方输入 SQL 执行查询', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      );
    }

    // 错误状态
    if (res.hasError) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: AppColors.error),
                  SizedBox(width: 6),
                  Text('SQL 执行出错', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.error, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                res.error!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.error),
              ),
            ],
          ),
        ),
      );
    }

    // 非结果集返回（如 INSERT / UPDATE / DDL）
    if (!res.isTabular) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 36, color: AppColors.success),
              const SizedBox(height: 10),
              Text(
                res.statusMessage ?? '执行完成',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text('耗时: ${res.executionDurationMs}ms', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ),
      );
    }

    // 结构化表格数据
    return Column(
      children: [
        // 结果状态栏与导出按钮
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          color: AppColors.darkSurface.withValues(alpha: 0.4),
          child: Row(
            children: [
              Text(
                '共 ${res.rowCount} 条记录 · 耗时 ${res.executionDurationMs}ms',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 13),
                label: const Text('复制为 CSV', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _copyResultsAsCsv,
              ),
            ],
          ),
        ),

        // 表格数据视图（双向滚动）
        Expanded(
          child: res.rows.isEmpty
              ? const Center(
                  child: Text('数据集为空 (0 行)', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                )
              : Scrollbar(
                  controller: _hScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _hScrollController,
                    scrollDirection: Axis.horizontal,
                    child: Scrollbar(
                      controller: _vScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _vScrollController,
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                        headingRowColor: WidgetStateProperty.all(AppColors.darkSurface),
                        dataRowMinHeight: 32,
                        dataRowMaxHeight: 38,
                        headingRowHeight: 36,
                        columnSpacing: 18,
                        horizontalMargin: 12,
                        columns: [
                          const DataColumn(
                            label: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                          ),
                          ...res.columns.map((c) => DataColumn(
                                label: Text(
                                  c,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryLight,
                                  ),
                                ),
                              )),
                        ],
                        rows: List.generate(res.rows.length, (idx) {
                          final row = res.rows[idx];
                          final isEven = idx % 2 == 0;
                          return DataRow(
                            color: WidgetStateProperty.all(
                              isEven ? AppColors.darkCard : AppColors.darkSurface.withValues(alpha: 0.3),
                            ),
                            cells: [
                              DataCell(
                                Text(
                                  '${idx + 1}',
                                  style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                ),
                              ),
                              ...row.map((cell) => DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 320),
                                      child: Tooltip(
                                        message: cell,
                                        waitDuration: const Duration(milliseconds: 600),
                                        child: Text(
                                          cell,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11.5,
                                            color: AppColors.textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  )),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
        ),
      ],
    );
  }
}

class _QuickQueryChip extends StatelessWidget {
  const _QuickQueryChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      backgroundColor: AppColors.darkCard,
      side: const BorderSide(color: AppColors.darkBorder),
    );
  }
}
