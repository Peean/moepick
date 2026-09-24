import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_settings.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../application/settings_providers.dart';

/// Theme picker: accent colour, light/dark behaviour, and grid density.
/// 主题设置：主色、明暗行为与网格密度。
///
/// Every control writes straight through to the persisted settings and the
/// theme rebuilds from the provider, so there is no "apply" step and no local
/// draft state to drift out of sync.
///
/// 每个控件直接写入已持久化的设置，主题从 provider 重建，
/// 因此没有「应用」步骤，也不存在会失同步的本地草稿状态。
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(appSettingsProvider);
    final AppSettingsNotifier notifier =
        ref.read(appSettingsProvider.notifier);

    return MoeScaffold(
      appBar: AppBar(
        title: const Text('主题色'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RoutePaths.settings),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          const SectionHeader(
            '主色',
            subtitle: '整个界面的强调色由此生成',
          ),
          _PresetGrid(
            selectedValue: settings.seedColorValue,
            onSelected: notifier.setSeedColor,
          ),

          const SectionHeader('明暗模式'),
          _ChoiceCard(
            options: <_Choice>[
              _Choice(
                label: '跟随系统',
                description: '随系统设置自动切换',
                selected: settings.followSystemTheme,
                onTap: () => notifier.setFollowSystemTheme(true),
              ),
              _Choice(
                label: '浅色',
                description: '始终使用浅色界面',
                selected:
                    !settings.followSystemTheme && !settings.useDarkMode,
                onTap: () => notifier.setDarkMode(false),
              ),
              _Choice(
                label: '深色',
                description: '始终使用深色界面',
                selected: !settings.followSystemTheme && settings.useDarkMode,
                onTap: () => notifier.setDarkMode(true),
              ),
            ],
          ),

          const SectionHeader(
            '列表密度',
            subtitle: '影响表情包网格的列数与卡片留白',
          ),
          _StepperCard(
            label: '每行列数',
            value: '${settings.gridColumns}',
            canDecrease: settings.gridColumns > 2,
            canIncrease: settings.gridColumns < 6,
            onDecrease: () =>
                notifier.setGridColumns(settings.gridColumns - 1),
            onIncrease: () =>
                notifier.setGridColumns(settings.gridColumns + 1),
          ),
          const SizedBox(height: 10),
          _SwitchCard(
            label: '紧凑卡片',
            description: '减小卡片内边距，同屏显示更多内容',
            value: settings.compactCards,
            onChanged: notifier.setCompactCards,
          ),

          const SizedBox(height: 20),
          _PreviewStrip(seedColorValue: settings.seedColorValue),
        ],
      ),
    );
  }
}

/// The preset swatch grid, laid out with a fixed column count so swatches do
/// not stretch awkwardly on wide desktop windows.
/// 预设色块网格，使用固定列数，避免在宽桌面窗口上被拉伸得难看。
class _PresetGrid extends StatelessWidget {
  const _PresetGrid({required this.selectedValue, required this.onSelected});

  final int selectedValue;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<Widget> swatches = buildPresetSwatches(
      context: context,
      selectedValue: selectedValue,
      onSelected: onSelected,
    );

    return MoeCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        runAlignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 14,
        children: swatches,
      ),
    );
  }
}

/// One radio-style row.
/// 单条单选行。
class _Choice {
  const _Choice({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.options});

  final List<_Choice> options;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return MoeCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < options.length; i++) ...<Widget>[
            if (i > 0) Divider(color: theme.colorScheme.onSurface.withOpacity(0.08)),
            InkWell(
              onTap: options[i].onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      options[i].selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: options[i].selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.35),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            options[i].label,
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (options[i].description.isNotEmpty)
                            Text(
                              options[i].description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A label plus a minus/plus stepper.
/// 标签加减号/加号步进器。
class _StepperCard extends StatelessWidget {
  const _StepperCard({
    required this.label,
    required this.value,
    required this.canDecrease,
    required this.canIncrease,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final String value;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return MoeCard(
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          IconButton(
            onPressed: canDecrease ? onDecrease : null,
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: '减少',
          ),
          SizedBox(
            width: 32,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          IconButton(
            onPressed: canIncrease ? onIncrease : null,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '增加',
          ),
        ],
      ),
    );
  }
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
                if (description.isNotEmpty)
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

/// A row of component previews so the effect of the accent colour is visible
/// without leaving the screen.
/// 一排组件预览，使主色的效果无需离开本页即可看到。
class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({required this.seedColorValue});

  final int seedColorValue;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = AppTheme.build(
      seedColor: Color(seedColorValue),
      brightness: Theme.of(context).brightness,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader('预览'),
        Theme(
          data: theme,
          child: MoeCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '效果预览',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('主要按钮'),
                    ),
                    const SizedBox(width: 10),
                    TextButton(onPressed: () {}, child: const Text('次要操作')),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    Chip(label: const Text('可爱'), backgroundColor: theme.colorScheme.primary.withOpacity(0.12)),
                    Chip(
                      label: const Text('日常'),
                      backgroundColor: theme.colorScheme.secondary.withOpacity(0.14),
                    ),
                    Chip(label: const Text('表情包'), backgroundColor: theme.colorScheme.surface),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
