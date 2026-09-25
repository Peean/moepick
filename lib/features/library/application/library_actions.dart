import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/data_version.dart';
import '../../../core/storage/file_store.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/id_utils.dart';
import '../../../data/models/series.dart';
import '../../../data/models/sticker.dart';
import '../../../data/repositories/repository_contracts.dart';
import '../../settings/application/background_service.dart';
import '../../settings/application/storage_providers.dart';

/// Write operations for series and stickers.
/// 系列与表情包的写操作。
///
/// Every mutation funnels through here so that `updatedAt` stamping, sticker
/// count maintenance and the data-version bump happen consistently. Feature
/// code never writes to a repository directly.
///
/// 所有变更都经由此处，以保证 `updatedAt` 打点、表情包计数维护与数据版本自增
/// 行为一致。业务代码不直接写仓储。
class LibraryActions {
  LibraryActions(this._ref);

  final Ref _ref;

  /// Create a series and return its id.
  /// 创建系列并返回其 id。
  Future<String> createSeries({required String name}) async {
    final DateTime now = DateUtils.nowUtc();
    final Series created = Series(
      id: IdUtils.newId(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    await _ref.read(seriesRepositoryProvider).save(created);
    _bump();
    return created.id;
  }

  /// Update a series' editable fields.
  /// 更新系列的可编辑字段。
  Future<void> updateSeries(
    Series series, {
    String? name,
    String? description,
    List<String>? categoryIds,
    List<String>? tagIds,
    String? note,
  }) async {
    await _ref.read(seriesRepositoryProvider).save(
          series.copyWith(
            name: name,
            description: description,
            categoryIds: categoryIds,
            tagIds: tagIds,
            note: note,
          ),
        );
    _bump();
  }

  /// Soft-delete a series together with its stickers.
  /// 软删除系列及其下的表情包。
  ///
  /// The stickers are soft-deleted too so that sync propagates the removals;
  /// leaving them live would let them reappear as orphans on another device.
  /// 表情包同样软删除，使同步能传播删除操作；
  /// 若保持存活，它们会在其他设备上作为孤儿记录重新出现。
  Future<void> deleteSeries(String seriesId) =>
      deleteSeriesBatch(<String>[seriesId]);

  /// Soft-delete several series (and their stickers) in one pass, bumping the
  /// data version exactly once.
  /// 一次软删除多个系列（及其表情包），仅自增一次数据版本。
  Future<void> deleteSeriesBatch(List<String> seriesIds) async {
    if (seriesIds.isEmpty) return;
    final StickerRepository stickers = _ref.read(stickerRepositoryProvider);
    final SeriesRepository seriesRepo = _ref.read(seriesRepositoryProvider);

    for (final String seriesId in seriesIds) {
      final List<Sticker> children = stickers.getBySeries(seriesId);
      for (final Sticker s in children) {
        await stickers.softDelete(s.id);
      }
      await seriesRepo.softDelete(seriesId);
    }
    _bump();
  }

  /// Import a batch of images into a series.
  /// 将一批图片导入某个系列。
  ///
  /// The hash index is loaded **once** and then extended as files land, so an
  /// import of 50 photos de-duplicates against both the existing library and
  /// the earlier files in the same batch, without re-reading every sticker per
  /// file (which would be O(n·m)).
  ///
  /// 哈希索引**只加载一次**，并随文件落盘增量扩展，
  /// 因此导入 50 张照片时既能对已有库去重，也能对本批次内的先前文件去重，
  /// 而不必对每个文件重读全部表情包（那将是 O(n·m)）。
  Future<ImportBatchResult> importStickers({
    required String seriesId,
    required List<String> sourcePaths,
  }) async {
    final StickerRepository stickers = _ref.read(stickerRepositoryProvider);
    final FileStore files = _ref.read(fileStoreProvider);

    // sha256 -> stickerId, seeded from the live library and grown as we go.
    // sha256 -> stickerId，以当前库为初始值，并随进度增长。
    final Map<String, String> hashIndex =
        Map<String, String>.from(stickers.hashIndex());

    final List<Sticker> created = <Sticker>[];
    int duplicates = 0;
    int failed = 0;

    // Continue numbering after existing stickers so the batch appears last.
    // 序号接续已有表情包，使本批次排在末尾。
    int sortIndex = stickers.countBySeries(seriesId);

    for (final String path in sourcePaths) {
      try {
        final ImportOutcome outcome = await files.importImage(
          sourcePath: path,
          seriesId: seriesId,
          existingHashes: hashIndex,
          sortIndex: sortIndex,
        );

        if (outcome.wasDuplicate) {
          duplicates++;
          continue;
        }

        await stickers.save(outcome.sticker);
        hashIndex[outcome.sticker.sha256] = outcome.sticker.id;
        created.add(outcome.sticker);
        sortIndex++;
      } catch (e) {
        // One bad file (corrupt image, permission denied) must not abort the
        // rest of the batch.
        // 单个坏文件（图片损坏、权限不足）不应中断整批导入。
        failed++;
        if (kDebugMode) {
          debugPrint('[LibraryActions] import failed for $path: $e');
        }
      }
    }

    if (created.isNotEmpty) {
      await _syncSeriesCount(seriesId);
      await _refreshTagUsage();
      _bump();
    }

    return ImportBatchResult(
      imported: created.length,
      duplicates: duplicates,
      failed: failed,
    );
  }

  /// Update a sticker's editable fields.
  /// 更新表情包的可编辑字段。
  Future<void> updateSticker(
    Sticker sticker, {
    String? name,
    List<String>? categoryIds,
    List<String>? tagIds,
    String? note,
  }) async {
    await _ref.read(stickerRepositoryProvider).save(
          sticker.copyWith(
            name: name,
            categoryIds: categoryIds,
            tagIds: tagIds,
            note: note,
          ),
        );
    await _refreshTagUsage();
    _bump();
  }

  /// Soft-delete a sticker and refresh the parent series' count.
  /// 软删除表情包并刷新其所属系列的计数。
  Future<void> deleteSticker(Sticker sticker) async {
    await _ref.read(stickerRepositoryProvider).softDelete(sticker.id);
    await _syncSeriesCount(sticker.seriesId);
    await _refreshTagUsage();
    _bump();
  }

  /// Soft-delete a batch of stickers (multi-select flow).
  /// 批量软删除表情包（多选流程）。
  Future<int> deleteStickers(List<Sticker> stickers) async {
    if (stickers.isEmpty) return 0;
    final StickerRepository repo = _ref.read(stickerRepositoryProvider);
    final Set<String> seriesIds = <String>{};
    for (final Sticker s in stickers) {
      await repo.softDelete(s.id);
      seriesIds.add(s.seriesId);
    }
    for (final String seriesId in seriesIds) {
      await _syncSeriesCount(seriesId);
    }
    await _refreshTagUsage();
    _bump();
    return stickers.length;
  }

  // ------------------------------------------------------------------ 回收站

  /// Undo a soft-delete for a batch of stickers.
  /// 批量还原软删除的表情包。
  Future<void> restoreStickers(List<String> ids) async {
    if (ids.isEmpty) return;
    final StickerRepository repo = _ref.read(stickerRepositoryProvider);
    final Map<String, Sticker> byId = <String, Sticker>{
      for (final Sticker s in _allStickers()) s.id: s,
    };
    final Set<String> seriesIds = <String>{};
    for (final String id in ids) {
      final Sticker? s = byId[id];
      if (s != null) seriesIds.add(s.seriesId);
    }
    await repo.restoreAll(ids);
    for (final String seriesId in seriesIds) {
      await _syncSeriesCount(seriesId);
    }
    await _refreshTagUsage();
    _bump();
  }

  /// Physically remove stickers and their image files.
  /// 物理移除表情包及其图片文件。
  Future<void> purgeStickers(List<String> ids) async {
    if (ids.isEmpty) return;
    final StickerRepository repo = _ref.read(stickerRepositoryProvider);
    final FileStore files = _ref.read(fileStoreProvider);
    final Map<String, Sticker> byId = <String, Sticker>{
      for (final Sticker s in _allStickers()) s.id: s,
    };
    final Set<String> seriesIds = <String>{};

    for (final String id in ids) {
      final Sticker? s = byId[id];
      if (s == null) continue;
      seriesIds.add(s.seriesId);
      // Best-effort file cleanup: losing a file must not block the record
      // deletion, which is the part that matters for storage correctness.
      // 尽力清理文件：删文件失败不应阻塞记录删除——后者才是存储正确性的关键。
      try {
        if (s.relativePath.isNotEmpty) await files.delete(s.relativePath);
        final String? thumb = s.thumbPath;
        if (thumb != null && thumb.isNotEmpty) await files.delete(thumb);
      } catch (_) {}
    }

    await repo.purgeAll(ids);
    for (final String seriesId in seriesIds) {
      await _syncSeriesCount(seriesId);
    }
    await _refreshTagUsage();
    _bump();
  }

  /// Restore a soft-deleted series together with its soft-deleted stickers.
  /// 还原软删除的系列，并连带还原其下被软删除的表情包。
  ///
  /// Restoring only the parent would leave its children hidden forever (they
  /// were soft-deleted alongside it), which reads as "restore lost my
  /// stickers".
  ///
  /// 只还原父级会让子项永远不可见（它们是随父级一起被软删除的），
  /// 在用户看来就是「还原之后表情包丢了」。
  Future<void> restoreSeries(String seriesId) async {
    await _ref.read(seriesRepositoryProvider).restore(seriesId);
    final List<Sticker> children = _allStickers()
        .where((Sticker s) => s.seriesId == seriesId && s.isDeleted)
        .toList();
    await _ref
        .read(stickerRepositoryProvider)
        .restoreAll(children.map((Sticker s) => s.id).toList());
    await _syncSeriesCount(seriesId);
    await _refreshTagUsage();
    _bump();
  }

  /// Physically remove a series, its stickers and their files.
  /// 物理移除系列、其表情包与对应文件。
  Future<void> purgeSeries(String seriesId) async {
    final FileStore files = _ref.read(fileStoreProvider);
    final List<Sticker> children = _allStickers()
        .where((Sticker s) => s.seriesId == seriesId)
        .toList();

    for (final Sticker s in children) {
      try {
        if (s.relativePath.isNotEmpty) await files.delete(s.relativePath);
        final String? thumb = s.thumbPath;
        if (thumb != null && thumb.isNotEmpty) await files.delete(thumb);
      } catch (_) {}
    }

    await _ref
        .read(stickerRepositoryProvider)
        .purgeAll(children.map((Sticker s) => s.id).toList());
    await _ref.read(seriesRepositoryProvider).purge(seriesId);
    await _refreshTagUsage();
    _bump();
  }

  /// Permanently remove everything soft-deleted more than [AppConstants.
  /// trashRetention] ago. Called when the trash page opens.
  /// 彻底清除软删除超过 [AppConstants.trashRetention] 的所有条目。
  /// 在回收站页打开时调用。
  Future<int> purgeExpired() async {
    final DateTime cutoff =
        DateUtils.nowUtc().subtract(AppConstants.trashRetention);
    final List<Sticker> expiredStickers = _allStickers()
        .where((Sticker s) => s.isDeleted && s.updatedAt.isBefore(cutoff))
        .toList();
    final List<Series> expiredSeries = _allSeries()
        .where((Series s) => s.isDeleted && s.updatedAt.isBefore(cutoff))
        .toList();

    if (expiredStickers.isEmpty && expiredSeries.isEmpty) return 0;

    await purgeStickers(expiredStickers.map((Sticker s) => s.id).toList());
    for (final Series s in expiredSeries) {
      await purgeSeries(s.id);
    }
    return expiredStickers.length + expiredSeries.length;
  }

  /// Live + deleted stickers, for trash/restore bookkeeping.
  /// 存活与已删除的全部表情包，供回收站/还原逻辑使用。
  List<Sticker> _allStickers() =>
      _ref.read(stickerRepositoryProvider).getAllIncludingDeleted();

  List<Series> _allSeries() =>
      _ref.read(seriesRepositoryProvider).getAllIncludingDeleted();

  /// Recompute and store a series' sticker count.
  /// 重算并保存某系列的表情包计数。
  Future<void> _syncSeriesCount(String seriesId) async {
    final int count =
        _ref.read(stickerRepositoryProvider).countBySeries(seriesId);
    final Series? series = _ref.read(seriesRepositoryProvider).getById(seriesId);
    if (series == null || series.stickerCount == count) return;
    await _ref
        .read(seriesRepositoryProvider)
        .save(series.copyWith(stickerCount: count));
  }

  Future<void> _refreshTagUsage() =>
      _ref.read(taxonomyRepositoryProvider).refreshTagUsage();

  /// Single place that signals "data changed".
  /// 唯一发出「数据已变化」信号的位置。
  void _bump() => _ref.read(dataVersionProvider.notifier).bump();
}

/// Provider for [LibraryActions].
/// [LibraryActions] 的 provider。
final Provider<LibraryActions> libraryActionsProvider =
    Provider<LibraryActions>((Ref ref) => LibraryActions(ref));

/// Summary of one batch import.
/// 单次批量导入的汇总。
///
/// A plain class rather than a record: Dart 2.17 predates records.
/// 使用普通类而非 record：Dart 2.17 尚无 records。
class ImportBatchResult {
  const ImportBatchResult({
    required this.imported,
    required this.duplicates,
    required this.failed,
  });

  final int imported;
  final int duplicates;
  final int failed;

  int get total => imported + duplicates + failed;

  /// True when nothing changed, so callers can skip the "success" toast.
  /// 当没有任何变化时为 true，调用方据此跳过「成功」提示。
  bool get isNoop => imported == 0;
}
