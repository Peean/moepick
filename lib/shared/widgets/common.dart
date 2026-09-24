import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Whether a [BuildContext] is still safe to use after an `await`.
/// 判断一次 `await` 之后 [BuildContext] 是否仍然可用。
///
/// `BuildContext.mounted` only arrived in Flutter 3.4 and this project targets
/// 3.0, so liveness has to be probed through the render object instead.
///
/// `BuildContext.mounted` 到 Flutter 3.4 才出现，而本项目基于 3.0，
/// 因此只能借助 render object 来探测存活性。
///
/// Two subtleties make the obvious implementation wrong, and both were
/// confirmed against the Flutter 3.0 sources rather than assumed:
///
/// 两处细节会让最直观的写法出错，且二者都是查阅 Flutter 3.0 源码确认的，
/// 而非凭推测：
///
/// 1. In **debug** builds `findRenderObject()` on a deactivated element does not
///    return null — it throws `Cannot get renderObject of inactive element.`
///    The throw sits inside an `assert`, so it is compiled out of release
///    builds, where the same call *does* return null. Hence both a `try` and a
///    null check are needed; either alone is correct in only one build mode.
///
/// 1. 在 **debug** 构建中，对已 deactivate 的 element 调用 `findRenderObject()`
///    不会返回 null，而是抛出 `Cannot get renderObject of inactive element.`。
///    该抛出位于 `assert` 内部，在 release 构建中会被编译掉，此时同一调用确实
///    返回 null。因此 `try` 与判空两者都不可少；只留其一会只在一种构建模式下正确。
///
/// 2. `RenderObjectBounds`-style helpers are not enough on their own: a render
///    object can be non-null yet detached mid-teardown, and touching a detached
///    (or defunct, when `debugDisposed` is on) render object throws. Checking
///    `attached` is what makes the guard safe rather than merely non-null.
///
/// 2. 仅靠判空并不够：render object 可能非空但已在拆除途中脱离树，而访问脱离的
///    （或开启 `debugDisposed` 后已 defunct 的）render object 会抛异常。正是
///    `attached` 这一检查让守卫真正安全，而不只是非空。
///
/// The analyzer's `use_build_context_synchronously` cannot see through this
/// helper (it only special-cases the literal name `mounted`), so call sites add
/// a targeted `// ignore:` that points back here.
///
/// 分析器的 `use_build_context_synchronously` 无法看穿这个辅助函数（它只对字面量
/// 名 `mounted` 特判），因此各调用点会加上指向本处的针对性 `// ignore:`。
bool contextIsAlive(BuildContext context) {
  try {
    final RenderObject? renderObject = context.findRenderObject();
    return renderObject != null && renderObject.attached;
  } catch (_) {
    // Debug-only path: the element is deactivated (or defunct). Safe to treat
    // as gone, which is exactly what the caller wants to know.
    // 仅 debug 路径：element 已 deactivate（或 defunct）。视为已消失是安全的，
    // 而这正是调用方想知道的。
    return false;
  }
}

/// Friendly empty-state placeholder.
/// 友好的空状态占位组件。
class EmptyState extends StatelessWidget {
  const EmptyState({
    Key? key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  }) : super(key: key);

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.10),
              ),
              child: Icon(
                icon,
                size: 40,
                color: theme.colorScheme.primary.withOpacity(0.85),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  height: 1.5,
                ),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Small colour dot used to hint a category's colour.
/// 用于提示分类颜色的小圆点。
class CategoryDot extends StatelessWidget {
  const CategoryDot({Key? key, required this.color, this.size = 8})
      : super(key: key);

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// A confirmation dialog matching the app's visual language.
/// 与应用视觉语言一致的确认对话框。
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) {
      final ThemeData theme = Theme.of(context);
      return AlertDialog(
        title: Text(title),
        content: markdownText(message, style: const TextStyle(height: 1.5)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              primary: destructive ? theme.colorScheme.error : null,
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Show a transient message.
/// 展示短暂的提示信息。
void showToast(BuildContext context, String message, {bool isError = false}) {
  final ThemeData theme = Theme.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? theme.colorScheme.error : theme.colorScheme.onSurface,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
}

/// Render [source] with minimal inline Markdown: `**bold**` spans become bold.
/// 以最小内联 Markdown 渲染 [source]：`**加粗**` 片段呈现为粗体。
///
/// Deliberately NOT a full Markdown renderer — just the one construct the
/// confirmation dialogs need, so `confirm(message: '...**替换**...')` reads
/// correctly instead of leaking the asterisks into the UI.
///
/// 刻意不是完整的 Markdown 渲染器——只实现确认对话框需要的这一种语法，
/// 使 `confirm(message: '...**替换**...')` 能正确显示，而不是把星号泄漏到界面上。
Widget markdownText(String source, {TextStyle? style}) {
  final List<TextSpan> spans = <TextSpan>[];
  final RegExp bold = RegExp(r'\*\*(.+?)\*\*');
  int cursor = 0;
  for (final RegExpMatch match in bold.allMatches(source)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: source.substring(cursor, match.start)));
    }
    spans.add(TextSpan(
      text: match.group(1),
      style: const TextStyle(fontWeight: FontWeight.w700),
    ));
    cursor = match.end;
  }
  if (cursor < source.length) {
    spans.add(TextSpan(text: source.substring(cursor)));
  }
  return Text.rich(TextSpan(style: style, children: spans));
}

/// A saturated accent derived from the current theme, for tag/category chips.
/// 从当前主题派生的高饱和强调色，用于标签与分类芯片。
Color accentOf(BuildContext context) => Theme.of(context).colorScheme.primary;

/// Convenience for a translucent version of the theme's surface.
/// 主题表面色的半透明版本的便捷方法。
Color translucentSurface(BuildContext context, double opacity) =>
    Theme.of(context).colorScheme.surface.withOpacity(opacity);

/// Prompt for a single line of text.
/// 询问单行文本。
///
/// Generic counterpart to the series name prompt: the same shape is needed for
/// categories and tags, and duplicating the dialog three times would guarantee
/// they drift apart.
///
/// 系列名输入框的通用版本：分类与标签需要同样的形态，
/// 复制三份对话框必然会逐渐走样。
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirmLabel = '创建',
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => _TextPromptDialog(
      title: title,
      initial: initial,
      hint: hint,
      confirmLabel: confirmLabel,
    ),
  );
}

/// The dialog behind [promptForText].
/// [promptForText] 背后的对话框。
///
/// The [TextEditingController] is owned by this widget's `State` rather than by
/// the calling function, and this is not a style preference — it is the fix for
/// a real crash.
///
/// The obvious implementation creates the controller in the calling function and
/// disposes it with `.whenComplete(controller.dispose)`. That runs as soon as the
/// dialog's route future completes, which is when `Navigator.pop` is called —
/// *before* the exit transition has finished and while the `TextField` and its
/// `InputDecorator` are still mounted and still listening. Disposing a
/// `ChangeNotifier` that still has listeners is a debug assertion
/// ("A TextEditingController was used after being disposed", followed by
/// "Tried to build dirty widget in the wrong build scope" and an
/// `_dependents.isEmpty` failure as the framework tears down a tree it believes
/// is gone). The dialog looks like it closed cleanly, and the crash lands on the
/// *next* interaction instead — which makes it read as a routing or theme bug.
///
/// Tying the controller to `State.dispose` guarantees it outlives every listener,
/// because `dispose` runs only once the element is genuinely unmounted.
///
/// [TextEditingController] 由本组件的 `State` 持有，而非调用方函数——这不是风格偏
/// 好，而是对一个真实崩溃的修复。
///
/// 直觉写法是在调用方函数里创建 controller，并用 `.whenComplete(controller.dispose)`
/// 释放。但该回调在对话框路由 future 完成时即触发，也就是 `Navigator.pop` 被调用的
/// 那一刻——**此时退场动画尚未结束，`TextField` 与其 `InputDecorator` 仍挂载、仍持有
/// 监听**。释放一个仍带监听者的 `ChangeNotifier` 会触发 debug 断言
/// （"A TextEditingController was used after being disposed"，随后是
/// "Tried to build dirty widget in the wrong build scope"，以及框架拆解它以为已消失的
/// 树时的 `_dependents.isEmpty` 失败）。对话框看起来是正常关闭的，崩溃却落在**下一次
/// 交互**上，因此极易被误读为路由或主题 bug。
///
/// 把 controller 绑定到 `State.dispose` 可保证它比所有监听者活得更久，
/// 因为 `dispose` 只在 element 真正卸载后才执行。
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final String hint;
  final String confirmLabel;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration:
            InputDecoration(hintText: widget.hint.isEmpty ? null : widget.hint),
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// A menu item styled as a destructive action, matching the red buttons used
/// elsewhere for delete operations. Keeps the overflow-menu "delete" entries
/// consistent with the inline delete buttons.
/// 以「危险操作」样式呈现的菜单项，与应用其他地方删除按钮所用的红色一致。
/// 使溢出菜单中的「删除」项与内联删除按钮风格统一。
class DestructiveMenuItem extends StatelessWidget {
  const DestructiveMenuItem({
    Key? key,
    required this.icon,
    required this.label,
  }) : super(key: key);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color error = Theme.of(context).colorScheme.error;
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: error),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: error),
        ),
      ],
    );
  }
}

/// Theme preset swatch row, reused by the theme picker.
/// 主题预设色块行，供主题选择器复用。
List<Widget> buildPresetSwatches({
  required BuildContext context,
  required int selectedValue,
  required ValueChanged<int> onSelected,
}) {
  return AppTheme.presets.map((ThemePreset preset) {
    final bool selected = preset.colorValue == selectedValue;
    return GestureDetector(
      onTap: () => onSelected(preset.colorValue),
      child: Column(
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: preset.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: selected
                ? Icon(
                    Icons.check,
                    size: 22,
                    color: preset.color.computeLuminance() > 0.55
                        ? Colors.black87
                        : Colors.white,
                  )
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            preset.label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }).toList();
}
