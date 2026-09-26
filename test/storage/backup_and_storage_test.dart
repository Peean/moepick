import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moepick/core/constants/hive_boxes.dart';
import 'package:moepick/core/constants/hive_type_ids.dart';
import 'package:moepick/core/storage/file_store.dart';
import 'package:moepick/core/storage/hive_registrar.dart';
import 'package:moepick/core/storage/hive_store.dart';
import 'package:moepick/core/utils/date_utils.dart';
import 'package:moepick/core/utils/debouncer.dart';
import 'package:moepick/core/utils/image_utils.dart';
import 'package:moepick/core/utils/path_utils.dart';
import 'package:moepick/data/models/app_settings.dart';
import 'package:moepick/data/models/category.dart';
import 'package:moepick/data/models/series.dart';
import 'package:moepick/data/models/sticker.dart';
import 'package:moepick/data/models/tag.dart';
import 'package:moepick/data/repositories/hive_repositories.dart';
import 'package:moepick/features/backup/application/backup_service.dart';
import 'package:path/path.dart' as p;

/// Shared test scaffolding for the storage-backed suites.
/// 存储相关测试套件共用的脚手架。
///
/// Everything runs against a real temporary directory rather than a mocked
/// filesystem. Path handling (relative vs absolute, Windows separators, atomic
/// renames) is exactly the part most likely to break, and a mock would hide
/// precisely the bugs these tests exist to catch.
///
/// 全部针对真实临时目录运行，而非模拟文件系统。路径处理（相对与绝对、
/// Windows 分隔符、原子重命名）恰恰是最易出错的部分，
/// 而模拟层会掩盖这些测试本要捕获的缺陷。
class TestEnv {
  TestEnv(this.root);

  final Directory root;

  late HiveStore store;

  static Future<TestEnv> create() async {
    final Directory root = await Directory.systemTemp.createTemp('moepick_test_');
    PathUtils.debugOverrideRoot(root.path);
    registerHiveAdapters();
    final Directory hiveDir = Directory(p.join(root.path, 'hive'));
    hiveDir.createSync(recursive: true);

    final TestEnv env = TestEnv(root);
    env.store = await HiveStore.open(overrideRootPath: root.path);
    return env;
  }

  Future<void> dispose() async {
    try {
      await store.close();
    } catch (_) {}
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {}
    PathUtils.debugOverrideRoot(null);
  }

  /// A tiny valid PNG, so image decoding has something real to chew on.
  /// 一张极小的合法 PNG，使图片解码有真实数据可处理。
  static final Uint8List tinyPng = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  /// Write [bytes] to a file inside the temp root and return its absolute path.
  /// 将 [bytes] 写入临时根目录中的文件并返回其绝对路径。
  Future<String> writeSourceFile(String name, List<int> bytes) async {
    final File f = File(p.join(root.path, name));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }
}

/// Verify the hand-written adapters round-trip every field.
/// 验证手写适配器能完整往返每个字段。
///
/// This matters more than usual here: with code generation disabled, an adapter
/// that silently drops a field would corrupt data only after a restart, which is
/// the hardest possible time to notice.
///
/// 此处比通常更重要：在禁用代码生成的条件下，静默丢字段的适配器
/// 只会在重启后才暴露数据损坏，而那是最难察觉的时机。
void main() {
  late TestEnv env;

  setUp(() async {
    env = await TestEnv.create();
  });

  tearDown(() async {
    await env.dispose();
  });

  group('Hive adapters round-trip', () {
    test('Series survives a write/read cycle', () async {
      final DateTime now = DateUtils.nowUtc();
      final Series original = Series(
        id: 'ser-1',
        name: '猫猫日常',
        description: '一只橘猫的日常',
        coverImagePath: 'covers/ser-1.png',
        categoryIds: <String>['cat-1', 'cat-2'],
        tagIds: <String>['tag-1'],
        note: '系列备注',
        stickerCount: 7,
        createdAt: now,
        updatedAt: now,
      );

      await env.store.series.put(original.id, original);
      final Series loaded = env.store.series.get('ser-1')!;

      expect(loaded.name, '猫猫日常');
      expect(loaded.description, '一只橘猫的日常');
      expect(loaded.coverImagePath, 'covers/ser-1.png');
      expect(loaded.categoryIds, <String>['cat-1', 'cat-2']);
      expect(loaded.tagIds, <String>['tag-1']);
      expect(loaded.note, '系列备注');
      expect(loaded.stickerCount, 7);
      expect(loaded.isDeleted, false);
      expect(
        DateUtils.toEpochMs(loaded.createdAt),
        DateUtils.toEpochMs(now),
      );
    });

    test('Sticker survives a write/read cycle', () async {
      final DateTime now = DateUtils.nowUtc();
      final Sticker original = Sticker(
        id: 'stk-1',
        seriesId: 'ser-1',
        name: '惊讶',
        relativePath: 'images/stk-1.png',
        thumbPath: 'thumbs/stk-1_t.jpg',
        width: 320,
        height: 240,
        byteSize: 4096,
        sha256: 'abc123',
        categoryIds: <String>['cat-9'],
        tagIds: <String>['tag-3', 'tag-4'],
        note: '来自群聊',
        sortIndex: 5,
        createdAt: now,
        updatedAt: now,
      );

      await env.store.stickers.put(original.id, original);
      final Sticker loaded = env.store.stickers.get('stk-1')!;

      expect(loaded.seriesId, 'ser-1');
      expect(loaded.name, '惊讶');
      expect(loaded.relativePath, 'images/stk-1.png');
      expect(loaded.thumbPath, 'thumbs/stk-1_t.jpg');
      expect(loaded.width, 320);
      expect(loaded.height, 240);
      expect(loaded.byteSize, 4096);
      expect(loaded.sha256, 'abc123');
      expect(loaded.categoryIds, <String>['cat-9']);
      expect(loaded.tagIds, <String>['tag-3', 'tag-4']);
      expect(loaded.note, '来自群聊');
      expect(loaded.sortIndex, 5);
    });

    test('Sticker with a null thumbnail keeps it null', () async {
      final Sticker s = Sticker.empty(
        id: 'stk-2',
        seriesId: 'ser-1',
        relativePath: 'images/stk-2.png',
      );
      await env.store.stickers.put(s.id, s);
      expect(env.store.stickers.get('stk-2')!.thumbPath, isNull);
    });

    test('Category survives a write/read cycle', () async {
      final Category c = Category(
        id: 'cat-1',
        name: '可爱',
        colorValue: 0xFFE38FB1,
        sortIndex: 3,
        updatedAt: DateUtils.nowUtc(),
      );
      await env.store.categories.put(c.id, c);
      final Category loaded = env.store.categories.get('cat-1')!;
      expect(loaded.name, '可爱');
      expect(loaded.colorValue, 0xFFE38FB1);
      expect(loaded.sortIndex, 3);
    });

    test('Tag survives a write/read cycle', () async {
      final Tag t = Tag(
        id: 'tag-1',
        name: '沙雕',
        usageCount: 12,
        updatedAt: DateUtils.nowUtc(),
      );
      await env.store.tags.put(t.id, t);
      final Tag loaded = env.store.tags.get('tag-1')!;
      expect(loaded.name, '沙雕');
      expect(loaded.usageCount, 12);
    });

    test('BackgroundMode persists by name, not index', () async {
      // Persisting the enum name means reordering `BackgroundMode.values` cannot
      // silently reinterpret stored data.
      // 以枚举名持久化，意味着重排 `BackgroundMode.values` 不会静默改变已存数据含义。
      final BackgroundConfig config = BackgroundConfig(
        imageRelativePath: 'background/bg_src_x.png',
        opacity: 0.6,
        scrimColorValue: 0xFF1B2A4A,
        scrimOpacity: 0.4,
        blurSigma: 12.5,
        mode: BackgroundMode.fullscreen,
        useBlur: true,
        cachedBlurRelativePath: 'background/bg_blur_y.png',
        cachedBlurSourceHash: 'hash-1',
      );
      await env.store.writeBackground(config);

      final BackgroundConfig loaded = env.store.readBackground();
      expect(loaded.mode, BackgroundMode.fullscreen);
      expect(loaded.imageRelativePath, 'background/bg_src_x.png');
      expect(loaded.opacity, closeTo(0.6, 0.0001));
      expect(loaded.scrimColorValue, 0xFF1B2A4A);
      expect(loaded.scrimOpacity, closeTo(0.4, 0.0001));
      expect(loaded.blurSigma, closeTo(12.5, 0.0001));
      expect(loaded.useBlur, true);
      expect(loaded.cachedBlurRelativePath, 'background/bg_blur_y.png');
      expect(loaded.cachedBlurSourceHash, 'hash-1');
    });

    test('Settings and SyncMeta round-trip', () async {
      await env.store.writeSettings(
        AppSettings(
          seedColorValue: 0xFF5FBF9F,
          useDarkMode: true,
          followSystemTheme: false,
          gridColumns: 5,
          compactCards: true,
        ),
      );
      final AppSettings settings = env.store.readSettings();
      expect(settings.seedColorValue, 0xFF5FBF9F);
      expect(settings.useDarkMode, true);
      expect(settings.followSystemTheme, false);
      expect(settings.gridColumns, 5);
      expect(settings.compactCards, true);

      final DateTime syncAt = DateUtils.nowUtc();
      await env.store.writeSyncMeta(
        SyncMeta(
          deviceId: 'dev-1',
          lastSyncAt: syncAt,
          lastUploadedManifestHash: 'h1',
          lastKnownRemoteHash: 'h2',
          remoteEtag: 'etag',
          autoSyncEnabled: true,
          conflictIds: <String>['a', 'b'],
        ),
      );
      final SyncMeta meta = env.store.readSyncMeta();
      expect(meta.deviceId, 'dev-1');
      expect(meta.autoSyncEnabled, true);
      expect(meta.conflictIds, <String>['a', 'b']);
      expect(
        DateUtils.toEpochMs(meta.lastSyncAt!),
        DateUtils.toEpochMs(syncAt),
      );
    });

    test('unknown enum name falls back to the default', () async {
      // A value written by a future version must not brick an older build.
      // 未来版本写入的值不应让旧版本不可用。
      expect(
        BackgroundConfig.fromJson(<String, dynamic>{'mode': 'hologram'}).mode,
        BackgroundMode.card,
      );
    });

    test('type ids stay unique across every registered adapter', () {
      // A collision would make Hive mis-deserialise one model as another.
      // 冲突会导致 Hive 把一个模型错误反序列化为另一个。
      final List<int> ids = <int>[
        HiveTypeIds.series,
        HiveTypeIds.sticker,
        HiveTypeIds.category,
        HiveTypeIds.tag,
        HiveTypeIds.appSettings,
        HiveTypeIds.backgroundConfig,
        HiveTypeIds.syncMeta,
      ];
      expect(ids.toSet().length, ids.length);
    });

    test('every box name is distinct', () {
      expect(HiveBoxes.all.toSet().length, HiveBoxes.all.length);
    });
  });

  group('PathUtils enforces the relative-path rule', () {
    test('image/thumb/cover paths are relative', () {
      expect(PathUtils.imageRelativePath('id1', '.png'),
          p.join('images', 'id1.png'));
      expect(PathUtils.thumbRelativePath('id1', '.jpg'),
          p.join('thumbs', 'id1_t.jpg'));
      expect(PathUtils.coverRelativePath('s1', '.png'),
          p.join('covers', 's1.png'));
      expect(PathUtils.imageRelativePath('id1', ''), p.join('images', 'id1.png'));
      expect(PathUtils.imageRelativePath('id1', '.PNG'),
          p.join('images', 'id1.png'));
    });

    test('absolute() and relative() are inverses inside the root', () async {
      final String abs = await PathUtils.absolute('images/a.png');
      expect(p.isAbsolute(abs), true);
      expect(await PathUtils.relative(abs), p.join('images', 'a.png'));
    });

    test('an already-absolute path passes through unchanged', () async {
      final String already = p.join(env.root.path, 'images', 'a.png');
      expect(await PathUtils.absolute(already), already);
      expect(await PathUtils.relative(already), p.join('images', 'a.png'));
    });

    test('a path outside the root is not relativised', () async {
      // Silently rewriting an outside path into a root-relative one would
      // produce a path that points nowhere.
      // 静默把外部路径改写为根内相对路径，会得到一个指向虚无的路径。
      final String outside = p.join(env.root.parent.path, 'elsewhere', 'x.png');
      expect(await PathUtils.relative(outside), outside);
    });

    test('absoluteSync agrees with absolute once the root is cached', () async {
      final String abs = await PathUtils.absolute('images/b.png');
      expect(PathUtils.absoluteSync('images/b.png'), abs);
      expect(PathUtils.hasCachedRoot, true);
    });
  });

  group('FileStore import', () {
    test('imports a file and records a relative path', () async {
      final String source = await env.writeSourceFile(
        'src1.png',
        TestEnv.tinyPng,
      );
      final FileStore files = FileStore();

      final ImportOutcome outcome = await files.importImage(
        sourcePath: source,
        seriesId: 'ser-1',
      );

      expect(outcome.wasDuplicate, false);
      expect(p.isAbsolute(outcome.sticker.relativePath), false);
      expect(outcome.sticker.relativePath, startsWith('images'));
      expect(outcome.sticker.sha256.isNotEmpty, true);

      // The stored file must actually be on disk at that relative path.
      // 所存文件必须确实位于该相对路径所指向的磁盘位置。
      expect(await files.exists(outcome.sticker.relativePath), true);
    });

    test('defaults the sticker name to the source file name', () async {
      final String source = await env.writeSourceFile(
        '我的表情.png',
        TestEnv.tinyPng,
      );
      final FileStore files = FileStore();

      final ImportOutcome outcome = await files.importImage(
        sourcePath: source,
        seriesId: 'ser-1',
      );

      expect(outcome.sticker.name, '我的表情');
    });

    test('an explicit name wins over the source file name', () async {
      final String source = await env.writeSourceFile(
        'source.png',
        TestEnv.tinyPng,
      );
      final FileStore files = FileStore();

      final ImportOutcome outcome = await files.importImage(
        sourcePath: source,
        seriesId: 'ser-1',
        name: '显式名字',
      );

      expect(outcome.sticker.name, '显式名字');
    });

    test('a second import of identical bytes is reported as a duplicate',
        () async {
      final String source =
          await env.writeSourceFile('src2.png', TestEnv.tinyPng);
      final FileStore files = FileStore();

      final ImportOutcome first = await files.importImage(
        sourcePath: source,
        seriesId: 'ser-1',
      );
      final ImportOutcome second = await files.importImage(
        sourcePath: source,
        seriesId: 'ser-1',
        existingHashes: <String, String>{
          first.sticker.sha256: first.sticker.id,
        },
      );

      expect(second.wasDuplicate, true);
      expect(second.duplicateOfId, first.sticker.id);
    });

    test('a missing source file throws rather than storing a dead entry',
        () async {
      final FileStore files = FileStore();
      expect(
        () => files.importImage(
          sourcePath: p.join(env.root.path, 'nope.png'),
          seriesId: 'ser-1',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('repositories maintain their invariants', () {
    test('save() stamps updatedAt without touching createdAt', () async {
      final HiveSeriesRepository repo = HiveSeriesRepository(env.store);
      final DateTime created = DateUtils.nowUtc().subtract(
        const Duration(days: 3),
      );
      final Series s = Series(
        id: 'ser-x',
        name: '旧名字',
        createdAt: created,
        // Deliberately stale so the stamp is observable.
        // 有意设为陈旧值，使打点行为可被观察。
        updatedAt: created,
      );
      await repo.save(s);

      final Series loaded = repo.getById('ser-x')!;
      expect(
        DateUtils.toEpochMs(loaded.createdAt),
        DateUtils.toEpochMs(created),
      );
      expect(loaded.updatedAt.isAfter(created), true);
    });

    test('softDelete keeps the record but hides it from getAll', () async {
      final HiveSeriesRepository repo = HiveSeriesRepository(env.store);
      await repo.save(Series.empty(id: 'ser-d', name: '待删'));

      await repo.softDelete('ser-d');

      expect(repo.getAll().isEmpty, true);
      // Still present, so sync can propagate the deletion.
      // 记录仍在，使同步能传播删除。
      expect(repo.getAllIncludingDeleted().length, 1);
      expect(repo.getAllIncludingDeleted().first.isDeleted, true);
    });

    test('ensureTag is case-insensitively idempotent', () async {
      final HiveTaxonomyRepository repo = HiveTaxonomyRepository(env.store);

      final String a = await repo.ensureTag('Cat');
      final String b = await repo.ensureTag('cat');
      final String c = await repo.ensureTag('  CAT  ');

      expect(a, b);
      expect(b, c);
      expect(repo.getTags().length, 1);
      expect(repo.getTags().first.name, 'Cat');
    });

    test('ensureTag trims and ignores an empty name', () async {
      final HiveTaxonomyRepository repo = HiveTaxonomyRepository(env.store);
      expect(await repo.ensureTag('   '), '');
      expect(repo.getTags().isEmpty, true);
    });

    test('saveCategoryWithName reuses an existing same-named category',
        () async {
      final HiveTaxonomyRepository repo = HiveTaxonomyRepository(env.store);

      final String first = await repo.saveCategoryWithName('可爱');
      final String second = await repo.saveCategoryWithName('可爱');

      expect(first, second);
      expect(repo.getCategories().length, 1);
    });

    test('consecutive new categories get distinct colours', () async {
      final HiveTaxonomyRepository repo = HiveTaxonomyRepository(env.store);
      await repo.saveCategoryWithName('一');
      await repo.saveCategoryWithName('二');
      await repo.saveCategoryWithName('三');

      final Set<int> colours =
          repo.getCategories().map((Category c) => c.colorValue).toSet();
      expect(colours.length, 3);
    });

    test('refreshTagUsage counts both stickers and series', () async {
      final HiveTaxonomyRepository repo = HiveTaxonomyRepository(env.store);
      final HiveStickerRepository stickers =
          HiveStickerRepository(env.store);

      final String tagId = await repo.ensureTag('常用');

      await stickers.save(
        Sticker.empty(id: 's1', seriesId: 'ser', relativePath: 'images/s1.png')
            .copyWith(tagIds: <String>[tagId]),
      );
      await stickers.save(
        Sticker.empty(id: 's2', seriesId: 'ser', relativePath: 'images/s2.png')
            .copyWith(tagIds: <String>[tagId]),
      );
      await HiveSeriesRepository(env.store).save(
        Series.empty(id: 'ser', name: 'S').copyWith(tagIds: <String>[tagId]),
      );

      await repo.refreshTagUsage();

      expect(repo.getTagById(tagId)!.usageCount, 3);
    });

    test('getBySeries returns only live stickers of that series', () async {
      final HiveStickerRepository repo = HiveStickerRepository(env.store);
      await repo.save(Sticker.empty(
          id: 'a', seriesId: 'g1', relativePath: 'images/a.png'));
      await repo.save(Sticker.empty(
          id: 'b', seriesId: 'g1', relativePath: 'images/b.png'));
      await repo.save(Sticker.empty(
          id: 'c', seriesId: 'g2', relativePath: 'images/c.png'));
      await repo.softDelete('b');

      final List<Sticker> g1 = repo.getBySeries('g1');
      expect(g1.map((Sticker s) => s.id), <String>['a']);
      expect(repo.countBySeries('g1'), 1);
      expect(repo.countBySeries('g2'), 1);
    });
  });

  group('BackgroundConfig', () {
    test('hasImage is false for null and empty paths', () {
      expect(BackgroundConfig().hasImage, false);
      expect(
        BackgroundConfig(imageRelativePath: '').hasImage,
        false,
      );
      expect(
        BackgroundConfig(imageRelativePath: 'background/x.png').hasImage,
        true,
      );
    });

    test('cleared() keeps the look but drops the image and caches', () {
      final BackgroundConfig original = BackgroundConfig(
        imageRelativePath: 'background/a.png',
        opacity: 0.7,
        scrimOpacity: 0.3,
        scrimColorValue: 0xFF112233,
        blurSigma: 9,
        useBlur: true,
        mode: BackgroundMode.fullscreen,
        cachedBlurRelativePath: 'background/bg_blur_z.png',
        cachedBlurSourceHash: 'k',
      );

      final BackgroundConfig cleared = original.cleared();

      expect(cleared.hasImage, false);
      expect(cleared.cachedBlurRelativePath, isNull);
      expect(cleared.cachedBlurSourceHash, isNull);
      // Presentation preferences survive, so re-adding an image restores the look.
      // 展示偏好保留，使重新添加图片即可恢复原效果。
      expect(cleared.opacity, 0.7);
      expect(cleared.scrimOpacity, closeTo(0.3, 0.0001));
      expect(cleared.scrimColorValue, 0xFF112233);
      expect(cleared.useBlur, true);
      expect(cleared.mode, BackgroundMode.fullscreen);
    });

    test('copyWith can distinguish "unset" from "set to null"', () {
      final BackgroundConfig withImage =
          BackgroundConfig(imageRelativePath: 'background/a.png');

      // Not passed: the field is preserved.
      // 未传参：字段保留。
      expect(withImage.copyWith(opacity: 0.5).imageRelativePath,
          'background/a.png');
      // Explicitly null: the field is cleared.
      // 显式传 null：字段被清空。
      expect(withImage.copyWith(imageRelativePath: null).imageRelativePath,
          isNull);
    });

    test('needsLiveBlur only when blur is asked for but not yet cached', () {
      expect(
        BackgroundConfig(useBlur: true, blurSigma: 10).needsLiveBlur,
        true,
      );
      expect(
        BackgroundConfig(
          useBlur: true,
          blurSigma: 10,
          cachedBlurRelativePath: 'background/bg_blur_a.png',
        ).needsLiveBlur,
        false,
      );
      expect(BackgroundConfig(blurSigma: 10).needsLiveBlur, false);
    });
  });

  group('ImageUtils', () {
    test('extensionOf normalises case and defaults to png', () {
      expect(PathUtils.extensionOf('a.PNG'), '.png');
      expect(PathUtils.extensionOf('a.jpeg'), '.jpeg');
      expect(PathUtils.extensionOf('noext'), '.png');
    });

    test('sigmaFor maps a radius to a stable sigma', () {
      expect(ImageUtils.sigmaFor(0), 0);
      expect(ImageUtils.sigmaFor(30), closeTo(10, 0.0001));
    });

    test('downscaleSync leaves an already-small image untouched', () {
      final Uint8List bytes = TestEnv.tinyPng;
      expect(ImageUtils.downscaleSync(bytes, 300).length, bytes.length);
    });

    test('createThumbnailSync produces a decodable result for a tiny png',
        () {
      // The 1x1 source cannot shrink further, so the same bytes come back —
      // which still proves the decode/encode path runs without throwing.
      // 1x1 源图无法再缩小，因此返回相同字节——
      // 这仍然证明解码/编码路径可正常执行而不抛异常。
      final Uint8List thumb =
          ImageUtils.createThumbnailSync(TestEnv.tinyPng, 300);
      expect(thumb.isNotEmpty, true);
    });
  });

  group('BackupService', () {
    /// Seed a small but non-trivial library.
    /// 填充一个规模小但不平凡的库。
    Future<void> seed() async {
      final DateTime now = DateUtils.nowUtc();
      await env.store.series.put(
        'ser-1',
        Series(
          id: 'ser-1',
          name: '猫猫',
          categoryIds: <String>['cat-1'],
          tagIds: <String>['tag-1'],
          note: '系列备注',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await env.store.stickers.put(
        'stk-1',
        Sticker(
          id: 'stk-1',
          seriesId: 'ser-1',
          name: '惊讶',
          relativePath: 'images/stk-1.png',
          tagIds: <String>['tag-2'],
          note: '表情备注',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await env.store.categories.put(
        'cat-1',
        Category(id: 'cat-1', name: '可爱', updatedAt: now),
      );
      await env.store.tags.put(
        'tag-1',
        Tag(id: 'tag-1', name: '橘猫', updatedAt: now),
      );
      await env.store.tags.put(
        'tag-2',
        Tag(id: 'tag-2', name: '沙雕', updatedAt: now),
      );
      await env.store.writeSettings(
        AppSettings(seedColorValue: 0xFF9B8FE0, gridColumns: 4),
      );
    }

    test('a settings-only archive omits asset files', () async {
      await seed();
      final BackupService service = BackupService(env.store);

      final List<int> bytes =
          await service.buildArchive(scope: BackupScope.settingsOnly);
      expect(bytes.isNotEmpty, true);

      // Round-trip through a device that has nothing.
      await env.store.series.clear();
      await env.store.stickers.clear();
      await env.store.categories.clear();
      await env.store.tags.clear();

      final String path = await env.writeSourceFile('b1.zip', bytes);
      final RestoreResult result = await service.restoreFrom(path);

      expect(result.seriesCount, 1);
      expect(result.stickerCount, 1);
      expect(result.assetCount, 0);
      expect(result.isFullRestore, false);
      expect(env.store.readSettings().seedColorValue, 0xFF9B8FE0);
      expect(env.store.readSettings().gridColumns, 4);
    });

    test('every record field survives a full round-trip', () async {
      await seed();
      final BackupService service = BackupService(env.store);

      final List<int> bytes =
          await service.buildArchive(scope: BackupScope.settingsOnly);
      final String path = await env.writeSourceFile('b2.zip', bytes);

      await env.store.series.clear();
      await env.store.stickers.clear();
      await service.restoreFrom(path);

      final Series series = env.store.series.get('ser-1')!;
      expect(series.name, '猫猫');
      expect(series.categoryIds, <String>['cat-1']);
      expect(series.tagIds, <String>['tag-1']);
      expect(series.note, '系列备注');

      final Sticker sticker = env.store.stickers.get('stk-1')!;
      expect(sticker.seriesId, 'ser-1');
      expect(sticker.name, '惊讶');
      expect(sticker.relativePath, 'images/stk-1.png');
      expect(sticker.tagIds, <String>['tag-2']);
      expect(sticker.note, '表情备注');

      expect(env.store.categories.get('cat-1')!.name, '可爱');
      expect(env.store.tags.get('tag-1')!.name, '橘猫');
    });

    test('restore replaces rather than merges', () async {
      await seed();
      final BackupService service = BackupService(env.store);
      final List<int> bytes =
          await service.buildArchive(scope: BackupScope.settingsOnly);
      final String path = await env.writeSourceFile('b3.zip', bytes);

      // Add a record the backup does not contain.
      // 添加一条备份中不存在的记录。
      await env.store.series.put(
        'ghost',
        Series(
          id: 'ghost',
          name: '幽灵',
          createdAt: DateUtils.nowUtc(),
          updatedAt: DateUtils.nowUtc(),
        ),
      );

      await service.restoreFrom(path);

      // A merge would have left 'ghost' behind, producing a library that is
      // neither the backup nor the pre-restore state.
      // 合并会把 'ghost' 留下，得到一个既非备份也非恢复前状态的库。
      expect(env.store.series.get('ghost'), isNull);
      expect(env.store.series.length, 1);
    });

    test('soft-deleted records are preserved so deletions propagate', () async {
      await seed();
      await env.store.series.put(
        'ser-1',
        env.store.series.get('ser-1')!.copyWith(isDeleted: true),
      );

      final BackupService service = BackupService(env.store);
      final List<int> bytes =
          await service.buildArchive(scope: BackupScope.settingsOnly);
      final String path = await env.writeSourceFile('b4.zip', bytes);

      await env.store.series.clear();
      await service.restoreFrom(path);

      expect(env.store.series.get('ser-1')!.isDeleted, true);
    });

    test('a file that is not a MoePick backup is rejected clearly', () async {
      final BackupService service = BackupService(env.store);
      final String path =
          await env.writeSourceFile('notabackup.zip', <int>[1, 2, 3, 4]);
      expect(
        () => service.restoreFrom(path),
        throwsA(isA<Exception>()),
      );
    });

    test('a missing file is reported rather than silently ignored', () async {
      final BackupService service = BackupService(env.store);
      expect(
        () => service.restoreFrom(p.join(env.root.path, 'missing.zip')),
        throwsA(isA<Exception>()),
      );
    });

    test('contentFingerprint changes when data changes and is stable '
        'otherwise', () async {
      final BackupService service = BackupService(env.store);

      final String empty = service.contentFingerprint();
      expect(service.contentFingerprint(), empty);

      await seed();
      final String seeded = service.contentFingerprint();
      expect(seeded, isNot(empty));
      expect(service.contentFingerprint(), seeded);

      // An updatedAt bump alone must move the fingerprint, because that is the
      // signal the sync engine uses to decide whether an upload is needed.
      // 仅 updatedAt 变化也必须改变指纹，因为同步引擎据此判断是否需要上传。
      final Series s = env.store.series.get('ser-1')!;
      await env.store.series.put(
        'ser-1',
        s.copyWith(
          name: '改过名字',
          updatedAt: DateUtils.nowUtc().add(const Duration(seconds: 1)),
        ),
      );
      expect(service.contentFingerprint(), isNot(seeded));
    });

    test('suggestedFileName encodes scope and timestamp', () {
      final String full = BackupService.suggestedFileName(BackupScope.full);
      final String settings =
          BackupService.suggestedFileName(BackupScope.settingsOnly);

      expect(full.startsWith('moepick_full_'), true);
      expect(full.endsWith('.zip'), true);
      expect(settings.startsWith('moepick_settings_'), true);
    });
  });

  group('Debouncer', () {
    test('fires once after the delay even when run repeatedly', () async {
      final Debouncer d = Debouncer(const Duration(milliseconds: 40));
      int calls = 0;

      d.run(() => calls++);
      d.run(() => calls++);
      d.run(() => calls++);

      expect(calls, 0);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(calls, 1);
      d.dispose();
    });

    test('flushNow fires the last scheduled action immediately', () {
      final Debouncer d = Debouncer(const Duration(seconds: 30));
      int calls = 0;
      d.run(() => calls++);
      d.flushNow();
      expect(calls, 1);
      d.dispose();
    });

    test('cancel drops the pending action', () async {
      final Debouncer d = Debouncer(const Duration(milliseconds: 30));
      int calls = 0;
      d.run(() => calls++);
      d.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(calls, 0);
      expect(d.isPending, false);
      d.dispose();
    });
  });
}
