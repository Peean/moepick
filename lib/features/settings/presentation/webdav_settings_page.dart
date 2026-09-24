import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state/data_version.dart';
import '../../../core/utils/date_utils.dart' as moe;
import '../../../core/storage/secure_store.dart';
import '../../../data/models/app_settings.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../sync/application/sync_providers.dart';
import '../../sync/application/webdav_sync_service.dart';
import '../application/storage_providers.dart';

/// WebDAV connection and sync controls.
/// WebDAV 连接与同步控制。
class WebDavSettingsPage extends ConsumerStatefulWidget {
  const WebDavSettingsPage({Key? key}) : super(key: key);

  @override
  ConsumerState<WebDavSettingsPage> createState() =>
      _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends ConsumerState<WebDavSettingsPage> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _remoteRootController = TextEditingController();

  bool _initialised = false;
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remoteRootController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<WebDavCredentials> credentialsAsync =
        ref.watch(webDavCredentialsProvider);
    final SyncStatus status = ref.watch(syncControllerProvider);
    final SyncMeta meta = ref.watch(syncMetaProvider);
    final bool degraded = ref.watch(secureStoreDegradedProvider);

    // Seed the form once, from whatever was stored when the page opened.
    // 仅在首次进入时用已存储的值填充表单。
    credentialsAsync.whenData((WebDavCredentials c) {
      if (_initialised) return;
      _initialised = true;
      _baseUrlController.text = c.baseUrl;
      _usernameController.text = c.username;
      _passwordController.text = c.password;
      _remoteRootController.text = c.remoteRoot;
    });

    return MoeScaffold(
      appBar: AppBar(
        title: const Text('WebDAV 同步'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RoutePaths.settings),
        ),
        actions: <Widget>[
          if (credentialsAsync.value?.isConfigured ?? false)
            PopupMenuButton<String>(
              tooltip: '更多操作',
              icon: const Icon(Icons.more_vert),
              onSelected: (String value) {
                if (value == 'clear') _clearConfig();
              },
              itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'clear',
                  child: DestructiveMenuItem(
                    icon: Icons.delete_outline,
                    label: '清除已保存配置',
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: <Widget>[
              if (degraded) const _DegradedWarning(),

              const SectionHeader(
                '服务器',
                subtitle: '支持坚果云、Nextcloud、群晖等标准 WebDAV 服务',
              ),
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://dav.jianguoyun.com/dav/',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  hintText: '坚果云为注册邮箱',
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '密码 / 应用密码',
                  hintText: '坚果云需生成应用密码，非登录密码',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _remoteRootController,
                decoration: const InputDecoration(
                  labelText: '远端文件夹',
                  hintText: 'moepick',
                ),
                autocorrect: false,
              ),

              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _testConnection,
                      child: const Text('测试连接'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),

              if (credentialsAsync.value?.isConfigured ?? false) ...<Widget>[
                const SectionHeader(
                  '自动同步',
                  subtitle: '本地数据变化后自动上传；'
                      '启动时以及每 15 分钟还会兜底检查一次',
                ),
                _SwitchCard(
                  label: '启用自动同步',
                  description: meta.autoSyncEnabled
                      ? '改动会在几秒后自动上传'
                      : '关闭时只在你手动点击时同步',
                  value: meta.autoSyncEnabled,
                  onChanged: (bool value) => _setAutoSync(value),
                ),
                const SizedBox(height: 12),
                _SyncActionCard(
                  status: status,
                  lastSyncAt: meta.lastSyncAt,
                  busy: _busy,
                  onSync: _syncNow,
                ),

                const SectionHeader(
                  '手动备份',
                  subtitle: '把当前库完整备份上传到服务器，或从服务器拉取备份恢复',
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _uploadBackup,
                        icon: const Icon(Icons.upload_outlined),
                        label: const Text('上传备份'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pullBackup,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('拉取备份'),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),
              const _Note(
                text: '同步使用整库快照：每次上传一份完整的压缩包，'
                    '并附带一个记录指纹的小文件用于判断是否需要同步。\n'
                    '当两台设备都有改动时，会优先采用服务器上的版本，'
                    '并在完成后告知你。\n'
                    '密码保存在系统的安全存储中（Android Keystore / Windows DPAPI）。',
              ),
            ],
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

  WebDavCredentials _collect() => WebDavCredentials(
        baseUrl: _baseUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        remoteRoot: _remoteRootController.text.trim().isEmpty
            ? 'moepick'
            : _remoteRootController.text.trim(),
      );

  /// Remove the stored credentials and blank the form.
  /// 清除已保存的凭据并清空表单。
  ///
  /// WHY THIS EXISTS / 为什么需要它
  ///
  /// The form is seeded once from whatever was previously saved, so a stale
  /// password keeps overriding what the user thinks they typed — the most
  /// common cause of "I entered the right password but it still fails". A
  /// one-tap reset removes that trap.
  ///
  /// 表单会用之前保存的旧值填充一次，于是陈旧的密码会持续覆盖用户以为自己
  /// 输入的内容——这正是「明明输入了正确密码却仍然失败」的最常见原因。
  /// 一键清除可移除这个陷阱。
  Future<void> _clearConfig() async {
    final bool ok = await confirm(
      context,
      title: '清除已保存配置',
      message: '将删除已保存的服务器地址、用户名和密码，\n'
          '之后需要重新填写并测试连接。',
      confirmLabel: '清除',
      destructive: true,
    );
    if (!ok) return;

    await ref.read(secureStoreProvider).clear();
    ref.invalidate(webDavCredentialsProvider);
    _baseUrlController.clear();
    _usernameController.clear();
    _passwordController.clear();
    _remoteRootController.clear();
    if (mounted) showToast(context, '已清除配置');
  }

  Future<void> _save() async {
    final WebDavCredentials credentials = _collect();
    if (!credentials.isConfigured) {
      showToast(context, '请填写服务器地址和用户名', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(secureStoreProvider).write(credentials);
      // Invalidate so the rest of the app re-reads the new credentials.
      // 使其失效，让应用其他部分重新读取新凭据。
      ref.invalidate(webDavCredentialsProvider);
      if (mounted) showToast(context, '已保存');
    } catch (e) {
      if (mounted) showToast(context, '保存失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testConnection() async {
    final WebDavCredentials credentials = _collect();
    if (!credentials.isConfigured) {
      showToast(context, '请先填写服务器地址和用户名', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final SyncReport report =
          await ref.read(syncControllerProvider.notifier).testConnection(
                credentials,
              );
      if (mounted) {
        showToast(context, report.message, isError: report.isError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      final SyncReport report =
          await ref.read(syncControllerProvider.notifier).syncNow();

      // A pull replaces the library underneath us, so refresh every derived
      // provider; this is the same signal a local edit would raise.
      // 拉取会替换底层库，因此需刷新全部派生 provider；
      // 这与本地编辑发出的信号相同。
      if (report.outcome == SyncOutcome.pulled ||
          report.outcome == SyncOutcome.conflictResolvedRemote) {
        ref.read(dataVersionProvider.notifier).bump();
      }

      if (mounted) {
        showToast(context, report.message, isError: report.isError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Force-upload the current library as a backup, overwriting the server copy.
  /// 强制把当前库上传为备份，覆盖服务器副本。
  Future<void> _uploadBackup() async {
    final WebDavCredentials credentials = _collect();
    if (!credentials.isConfigured) {
      showToast(context, '请先填写服务器地址和用户名', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final SyncReport report = await ref
          .read(syncControllerProvider.notifier)
          .uploadBackup(credentials);
      if (mounted) {
        showToast(context, report.message, isError: report.isError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Force-download the server backup and replace the local library with it.
  /// 强制从服务器下载备份并替换本地库。
  ///
  /// This overwrites local data, so it must be confirmed first.
  /// 这会覆盖本地数据，因此必须先确认。
  Future<void> _pullBackup() async {
    final WebDavCredentials credentials = _collect();
    if (!credentials.isConfigured) {
      showToast(context, '请先填写服务器地址和用户名', isError: true);
      return;
    }

    final bool ok = await confirm(
      context,
      title: '从服务器拉取备份',
      message: '将用服务器上的备份**替换**本地全部数据，'
          '本地尚未上传的改动会丢失。\n建议先执行一次「上传备份」留底。',
      confirmLabel: '拉取并覆盖',
      destructive: true,
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      final SyncReport report = await ref
          .read(syncControllerProvider.notifier)
          .pullBackup(credentials);

      // A pull replaced the library; refresh every derived provider.
      // 拉取替换了库；刷新全部派生 provider。
      if (report.outcome == SyncOutcome.pulled) {
        ref.read(dataVersionProvider.notifier).bump();
      }

      if (mounted) {
        showToast(context, report.message, isError: report.isError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAutoSync(bool value) async {
    await ref.read(syncMetaProvider.notifier).setAutoSync(value);
    if (!mounted) return;
    showToast(context, value ? '已启用自动同步' : '已关闭自动同步');
  }
}

/// Warning shown when credentials could not be stored securely.
/// 凭据无法安全存储时展示的警告。
class _DegradedWarning extends StatelessWidget {
  const _DegradedWarning();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.error.withOpacity(0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.warning_amber_outlined,
              size: 19,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '系统安全存储当前不可用，密码将以未加密的方式保存。\n'
                '如果你对这一点有顾虑，可以先不保存密码，每次同步时手动输入。',
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Manual sync card showing the last run's result.
/// 手动同步卡片，展示上次运行结果。
class _SyncActionCard extends StatelessWidget {
  const _SyncActionCard({
    required this.status,
    required this.lastSyncAt,
    required this.busy,
    required this.onSync,
  });

  final SyncStatus status;
  final DateTime? lastSyncAt;
  final bool busy;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool running = status.isRunning || busy;

    return MoeCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.cloud_sync_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '立即同步',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      lastSyncAt == null
                          ? '还没有同步过'
                          : '上次同步：${_relative(lastSyncAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: running ? null : onSync,
                child: Text(running ? '同步中' : '同步'),
              ),
            ],
          ),
          if (status.report != null) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  status.report!.isError
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  size: 15,
                  color: status.report!.isError
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    status.report!.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.report!.isError
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface.withOpacity(0.75),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Coarse "how long ago", which is all the user needs here.
  /// 粗略的「多久以前」，此处对用户而言足够了。
  static String _relative(DateTime utc) {
    final Duration diff = moe.DateUtils.nowUtc().difference(utc.toUtc());
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    final DateTime local = utc.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// A label plus a switch.
/// 标签加开关。
class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return MoeCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: theme.textTheme.bodyLarge),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
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
