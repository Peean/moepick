// ignore_for_file: use_build_context_synchronously
//
// `contextIsAlive` (shared/widgets/common.dart) is the Flutter 3.0 stand-in for
// `BuildContext.mounted`; the analyzer cannot follow the indirection, so this
// file opts out of the lint for those guarded uses.
//
// `contextIsAlive`（shared/widgets/common.dart）是 `BuildContext.mounted` 在
// Flutter 3.0 下的等价替代；分析器无法跟随这层间接，因此本文件对这些守卫用法
// 关闭该 lint。

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/platform/file_save_service.dart';
import '../../../core/utils/date_utils.dart' as moe;
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';

/// View, copy, clear and export the on-disk log.
/// 查看、复制、清空与导出磁盘日志。
///
/// The log is the primary diagnostic surface: crashes and errors are written
/// here automatically, and this page is how a user gets the file off the device
/// to attach to a bug report.
///
/// 日志是主要的诊断途径：崩溃与错误会自动写入这里，
/// 本页让用户能把文件从设备导出，附到问题报告里。
class LogPage extends StatefulWidget {
  const LogPage({Key? key}) : super(key: key);

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  String _content = '';
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final String content = await AppLog.readAll();
    if (!mounted) return;
    setState(() {
      _content = content;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return MoeScaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RoutePaths.settings),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_outlined),
            onPressed: _content.isEmpty ? null : _copyAll,
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            icon: const Icon(Icons.more_vert),
            onSelected: (String value) {
              if (value == 'export') _export();
              if (value == 'clear') _clear();
            },
            itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('导出日志'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('清空日志'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_content.isEmpty)
            const EmptyState(
              icon: Icons.article_outlined,
              title: '还没有日志',
              message: '应用运行中产生的错误与关键事件会记录在这里。',
            )
          else
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _content,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          if (_busy)
            ColoredBox(
              color: Colors.black.withOpacity(0.25),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _content));
    if (contextIsAlive(context)) {
      showToast(context, '已复制全部日志');
    }
  }

  Future<void> _clear() async {
    final bool ok = await confirm(
      context,
      title: '清空日志',
      message: '将删除全部日志文件，此操作无法撤销。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!ok) return;
    await AppLog.clear();
    if (mounted) {
      showToast(context, '日志已清空');
      await _reload();
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final String stamp = moe.DateUtils.fileStamp(moe.DateUtils.nowUtc());
      final SaveDestination? destination =
          await FileSaveService.chooseSaveDestination(
        suggestedName: 'moepick_log_$stamp.txt',
        extensionLabel: 'txt',
      );
      if (destination == null) return;

      final SaveOutcome outcome = await FileSaveService.writeBytes(
        destination,
        Uint8List.fromList(_content.codeUnits),
      );
      if (mounted) {
        showToast(
          context,
          outcome.usedFallback
              ? '所选位置不可写，已改存到：${outcome.path}'
              : '日志已导出',
          isError: outcome.usedFallback,
        );
      }
    } catch (e) {
      if (mounted) showToast(context, '导出失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
