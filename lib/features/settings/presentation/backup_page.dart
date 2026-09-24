import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/file_save_service.dart';
import '../../../core/state/data_version.dart';
import '../../../core/storage/hive_store.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../library/application/library_providers.dart';
import '../../backup/application/backup_service.dart';
import '../application/storage_providers.dart';

/// Backup and restore.
/// 备份与恢复。
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({Key? key}) : super(key: key);

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String _busyLabel = '';

  @override
  Widget build(BuildContext context) {
    final Map<String, int> stats = ref.watch(libraryStatsProvider);

    return MoeScaffold(
      appBar: AppBar(
        title: const Text('备份与恢复'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RoutePaths.settings),
        ),
      ),
      body: Stack(
        children: <Widget>[
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: <Widget>[
              _LibrarySummary(stats: stats),

              const SectionHeader(
                '导出备份',
                subtitle: '备份文件可以在新设备上恢复，也可以当作一份快照留存',
              ),
              _ActionCard(
                icon: Icons.inventory_2_outlined,
                title: '完整备份',
                description: '包含全部系列、表情包、图片文件、分类、标签和设置。'
                    '换设备或重装后用它恢复最完整。',
                highlight: true,
                enabled: !_busy,
                trailingLabel: _sizeHint(stats, includeImages: true),
                onTap: () => _export(BackupScope.full),
              ),
              const SizedBox(height: 10),
              _ActionCard(
                icon: Icons.tune_outlined,
                title: '仅备份设置',
                description: '只导出设置、分类、标签和记录，不含图片文件，体积很小。',
                enabled: !_busy,
                trailingLabel: _sizeHint(stats, includeImages: false),
                onTap: () => _export(BackupScope.settingsOnly),
              ),

              const SectionHeader(
                '从备份恢复',
                subtitle: '恢复会替换当前的全部数据，建议先导出一份当前备份',
              ),
              _ActionCard(
                icon: Icons.settings_backup_restore,
                title: '选择备份文件恢复',
                description: '从本地选择一个 .zip 备份文件，恢复其中的全部内容。',
                destructive: true,
                enabled: !_busy,
                onTap: _restore,
              ),

              const SizedBox(height: 24),
              const _Note(
                text: '备份是普通的 zip 压缩包，内含 manifest.json 与图片文件，'
                    '不依赖任何云端服务。\n'
                    '导出时会弹出系统文件管理器，你可以选择保存到任意文件夹；'
                    '若该文件夹不允许写入，备份会自动改存到应用专属目录并提示实际路径。',
              ),
            ],
          ),
          if (_busy)
            ColoredBox(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 22,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_busyLabel),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Rough size hint so the user can pick a scope knowingly.
  /// 粗略的体积提示，使用户能有依据地选择范围。
  static String _sizeHint(Map<String, int> stats, {required bool includeImages}) {
    final int stickers = stats['stickers'] ?? 0;
    if (!includeImages) return '约 ${(stickers * 0.4 / 1024).toStringAsFixed(1)} KB';
    // Assume ~120 KB per sticker, which is typical for a meme-sized JPEG/PNG.
    // 按每张表情包约 120 KB 估算，这是迷因尺寸 JPEG/PNG 的典型值。
    return '约 ${(stickers * 120 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _export(BackupScope scope) async {
    // Ask first, then show the spinner: the platform dialog is the user's
    // choice, and covering it with a modal overlay would be hostile.
    // 先询问再显示进度：平台对话框属于用户的选择，
    // 用模态遮罩盖住它是不友好的。
    final SaveDestination? target =
        await FileSaveService.chooseSaveDestination(
      suggestedName: BackupService.suggestedFileName(scope),
    );
    if (target == null || !mounted) return;

    setState(() {
      _busy = true;
      _busyLabel = '正在打包…';
    });

    try {
      final HiveStore store = ref.read(hiveStoreProvider);
      final BackupService service = BackupService(store);
      final BackupResult result = await service.writeTo(target, scope: scope);

      if (!mounted) return;

      // Report where the file actually landed: when the chosen folder was not
      // writable the archive goes to app storage instead, and the user has to
      // be told rather than left to discover an empty folder.
      // 如实报告文件最终落点：当所选文件夹不可写时，归档会改放应用存储，
      // 必须告知用户，而不是让他对着空文件夹发懵。
      final String size = _formatBytes(result.bytes);
      if (result.usedFallback) {
        showToast(
          context,
          '所选位置不可写，已改存到：${result.path}（$size）',
        );
      } else {
        showToast(
          context,
          '已导出到 ${result.path.split(Platform.pathSeparator).last}（$size）',
        );
      }
    } catch (e) {
      if (mounted) showToast(context, '导出失败：$e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = '';
        });
      }
    }
  }

  Future<void> _restore() async {
    final bool ok = await confirm(
      context,
      title: '确认恢复',
      message: '恢复会**替换**当前的全部系列、表情包与设置。\n'
          '如果当前数据重要，请先导出一份备份。',
      confirmLabel: '继续',
      destructive: true,
    );
    if (!ok) return;

    final String? source = await FileSaveService.chooseOpenPath();
    if (source == null) return;

    setState(() {
      _busy = true;
      _busyLabel = '正在恢复…';
    });

    try {
      final HiveStore store = ref.read(hiveStoreProvider);
      final RestoreResult result =
          await BackupService(store).restoreFrom(source);

      // Every provider watches this, so one bump refreshes the whole UI after
      // the store was rewritten underneath it.
      // 所有 provider 都监听它，因此在底层存储被重写后，
      // 一次自增即可刷新整个界面。
      ref.read(dataVersionProvider.notifier).bump();

      if (!mounted) return;
      final String message = result.skippedAssets > 0
          ? '${result.summary}；${result.skippedAssets} 张图片文件未包含在备份中'
          : result.summary;
      showToast(context, message);
    } catch (e) {
      if (mounted) showToast(context, '恢复失败：$e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = '';
        });
      }
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// What is about to be backed up.
/// 即将被备份的内容概览。
class _LibrarySummary extends StatelessWidget {
  const _LibrarySummary({required this.stats});

  final Map<String, int> stats;

  @override
  Widget build(BuildContext context) {
    return MoeCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Row(
        children: <Widget>[
          _Cell(label: '系列', value: stats['series'] ?? 0),
          _Cell(label: '表情包', value: stats['stickers'] ?? 0),
          _Cell(label: '分类', value: stats['categories'] ?? 0),
          _Cell(label: '标签', value: stats['tags'] ?? 0),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable action card with an explanation of what it does.
/// 可点击的操作卡片，附带功能说明。
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onTap,
    this.highlight = false,
    this.destructive = false,
    this.trailingLabel,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool enabled;
  final VoidCallback onTap;
  final bool highlight;
  final bool destructive;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: MoeCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        onTap: enabled ? onTap : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withOpacity(highlight ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (trailingLabel != null)
                        Text(
                          trailingLabel!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.65),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurface.withOpacity(0.35),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explanatory footnote.
/// 说明性脚注。
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.info_outline,
          size: 15,
          color: theme.colorScheme.onSurface.withOpacity(0.45),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.55),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
