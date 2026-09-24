import 'package:flutter_test/flutter_test.dart';
import 'package:moepick/data/mappers/effective_meta.dart';
import 'package:moepick/data/models/series.dart';
import 'package:moepick/data/models/sticker.dart';
import 'package:moepick/core/utils/date_utils.dart';

/// Builds a Series with only the fields under test filled in.
/// 仅填充被测字段的 Series 构造辅助。
Series makeSeries({
  String id = 's1',
  String name = '系列A',
  List<String>? categoryIds,
  List<String>? tagIds,
  String note = '',
}) {
  return Series(
    id: id,
    name: name,
    categoryIds: categoryIds,
    tagIds: tagIds,
    note: note,
    createdAt: DateUtils.nowUtc(),
    updatedAt: DateUtils.nowUtc(),
  );
}

/// Builds a Sticker with only the fields under test filled in.
/// 仅填充被测字段的 Sticker 构造辅助。
Sticker makeSticker({
  String id = 'k1',
  String seriesId = 's1',
  String name = '',
  List<String>? categoryIds,
  List<String>? tagIds,
  String note = '',
}) {
  return Sticker(
    id: id,
    seriesId: seriesId,
    name: name,
    relativePath: 'images/$id.png',
    categoryIds: categoryIds,
    tagIds: tagIds,
    note: note,
    createdAt: DateUtils.nowUtc(),
    updatedAt: DateUtils.nowUtc(),
  );
}

void main() {
  group('EffectiveMeta - 分类采用覆盖语义', () {
    test('表情包无分类时继承系列分类', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(categoryIds: <String>[]),
        makeSeries(categoryIds: <String>['c1', 'c2']),
      );
      expect(meta.categoryIds, <String>['c1', 'c2']);
    });

    test('表情包有分类时覆盖系列分类，而非叠加', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(categoryIds: <String>['c9']),
        makeSeries(categoryIds: <String>['c1', 'c2']),
      );
      expect(meta.categoryIds, <String>['c9']);
      expect(meta.categoryIds, isNot(contains('c1')));
    });
  });

  group('EffectiveMeta - 标签采用并集语义', () {
    test('系列标签与表情包标签合并去重，顺序为系列优先', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(tagIds: <String>['t2', 't3']),
        makeSeries(tagIds: <String>['t1', 't2']),
      );
      // t2 在两侧都出现，只应保留一次（系列侧的位置）。
      // t2 appears on both sides and must appear once, at the series position.
      expect(meta.tagIds, <String>['t1', 't2', 't3']);
    });

    test('仅系列有标签时全部继承', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(tagIds: <String>[]),
        makeSeries(tagIds: <String>['t1']),
      );
      expect(meta.tagIds, <String>['t1']);
    });

    test('仅表情包有标签时不受影响', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(tagIds: <String>['t5']),
        makeSeries(tagIds: <String>[]),
      );
      expect(meta.tagIds, <String>['t5']);
    });

    test('空字符串 id 被忽略', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(tagIds: <String>['', 't2']),
        makeSeries(tagIds: <String>['']),
      );
      expect(meta.tagIds, <String>['t2']);
    });
  });

  group('EffectiveMeta - 备注采用拼接语义', () {
    test('两侧都有备注时以分隔符拼接', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(note: '表情包备注'),
        makeSeries(note: '系列备注'),
      );
      expect(meta.note, '系列备注${EffectiveMeta.noteSeparator}表情包备注');
    });

    test('仅系列有备注时直接使用', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(note: ''),
        makeSeries(note: '系列备注'),
      );
      expect(meta.note, '系列备注');
    });

    test('仅表情包有备注时直接使用', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(note: '表情包备注'),
        makeSeries(note: ''),
      );
      expect(meta.note, '表情包备注');
    });

    test('两侧相同时不重复拼接', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(note: '相同'),
        makeSeries(note: '相同'),
      );
      expect(meta.note, '相同');
    });

    test('两侧都有备注时，两者的文本都能被搜到（拼接结果包含双份）', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(note: '傲娇'),
        makeSeries(note: '猫猫'),
      );
      expect(meta.note.contains('傲娇'), isTrue);
      expect(meta.note.contains('猫猫'), isTrue);
    });
  });

  group('EffectiveMeta - 显示名回退', () {
    test('表情包有名时使用其自身名称', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(name: '开心'),
        makeSeries(name: '系列A'),
      );
      expect(meta.displayName, '开心');
    });

    test('表情包无名称时回退到系列名', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(name: ''),
        makeSeries(name: '系列A'),
      );
      expect(meta.displayName, '系列A');
    });

    test('无论是否回退，seriesName 始终为系列名（用于搜索加权）', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(name: '开心'),
        makeSeries(name: '系列A'),
      );
      expect(meta.seriesName, '系列A');
    });
  });

  group('EffectiveMeta - 系列缺失时的容错', () {
    test('系列为 null 时保留表情包自身元数据，不丢字段', () {
      final EffectiveMeta meta = EffectiveMeta.of(
        makeSticker(
          name: '孤立',
          categoryIds: <String>['c1'],
          tagIds: <String>['t1'],
          note: '备注',
        ),
        null,
      );
      expect(meta.categoryIds, <String>['c1']);
      expect(meta.tagIds, <String>['t1']);
      expect(meta.note, '备注');
      expect(meta.displayName, '孤立');
      expect(meta.seriesName, '');
    });

    test('系列为 null 且表情包无名时 displayName 为空而非崩溃', () {
      final EffectiveMeta meta = EffectiveMeta.of(makeSticker(name: ''), null);
      expect(meta.displayName, '');
    });
  });
}
