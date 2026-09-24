import 'package:flutter_test/flutter_test.dart';
import 'package:moepick/core/utils/date_utils.dart';
import 'package:moepick/data/models/category.dart';
import 'package:moepick/data/models/series.dart';
import 'package:moepick/data/models/sticker.dart';
import 'package:moepick/data/models/tag.dart';
import 'package:moepick/data/repositories/search_repository.dart';

/// Fixture builder so each test only states what it cares about.
/// 测试夹具构造器，使每个用例只声明自己关心的部分。
class Fixture {
  Fixture() {
    seriesById = <String, Series>{};
    stickerList = <Sticker>[];
    categoryById = <String, Category>{};
    tagById = <String, Tag>{};
  }

  late Map<String, Series> seriesById;
  late List<Sticker> stickerList;
  late Map<String, Category> categoryById;
  late Map<String, Tag> tagById;

  Series addSeries({
    required String id,
    String name = '',
    List<String> tags = const <String>[],
    List<String> categories = const <String>[],
    String note = '',
  }) {
    final Series s = Series(
      id: id,
      name: name,
      tagIds: tags,
      categoryIds: categories,
      note: note,
      createdAt: DateUtils.nowUtc(),
      updatedAt: DateUtils.nowUtc(),
    );
    seriesById[id] = s;
    return s;
  }

  Sticker addSticker({
    required String id,
    required String seriesId,
    String name = '',
    List<String> tags = const <String>[],
    List<String> categories = const <String>[],
    String note = '',
  }) {
    final Sticker s = Sticker(
      id: id,
      seriesId: seriesId,
      name: name,
      relativePath: 'images/$id.png',
      tagIds: tags,
      categoryIds: categories,
      note: note,
      createdAt: DateUtils.nowUtc(),
      updatedAt: DateUtils.nowUtc(),
    );
    stickerList.add(s);
    return s;
  }

  void addTag(String id, String name) {
    tagById[id] = Tag(
      id: id,
      name: name,
      updatedAt: DateUtils.nowUtc(),
    );
  }

  void addCategory(String id, String name) {
    categoryById[id] = Category(
      id: id,
      name: name,
      updatedAt: DateUtils.nowUtc(),
    );
  }

  List<SearchHit> run(SearchQuery query) {
    return SearchRepository().search(
      query: query,
      stickers: stickerList,
      seriesById: seriesById,
      categoryById: categoryById,
      tagById: tagById,
    );
  }
}

void main() {
  group('搜索 - 空查询', () {
    test('空查询返回空结果，而不是整库', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'k1', seriesId: 's1', name: '开心');
      expect(f.run(SearchQuery.empty), isEmpty);
    });
  });

  group('搜索 - 按备注命中', () {
    test('表情包自身备注可被搜到', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'k1', seriesId: 's1', name: '开心', note: '用于斗图');

      final List<SearchHit> hits = f.run(const SearchQuery(text: '斗图'));
      expect(hits.length, 1);
      expect(hits.first.sticker.id, 'k1');
      expect(hits.first.matchedNote, isTrue);
    });

    test('系列级备注也能搜到其下表情包（验证继承生效）', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '系列A', note: '猫猫专用');
      f.addSticker(id: 'k1', seriesId: 's1', name: '开心');

      final List<SearchHit> hits = f.run(const SearchQuery(text: '猫猫'));
      expect(hits.length, 1);
      expect(hits.first.sticker.id, 'k1');
      expect(hits.first.matchedNote, isTrue);
    });
  });

  group('搜索 - 按标签命中', () {
    test('表情包自身标签可被搜到', () {
      final Fixture f = Fixture();
      f.addTag('t1', '可爱');
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'k1', seriesId: 's1', name: '开心', tags: <String>['t1']);

      final List<SearchHit> hits = f.run(const SearchQuery(text: '可爱'));
      expect(hits.length, 1);
      expect(hits.first.matchedTag, isTrue);
    });

    test('系列级标签也能搜到其下表情包（并集语义）', () {
      final Fixture f = Fixture();
      f.addTag('t1', '萌宠');
      f.addSeries(id: 's1', name: '系列A', tags: <String>['t1']);
      f.addSticker(id: 'k1', seriesId: 's1', name: '开心');

      final List<SearchHit> hits = f.run(const SearchQuery(text: '萌宠'));
      expect(hits.length, 1);
      expect(hits.first.matchedTag, isTrue);
    });
  });

  group('搜索 - 按分类命中', () {
    test('系列级分类可搜到其下表情包（覆盖语义下表情包无分类）', () {
      final Fixture f = Fixture();
      f.addCategory('c1', '斗图');
      f.addSeries(id: 's1', name: '系列A', categories: <String>['c1']);
      f.addSticker(id: 'k1', seriesId: 's1', name: '开心');

      final List<SearchHit> hits = f.run(const SearchQuery(text: '斗图'));
      expect(hits.length, 1);
      expect(hits.first.matchedCategory, isTrue);
    });

    test('表情包自身有分类时，系列分类不再参与该表情包的搜索', () {
      final Fixture f = Fixture();
      f.addCategory('c1', '斗图');
      f.addCategory('c2', '萌宠');
      f.addSeries(id: 's1', name: '系列A', categories: <String>['c1']);
      f.addSticker(
        id: 'k1',
        seriesId: 's1',
        name: '开心',
        categories: <String>['c2'],
      );

      // 覆盖后只保留 c2，搜索系列分类应无结果。
      // After override only c2 remains, so the series category must not match.
      expect(f.run(const SearchQuery(text: '斗图')), isEmpty);
      expect(f.run(const SearchQuery(text: '萌宠')).length, 1);
    });
  });

  group('搜索 - 按名称命中', () {
    test('表情包名称可被搜到', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'k1', seriesId: 's1', name: '开心');

      final List<SearchHit> hits = f.run(const SearchQuery(text: '开心'));
      expect(hits.first.matchedName, isTrue);
    });

    test('搜系列名能搜到该系列下所有表情包', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '布偶猫');
      f.addSticker(id: 'k1', seriesId: 's1', name: '甲');
      f.addSticker(id: 'k2', seriesId: 's1', name: '乙');

      final List<SearchHit> hits = f.run(const SearchQuery(text: '布偶猫'));
      expect(hits.length, 2);
      for (final SearchHit h in hits) {
        expect(h.matchedSeriesName, isTrue);
      }
    });

    test('未命名表情包回退系列名后仍可被搜到', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '布偶猫');
      f.addSticker(id: 'k1', seriesId: 's1', name: '');

      final List<SearchHit> hits = f.run(const SearchQuery(text: '布偶猫'));
      expect(hits.length, 1);
      expect(hits.first.sticker.id, 'k1');
    });
  });

  group('搜索 - 中文子串匹配', () {
    test('部分匹配即可命中，无需分词', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'k1', seriesId: 's1', name: '超可爱');

      expect(f.run(const SearchQuery(text: '可爱')).length, 1);
    });

    test('大小写不敏感', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'k1', seriesId: 's1', name: 'Happy Cat');

      expect(f.run(const SearchQuery(text: 'happy')).length, 1);
      expect(f.run(const SearchQuery(text: 'HAPPY')).length, 1);
    });
  });

  group('搜索 - 排序与权重', () {
    test('名称命中优先于备注命中', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'kNote', seriesId: 's1', name: '甲', note: '开心');
      f.addSticker(id: 'kName', seriesId: 's1', name: '开心');

      final List<SearchHit> hits = f.run(const SearchQuery(text: '开心'));
      expect(hits.length, 2);
      expect(hits.first.sticker.id, 'kName');
    });

    test('前缀命中比中间命中得分更高', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'kPrefix', seriesId: 's1', name: '开心果');
      f.addSticker(id: 'kMid', seriesId: 's1', name: '不开心');

      final List<SearchHit> hits = f.run(const SearchQuery(text: '开心'));
      expect(hits.first.sticker.id, 'kPrefix');
    });

    test('标签越多不会导致分数膨胀（同字段只计一次）', () {
      final Fixture f = Fixture();
      f.addTag('t1', '可爱');
      f.addTag('t2', '可爱多');
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'k1', seriesId: 's1', name: '甲', tags: <String>['t1', 't2']);

      final List<SearchHit> hits = f.run(const SearchQuery(text: '可爱'));
      expect(hits.length, 1);
      // 单标签基准分(5.0) + 前缀奖励(2.0)，不因两个标签而翻倍。
      // Single-tag base (5.0) plus prefix bonus (2.0); not doubled by two tags.
      expect(hits.first.score, 7.0);
    });
  });

  group('搜索 - 结构化过滤', () {
    test('按标签 id 过滤', () {
      final Fixture f = Fixture();
      f.addTag('t1', '可爱');
      f.addTag('t2', '搞笑');
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'k1', seriesId: 's1', name: '甲', tags: <String>['t1']);
      f.addSticker(id: 'k2', seriesId: 's1', name: '乙', tags: <String>['t2']);

      final List<SearchHit> hits = f.run(
        const SearchQuery(text: '甲', tagIds: <String>{'t1'}),
      );
      expect(hits.length, 1);
      expect(hits.first.sticker.id, 'k1');
    });

    test('多标签过滤为 AND 语义', () {
      final Fixture f = Fixture();
      f.addTag('t1', '可爱');
      f.addTag('t2', '搞笑');
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'k1', seriesId: 's1', name: '甲', tags: <String>['t1']);
      f.addSticker(
        id: 'k2',
        seriesId: 's1',
        name: '乙',
        tags: <String>['t1', 't2'],
      );

      final List<SearchHit> hits = f.run(
        const SearchQuery(tagIds: <String>{'t1', 't2'}),
      );
      expect(hits.length, 1);
      expect(hits.first.sticker.id, 'k2');
    });

    test('限定系列范围', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '系列A');
      f.addSeries(id: 's2', name: '系列B');
      f.addSticker(id: 'k1', seriesId: 's1', name: '开心');
      f.addSticker(id: 'k2', seriesId: 's2', name: '开心');

      final List<SearchHit> hits = f.run(
        const SearchQuery(text: '开心', seriesId: 's2'),
      );
      expect(hits.length, 1);
      expect(hits.first.sticker.id, 'k2');
    });

    test('结构化过滤可单独使用（无文本）', () {
      final Fixture f = Fixture();
      f.addCategory('c1', '斗图');
      f.addSeries(id: 's1', name: '系列A', categories: <String>['c1']);
      f.addSticker(id: 'k1', seriesId: 's1', name: '甲');

      final List<SearchHit> hits = f.run(
        const SearchQuery(categoryIds: <String>{'c1'}),
      );
      expect(hits.length, 1);
    });
  });

  group('搜索 - 容错', () {
    test('已软删除的表情包不出现在结果中', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '系列A');
      final Sticker s = f.addSticker(id: 'k1', seriesId: 's1', name: '开心');
      f.stickerList[0] = s.copyWith(isDeleted: true);

      expect(f.run(const SearchQuery(text: '开心')), isEmpty);
    });

    test('系列缺失时仍能用表情包自身元数据搜到', () {
      final Fixture f = Fixture();
      // 不注册系列 s1，模拟父级缺失。
      // Do not register series s1, simulating a missing parent.
      f.addSticker(id: 'k1', seriesId: 's1', name: '孤儿表情', note: '独立备注');

      expect(f.run(const SearchQuery(text: '孤儿')).length, 1);
      expect(f.run(const SearchQuery(text: '独立')).length, 1);
    });

    test('指向已删除标签的 id 不会导致崩溃', () {
      final Fixture f = Fixture();
      f.addSeries(id: 's1', name: '系列A');
      f.addSticker(id: 'k1', seriesId: 's1', name: '甲', tags: <String>['ghost']);

      expect(f.run(const SearchQuery(text: '甲')).length, 1);
    });
  });
}
