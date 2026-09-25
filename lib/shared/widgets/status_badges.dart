import 'package:flutter/material.dart';

/// Overlaid pin / favourite badges for series cards and sticker tiles, so the
/// status is visible at a glance without opening the item or long-pressing it.
/// 系列卡片与表情包瓦片上的置顶 / 收藏角标叠加层，
/// 使状态一眼可见，无需点进条目或长按查看。
///
/// Drawn as small circular chips on a dark scrim so they stay legible over any
/// artwork: a white pin for pinned, an amber star for favourited.
/// 以深色衬底上的小圆片呈现，在任何封面上都清晰可辨：
/// 置顶为白色图钉，收藏为琥珀色星星。
class StatusBadges extends StatelessWidget {
  const StatusBadges({
    Key? key,
    required this.pinned,
    required this.favorite,
  }) : super(key: key);

  final bool pinned;
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    if (!pinned && !favorite) return const SizedBox.shrink();

    final List<Widget> badges = <Widget>[];
    if (pinned) {
      badges.add(_badge(Icons.push_pin, Colors.white));
    }
    if (favorite) {
      if (badges.isNotEmpty) badges.add(const SizedBox(width: 4));
      badges.add(_badge(Icons.star_rounded, const Color(0xFFFFC94D)));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: badges);
  }

  Widget _badge(IconData icon, Color color) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 13, color: color),
    );
  }
}
