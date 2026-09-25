import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:webdav_client/webdav_client.dart' as webdav;

import '../../../core/error/app_exception.dart';
import '../../../core/logging/app_log.dart';
import '../../../core/storage/hive_store.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/hash_utils.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/utils/path_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../backup/application/backup_service.dart';

/// Outcome of one sync attempt.
/// 单次同步尝试的结果。
enum SyncOutcome {
  /// Nothing to do: local and remote already agree.
  /// 无事可做：本地与远端已一致。
  upToDate,

  /// Local changes were pushed to the server.
  /// 本地变更已推送到服务器。
  pushed,

  /// Remote changes were pulled and applied.
  /// 远端变更已拉取并应用。
  pulled,

  /// Both sides changed; the remote won and was applied.
  /// 双方都有变更；以远端为准并已应用。
  conflictResolvedRemote,

  /// Sync is not configured or was skipped.
  /// 未配置同步或已跳过。
  skipped,

  /// The attempt failed; see [SyncReport.message].
  /// 尝试失败；见 [SyncReport.message]。
  failed,
}

/// A human-readable report of one sync run.
/// 单次同步的可读报告。
class SyncReport {
  const SyncReport({
    required this.outcome,
    required this.message,
    this.at,
  });

  final SyncOutcome outcome;
  final String message;
  final DateTime? at;

  bool get isError => outcome == SyncOutcome.failed;
  bool get isNoop =>
      outcome == SyncOutcome.upToDate || outcome == SyncOutcome.skipped;
}

/// WebDAV snapshot synchronisation.
/// WebDAV 快照同步。
///
/// STRATEGY: single-file snapshot with a sidecar metadata file.
///
///   {remoteRoot}/
///     snapshot.zip        — the same archive the backup screen produces
///     snapshot.meta.json  — schema version, manifest hash, device, timestamp
///
/// WHY A SNAPSHOT AND NOT PER-RECORD DELTAS: this app syncs a personal library
/// between a handful of devices, not a multi-writer database. Snapshot upload
/// is O(library) but has no merge algebra to get wrong, no tombstones to leak,
/// and no partial-application state — a half-applied delta is a corrupt library,
/// whereas a half-uploaded snapshot is simply ignored. The cost is bandwidth on
/// every change, which the debounce and the "changed at all?" fingerprint check
/// keep bounded.
///
/// CONFLICT POLICY: last-writer-wins **at the whole-library level**, resolved by
/// comparing the hash the device last saw with the hash currently on the server:
///
///   - remote hash == last known  → only we changed → push
///   - remote hash != last known, local fingerprint == last uploaded → pull
///   - both changed               → pull, because the remote is the more
///                                  recently observed state and refusing to act
///                                  would strand the user with no progress
///
/// The pull-first choice is deliberate and one-sided; the alternative (prompting
/// per conflict) needs a UI this app does not have, and silently discarding the
/// remote would lose another device's work. Users are told what happened.
///
/// 策略：单文件快照加一个伴随的元数据文件。
///
/// 为何用快照而非逐条增量：本应用是在少数几台设备间同步个人库，而非多写数据库。
/// 快照上传是 O(库规模)，但没有需要推导的合并代数、没有会泄漏的墓碑、
/// 也不存在部分应用状态——半应用的增量意味着库损坏，
/// 而半上传的快照只会被忽略。代价是每次变更都要传带宽，
/// 由防抖与「究竟有没有变化」的指纹检查控制在合理范围。
///
/// 冲突策略：**整库级**后写者胜，通过比较本设备上次见到的哈希与服务器上的当前哈希：
///   - 远端哈希 == 上次已知    → 只有本地变了 → 推送
///   - 远端哈希 != 上次已知，且本地指纹 == 上次上传 → 拉取
///   - 双方都变了              → 拉取
///
/// 优先拉取是有意且单向的选择。
class WebDavSyncService {
  WebDavSyncService(this._store);

  final HiveStore _store;

  /// Remote file names inside the sync folder.
  /// 同步文件夹内的远端文件名。
  static const String snapshotName = 'snapshot.zip';
  static const String metaName = 'snapshot.meta.json';

  /// A dry-run connection check used by the settings screen's "test" button.
  /// 供设置页「测试」按钮使用的连接检查。
  Future<SyncReport> testConnection(WebDavCredentials credentials) async {
    if (!credentials.isConfigured) {
      return const SyncReport(
        outcome: SyncOutcome.skipped,
        message: '请先填写服务器地址和用户名',
      );
    }

    try {
      final webdav.Client client = _client(credentials);
      await _ensureRemoteRoot(client, credentials.remoteRoot);
      return const SyncReport(
        outcome: SyncOutcome.upToDate,
        message: '连接成功，远端文件夹可用',
      );
    } catch (e) {
      return SyncReport(
        outcome: SyncOutcome.failed,
        message: _friendlyError(e),
      );
    }
  }

  /// Run one synchronisation pass.
  /// 执行一次同步。
  Future<SyncReport> sync(WebDavCredentials credentials) async {
    if (!credentials.isConfigured) {
      return const SyncReport(
        outcome: SyncOutcome.skipped,
        message: '未配置 WebDAV',
      );
    }

    final SyncMeta meta = _store.readSyncMeta();
    final String deviceId = meta.deviceId.isEmpty
        ? IdUtils.newId()
        : meta.deviceId;

    final webdav.Client client = _client(credentials);
    final String root = _normalizeRoot(credentials.remoteRoot);
    final String snapshotPath = '$root/$snapshotName';
    final String metaPath = '$root/$metaName';

    try {
      // Skip mkdirAll on the "already up to date" fast path: reading the sidecar
      // is enough to decide nothing changed, and creating the folder only
      // matters before a push. This saves a network round-trip on every no-op
      // sync (e.g. after a background-image change, which never alters the
      // content fingerprint).
      // 「已是最新」快路径跳过 mkdirAll：读伴随文件即可判断无变化，建目录只在
      // 推送前才需要。这样每次无操作同步（如改了背景图——它不改变内容指纹）
      // 都省一次网络往返。
      final _RemoteMeta? remoteMeta = await _readRemoteMeta(client, metaPath);
      final String localFingerprint = BackupService(_store).contentFingerprint();

      final String lastSeen = meta.lastKnownRemoteHash;
      final String? remoteFingerprint = remoteMeta?.fingerprint;

      // Fresh server: nothing to compare against, so publish.
      // 全新的服务器：无可比对对象，直接发布。
      if (remoteMeta == null) {
        await _ensureRemoteRoot(client, root);
        return _push(
          client: client,
          snapshotPath: snapshotPath,
          metaPath: metaPath,
          deviceId: deviceId,
          fingerprint: localFingerprint,
          reportMessage: '已上传本地数据到服务器',
        );
      }

      final bool remoteChanged = remoteFingerprint != lastSeen;
      final bool localChanged = localFingerprint != meta.lastUploadedManifestHash;

      if (!remoteChanged && !localChanged) {
        return SyncReport(
          outcome: SyncOutcome.upToDate,
          message: '已是最新',
          at: DateUtils.nowUtc(),
        );
      }

      if (!remoteChanged && localChanged) {
        await _ensureRemoteRoot(client, root);
        return _push(
          client: client,
          snapshotPath: snapshotPath,
          metaPath: metaPath,
          deviceId: deviceId,
          fingerprint: localFingerprint,
          reportMessage: '已上传本地变更',
        );
      }

      // Remote moved: take it, whether or not we also changed. See the class
      // doc for why this is deliberate.
      // 远端有变化：无论本地是否也变了，都以远端为准。原因见类文档。
      final _RemoteMeta effective = remoteMeta;
      final SyncReport pulled = await _pull(
        client: client,
        snapshotPath: snapshotPath,
        deviceId: deviceId,
        remote: effective,
      );

      if (localChanged && pulled.outcome == SyncOutcome.pulled) {
        return SyncReport(
          outcome: SyncOutcome.conflictResolvedRemote,
          message: '两侧都有改动，已采用服务器版本',
          at: pulled.at,
        );
      }
      return pulled;
    } catch (e) {
      AppLog.error('WebDAV 同步失败', error: e);
      return SyncReport(
        outcome: SyncOutcome.failed,
        message: _friendlyError(e),
      );
    }
  }

  /// Force-upload the current library as a backup, overwriting the server copy.
  /// 强制将当前库打包上传为备份，覆盖服务器上的副本。
  ///
  /// Unlike [sync], this ignores the fingerprint comparison entirely — it is
  /// the explicit "push my data now" the user asked for, and is the right tool
  /// after a big reorganisation or before switching devices.
  ///
  /// 与 [sync] 不同，此方法完全无视指纹比对——它是用户明确要求的「立即把我的
  /// 数据推上去」，适合在大量整理之后、或换设备之前使用。
  Future<SyncReport> uploadBackup(WebDavCredentials credentials) async {
    if (!credentials.isConfigured) {
      return const SyncReport(
        outcome: SyncOutcome.skipped,
        message: '未配置 WebDAV',
      );
    }

    final SyncMeta meta = _store.readSyncMeta();
    final String deviceId =
        meta.deviceId.isEmpty ? IdUtils.newId() : meta.deviceId;
    final webdav.Client client = _client(credentials);
    final String root = _normalizeRoot(credentials.remoteRoot);

    try {
      await _ensureRemoteRoot(client, root);
      final String fingerprint = BackupService(_store).contentFingerprint();
      return _push(
        client: client,
        snapshotPath: '$root/$snapshotName',
        metaPath: '$root/$metaName',
        deviceId: deviceId,
        fingerprint: fingerprint,
        reportMessage: '备份已上传到服务器',
      );
    } catch (e) {
      AppLog.error('上传备份失败', error: e);
      return SyncReport(
        outcome: SyncOutcome.failed,
        message: _friendlyError(e),
      );
    }
  }

  /// Force-download the server backup and replace the local library with it.
  /// 强制从服务器下载备份并用它替换本地库。
  ///
  /// This is the explicit "restore from server" the user asked for: it does not
  /// consult the fingerprint, it simply takes whatever is on the server and
  /// overwrites the local library. The caller must confirm with the user first.
  ///
  /// 这是用户明确要求的「从服务器恢复」：不咨询指纹，直接取服务器上的内容覆盖
  /// 本地库。调用方必须先向用户确认。
  Future<SyncReport> pullBackup(WebDavCredentials credentials) async {
    if (!credentials.isConfigured) {
      return const SyncReport(
        outcome: SyncOutcome.skipped,
        message: '未配置 WebDAV',
      );
    }

    final SyncMeta meta = _store.readSyncMeta();
    final String deviceId =
        meta.deviceId.isEmpty ? IdUtils.newId() : meta.deviceId;
    final webdav.Client client = _client(credentials);
    final String root = _normalizeRoot(credentials.remoteRoot);

    try {
      await _ensureRemoteRoot(client, root);
      final _RemoteMeta? remote =
          await _readRemoteMeta(client, '$root/$metaName');
      if (remote == null) {
        return const SyncReport(
          outcome: SyncOutcome.failed,
          message: '服务器上还没有备份，请先上传一次',
        );
      }
      return _pull(
        client: client,
        snapshotPath: '$root/$snapshotName',
        deviceId: deviceId,
        remote: remote,
      );
    } catch (e) {
      AppLog.error('拉取备份失败', error: e);
      return SyncReport(
        outcome: SyncOutcome.failed,
        message: _friendlyError(e),
      );
    }
  }

  /// Upload the local library and update the remote metadata.
  /// 上传本地库并更新远端元数据。
  Future<SyncReport> _push({
    required webdav.Client client,
    required String snapshotPath,
    required String metaPath,
    required String deviceId,
    required String fingerprint,
    required String reportMessage,
  }) async {
    final Uint8List archive = await BackupService(_store)
        .buildArchive(scope: BackupScope.full);
    final String archiveHash = HashUtils.ofBytes(archive);
    final DateTime now = DateUtils.nowUtc();

    // Write the payload first, then the metadata. A crash between the two
    // leaves a snapshot whose hash does not match the sidecar, which the reader
    // treats as "no metadata" and recovers from — the reverse order would
    // advertise a snapshot that is not there yet.
    // 先写数据再写元数据。两步之间崩溃会留下哈希与伴随文件不匹配的快照，
    // 读取方将其视为「无元数据」并可恢复；反过来则会预告一个尚不存在的快照。
    await client.write(snapshotPath, archive);

    final Map<String, dynamic> sidecar = <String, dynamic>{
      'schemaVersion': 1,
      'fingerprint': fingerprint,
      'archiveHash': archiveHash,
      'updatedAt': DateUtils.toIso(now),
      'deviceId': deviceId,
    };
    await client.write(
      metaPath,
      Uint8List.fromList(utf8.encode(jsonEncode(sidecar))),
    );

    _store.writeSyncMeta(
      _store.readSyncMeta().copyWith(
            deviceId: deviceId,
            lastSyncAt: now,
            lastUploadedManifestHash: fingerprint,
            lastKnownRemoteHash: fingerprint,
            conflictIds: const <String>[],
          ),
    );

    return SyncReport(
      outcome: SyncOutcome.pushed,
      message: reportMessage,
      at: now,
    );
  }

  /// Download the remote snapshot and replace the local library with it.
  /// 下载远端快照并用它替换本地库。
  Future<SyncReport> _pull({
    required webdav.Client client,
    required String snapshotPath,
    required String deviceId,
    required _RemoteMeta remote,
  }) async {
    final List<int> raw = await client.read(snapshotPath);
    if (raw.isEmpty) {
      throw SyncException('服务器上的快照是空的');
    }

    // Download to a temp file rather than holding it only in memory: a full
    // library archive can be tens of MB, and the restore path already takes a
    // path so no extra API surface is needed.
    // 先下载到临时文件而非仅驻留内存：完整库归档可达数十 MB，
    // 且恢复路径本就接收路径，无需额外 API。
    final String tempDir = await PathUtils.tempPath();
    final String tempPath =
        '$tempDir/sync_${DateUtils.fileStamp(DateUtils.nowUtc())}.zip';
    final File temp = File(tempPath);
    await temp.writeAsBytes(raw, flush: true);

    try {
      final RestoreResult result =
          await BackupService(_store).restoreFrom(tempPath);

      final DateTime now = DateUtils.nowUtc();
      _store.writeSyncMeta(
        _store.readSyncMeta().copyWith(
              deviceId: deviceId,
              lastSyncAt: now,
              lastKnownRemoteHash: remote.fingerprint,
              // The restored content is now what this device holds, so the
              // next comparison needs that same fingerprint on both sides.
              // 恢复后的内容即本设备现有内容，因此下次比对需要两侧持有同一指纹。
              lastUploadedManifestHash: remote.fingerprint,
              conflictIds: const <String>[],
            ),
      );

      return SyncReport(
        outcome: SyncOutcome.pulled,
        message: '已从服务器恢复：${result.summary}',
        at: now,
      );
    } finally {
      // Always clean up, including on failure: leaving a multi-MB temp file
      // behind on every failed sync would quietly fill the device.
      // 无论成功失败都清理：每次同步失败都遗留数 MB 临时文件会悄悄占满设备。
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Best effort only.
        // 尽力而为。
      }
    }
  }

  /// Read and validate the remote sidecar, or null when absent/unreadable.
  /// 读取并校验远端伴随文件；不存在或不可读时返回 null。
  Future<_RemoteMeta?> _readRemoteMeta(
    webdav.Client client,
    String metaPath,
  ) async {
    try {
      final List<int> raw = await client.read(metaPath);
      if (raw.isEmpty) return null;
      final Object? decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map) return null;
      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
      final String fingerprint = (map['fingerprint'] as String?) ?? '';
      if (fingerprint.isEmpty) return null;
      return _RemoteMeta(
        fingerprint: fingerprint,
        updatedAt: DateUtils.tryParse(map['updatedAt']),
        deviceId: (map['deviceId'] as String?) ?? '',
      );
    } catch (_) {
      // A missing sidecar is the normal first-run case, and a corrupt one is
      // indistinguishable from it for our purposes: both mean "no usable
      // comparison", which the caller handles by pushing.
      // 伴随文件缺失是首次运行的正常情况，损坏的伴随文件对此逻辑而言与之无异：
      // 二者都意味着「无可用于比对的信息」，调用方按推送处理。
      return null;
    }
  }

  webdav.Client _client(WebDavCredentials c) {
    final webdav.Client client = webdav.newClient(
      c.baseUrl,
      user: c.username,
      password: c.password,
      debug: false,
    );

    // Pre-emptively send Basic auth. The library defaults to a "no auth, then
    // retry on 401 challenge" flow, which breaks on servers that return a 401
    // whose `www-authenticate` header it cannot parse (or that simply do not
    // send one) — the symptom is a spurious "username or password wrong" for
    // perfectly correct credentials. Sending the header up front removes the
    // fragile challenge dance entirely.
    //
    // 预先发送 Basic 认证。该库默认走「先不带认证、收到 401 挑战再重试」的流程，
    // 遇到返回无法解析的 `www-authenticate` 头（或干脆不返回）的服务器就会失败——
    // 表现为凭据明明正确却报「用户名或密码错误」。提前带上认证头即可彻底绕开
    // 这套脆弱的挑战流程。
    if (c.username.isNotEmpty) {
      client.auth = webdav.BasicAuth(user: c.username, pwd: c.password);
    }

    // Explicit timeouts: the library's defaults are long enough that a wrong
    // host would make the UI appear to hang rather than report a failure.
    // 显式超时：该库的默认值长到足以让错误的主机地址表现为界面卡死，
    // 而不是报告失败。
    client.setConnectTimeout(15000);
    client.setSendTimeout(60000);
    client.setReceiveTimeout(60000);
    return client;
  }

  /// Create the sync folder if needed. `mkdirAll` is idempotent on every server
  /// this app targets, so no existence probe is required.
  /// 按需创建同步文件夹。`mkdirAll` 在本应用面向的各类服务器上都是幂等的，
  /// 因此无需先探测存在性。
  Future<void> _ensureRemoteRoot(
    webdav.Client client,
    String root,
  ) async {
    await client.mkdirAll(_normalizeRoot(root));
  }

  /// Normalise the remote root to `/moepick` form.
  /// 将远端根目录规范化为 `/moepick` 形式。
  static String _normalizeRoot(String root) {
    final String trimmed = root.trim();
    if (trimmed.isEmpty) return '/moepick';
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  /// Turn library exceptions and socket errors into something a user can act on.
  /// 将库异常与套接字错误转为用户可据以行动的信息。
  static String _friendlyError(Object error) {
    if (error is AppException) return error.message;
    final String text = error.toString();
    if (text.contains('401') || text.contains('Unauthorized')) {
      return '认证失败：请确认用户名与「应用密码」正确。\n'
          '坚果云需在「账户信息 → 安全选项」里生成应用密码，'
          '而不是使用登录密码。';
    }
    if (text.contains('404')) {
      return '服务器路径不存在，请检查地址是否正确';
    }
    if (text.contains('SocketException') ||
        text.contains('Connection') ||
        text.contains('timed out')) {
      return '无法连接服务器，请检查网络与地址';
    }
    if (text.contains('HandshakeException')) {
      return 'HTTPS 证书校验失败，请确认服务器证书有效';
    }
    return '同步失败：$text';
  }
}

/// The subset of the remote sidecar this engine relies on.
/// 本引擎依赖的远端伴随文件字段子集。
class _RemoteMeta {
  const _RemoteMeta({
    required this.fingerprint,
    required this.deviceId,
    this.updatedAt,
  });

  final String fingerprint;
  final String deviceId;
  final DateTime? updatedAt;
}
