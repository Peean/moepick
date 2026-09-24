import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/path_utils.dart';
import '../../../../data/models/category.dart';
import '../../../../data/models/series.dart';
import '../../../../data/models/sticker.dart';
import '../../../../data/models/tag.dart';
import '../../../library/application/library_providers.dart';

/// A cover tile for one series in the library grid.
/// 图库网格中单个系列的封面卡片。
class SeriesCard extends ConsumerWidget {
  const SeriesCard({
    Key? key,
    required this.series,
    required this.onTap,
  }) : super(key: key);

  final Series series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<Sticker> stickers =
        ref.watch(stickersBySeriesProvider(series.id));
    final Map<String, Category> categories = ref.watch(categoryByIdProvider);
    final Map<String, Tag> tags = ref.watch(tagByIdProvider);

    // Show up to three series-level tags/categories as chips.
    // 最多展示三个系列级标签/分类芯片。
    final List<Category> seriesCategories = series.categoryIds
        .map((String id) => categories[id])
        .whereType<Category>()
        .take(2)
        .toList();
    final List<Tag> seriesTags = series.tagIds
        .map((String id) => tags[id])
        .whereType<Tag>()
        .take(2)
        .toList();

    return Material(
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.onSurface.withOpacity(0.08),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Cover: nine-grid preview built from the first few stickers, which
            // is far more informative than a single image and needs no
            // generation step.
            // 封面：用前几张表情包拼成的九宫格预览，
            // 比单图信息量更大，且无需额外生成步骤。
            Expanded(
              child: _CoverPreview(
                series: series,
                stickers: stickers,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    series.name.isEmpty ? '未命名系列' : series.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    series.stickerCount > 0
                        ? '${series.stickerCount} 个表情包'
                        : (stickers.isEmpty ? '空系列' : '${stickers.length} 个表情包'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                      fontSize: 11,
                    ),
                  ),
                  if (seriesCategories.isNotEmpty || seriesTags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final Category c in seriesCategories)
                          _MiniChip(
                            label: c.name,
                            color: Color(c.colorValue),
                          ),
                        for (final Tag t in seriesTags)
                          _MiniChip(
                            label: t.name,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nine-grid style preview assembled from the series' stickers.
/// 由系列下表情包拼装的九宫格预览。
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.series, required this.stickers});

  final Series series;
  final List<Sticker> stickers;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color placeholder = theme.colorScheme.primary.withOpacity(0.07);

    if (series.coverImagePath != null &&
        series.coverImagePath!.isNotEmpty) {
      return _CoverFile(path: series.coverImagePath!);
    }

    if (stickers.isEmpty) {
      return Container(
        color: placeholder,
        child: Icon(
          Icons.image_outlined,
          size: 32,
          color: theme.colorScheme.primary.withOpacity(0.35),
        ),
      );
    }

    // Up to four tiles reads clearly at this size without turning to mush.
    // 最多四格：在该尺寸下清晰可辨，又不至于糊成一片。
    final List<Sticker> preview = stickers.take(4).toList();
    if (preview.length == 1) {
      return _StickerFile(sticker: preview.first);
    }

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 1.5,
        mainAxisSpacing: 1.5,
      ),
      itemCount: preview.length.clamp(2, 4),
      itemBuilder: (BuildContext context, int index) {
        if (index >= preview.length) return ColoredBox(color: placeholder);
        return _StickerFile(sticker: preview[index]);
      },
    );
  }
}

/// Renders a sticker's thumbnail (or original when no thumbnail exists).
/// 渲染表情包的缩略图（无缩略图时用原图）。
class _StickerFile extends StatelessWidget {
  const _StickerFile({required this.sticker});

  final Sticker sticker;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String relative = sticker.thumbPath ?? sticker.relativePath;

    return FutureBuilder<String>(
      future: PathUtils.absolute(relative),
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        final String? path = snapshot.data;
        if (path == null) {
          return ColoredBox(
            color: theme.colorScheme.primary.withOpacity(0.05),
          );
        }
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          // Decode at display size: a full-resolution decode per grid tile is
          // the classic cause of janky scrolling on mid-range devices.
          // 按展示尺寸解码：每个网格项都全分辨率解码是中端设备滚动卡顿的经典原因。
          cacheWidth: 300,
          errorBuilder: (_, __, ___) => ColoredBox(
            color: theme.colorScheme.primary.withOpacity(0.05),
            child: Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
        );
      },
    );
  }
}

/// Renders a series cover image file.
/// 渲染系列封面图片文件。
class _CoverFile extends StatelessWidget {
  const _CoverFile({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: PathUtils.absolute(path),
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        final String? abs = snapshot.data;
        if (abs == null) return const SizedBox.expand();
        return Image.file(
          File(abs),
          fit: BoxFit.cover,
          cacheWidth: 400,
          errorBuilder: (_, __, ___) => const SizedBox.expand(),
        );
      },
    );
  }
}

/// Compact label chip used on series cards.
/// 系列卡片上使用的紧凑标签芯片。
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, color: color, height: 1.3),
      ),
    );
  }
}
