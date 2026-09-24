import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/utils/path_utils.dart';
import '../../data/models/sticker.dart';

/// A single sticker thumbnail tile.
/// 单个表情包缩略图瓦片。
///
/// Decodes at [cacheWidth] rather than native size: a library of a few hundred
/// stickers otherwise holds far more decoded pixels in memory than the screen
/// can ever show.
///
/// 按 [cacheWidth] 解码而非原始尺寸：否则几百张表情包会占用远超屏幕所能显示的
/// 解码像素内存。
class StickerTile extends StatelessWidget {
  const StickerTile({
    Key? key,
    required this.sticker,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.cacheWidth = 300,
    this.borderRadius = 12,
  }) : super(key: key);

  final Sticker sticker;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final int cacheWidth;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String stored = sticker.thumbPath ?? sticker.relativePath;

    return Material(
      color: theme.colorScheme.onSurface.withOpacity(0.04),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withOpacity(0.08),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _StickerImage(storedPath: stored, cacheWidth: cacheWidth),
            if (selected)
              ColoredBox(color: theme.colorScheme.primary.withOpacity(0.18)),
          ],
        ),
      ),
    );
  }
}

/// Resolves a relative path then paints the file, degrading gracefully.
/// 解析相对路径后绘制文件，并优雅降级。
class _StickerImage extends StatelessWidget {
  const _StickerImage({required this.storedPath, required this.cacheWidth});

  final String storedPath;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Absolute path is synchronous once the root is known, so there is no
    // reason to put a FutureBuilder in the hot scroll path.
    // 一旦根目录已知，绝对路径的解析是同步的，
    // 因此没有理由在滚动热路径上放一个 FutureBuilder。
    final String absolute = PathUtils.absoluteSync(storedPath);

    return Image.file(
      File(absolute),
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      // A missing file is expected after a partial restore or a manual cleanup,
      // so show a placeholder instead of crashing the grid.
      // 部分恢复或手工清理后会缺少文件，因此显示占位而非让网格崩溃。
      errorBuilder: (_, __, ___) => Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 22,
          color: theme.colorScheme.onSurface.withOpacity(0.3),
        ),
      ),
    );
  }
}
