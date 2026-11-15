import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import 'dart:io';

import 'app_theme.dart';
import 'menu_motion.dart';

const controlHeight = 30.0;

/// A single shared underline moves independently of the menu labels.
class LauncherTopMenuBar extends StatelessWidget {
  const LauncherTopMenuBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.widths = const [72, 96, 110, 72],
  }) : assert(labels.length == widths.length);
  final List<String> labels;
  final List<double> widths;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widths.fold<double>(0, (total, width) => total + width),
    height: 44,
    child: Stack(
      children: [
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              LauncherMenuItem(
                key: ValueKey('top-menu-$i'),
                label: labels[i],
                selected: selected == i,
                top: true,
                width: widths[i],
                onPressed: () {
                  if (selected != i) onSelected(i);
                },
              ),
          ],
        ),
        StretchMenuIndicator(
          target: Rect.fromLTWH(
            widths
                .take(selected)
                .fold<double>(0, (total, width) => total + width),
            42,
            widths[selected],
            2,
          ),
          markerKey: const ValueKey('top-menu-indicator'),
          color: AppColors.of(context).accent,
        ),
      ],
    ),
  );
}

class LauncherSideMenuBar extends StatelessWidget {
  const LauncherSideMenuBar({
    super.key,
    required this.title,
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onSelected,
    required this.menuKeyPrefix,
    required this.tasksSelected,
    required this.tasksLabel,
    required this.onTasks,
    this.footer,
  });
  final String title, menuKeyPrefix, tasksLabel;
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final bool tasksSelected;
  final ValueChanged<int> onSelected;
  final VoidCallback onTasks;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    title,
                    style: FluentTheme.of(context).typography.bodyStrong,
                  ),
                ),
              ),
            ),
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              LauncherMenuItem(
                key: ValueKey('$menuKeyPrefix-$i'),
                label: labels[i],
                icon: icons[i],
                width: bounds.maxWidth,
                selected: !tasksSelected && selected == i,
                onPressed: () {
                  if (tasksSelected || selected != i) onSelected(i);
                },
              ),
            ],
            const Spacer(),
            ?footer,
            Container(height: 1, color: AppColors.of(context).border),
            const SizedBox(height: 8),
            LauncherMenuItem(
              key: const ValueKey('side-menu-tasks'),
              label: tasksLabel,
              icon: FluentIcons.download,
              width: bounds.maxWidth,
              selected: tasksSelected,
              onPressed: () {
                if (!tasksSelected) onTasks();
              },
            ),
          ],
        ),
        StretchMenuIndicator(
          target: Rect.fromLTWH(
            0,
            tasksSelected ? bounds.maxHeight - 36 : 40 + selected * 40,
            3,
            36,
          ),
          markerKey: const ValueKey('side-menu-indicator'),
          color: AppColors.of(context).accent,
        ),
      ],
    ),
  );
}

/// Navigation has no outline; the selected edge identifies the current page.
class LauncherMenuItem extends StatelessWidget {
  const LauncherMenuItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
    this.top = false,
    this.width = 136,
  });
  final String label;
  final bool selected, top;
  final VoidCallback onPressed;
  final IconData? icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: width,
          height: top ? 44 : 36,
          child: HoverButton(
            onPressed: onPressed,
            builder: (context, states) => Container(
              key: const ValueKey('menu-item-surface'),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected && !top ? c.selection : Colors.transparent,
              ),
              foregroundDecoration: states.isFocused
                  ? BoxDecoration(border: Border.all(color: c.secondary))
                  : null,
              child: SizedBox(
                width: width - 28,
                child: Row(
                  mainAxisAlignment: top
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 14,
                        color: selected ? c.accent : c.secondary,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          inherit: false,
                          fontFamily: 'Segoe UI',
                          color: selected ? c.accent : c.secondary,
                          fontSize: 13,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppWindowChrome extends StatelessWidget {
  const AppWindowChrome({super.key, required this.child, this.menu});
  final Widget child;
  final Widget? menu;
  static const channel = MethodChannel('rimworld_launcher/appearance');
  Future<void> command(String method) async {
    try {
      await channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Flutter widget tests run without the Windows host.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget draggable(Widget child) => Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.buttons == 1) command('drag');
      },
      child: child,
    );
    Widget windowControl(
      String label,
      String key,
      IconData icon,
      String method,
    ) => Tooltip(
      message: label,
      child: SizedBox(
        width: 40,
        height: 44,
        child: IconButton(
          key: ValueKey(key),
          style: ButtonStyle(
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(side: BorderSide.none),
            ),
            backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            foregroundColor: WidgetStatePropertyAll(c.secondary),
          ),
          icon: Icon(icon, size: 14),
          onPressed: () => command(method),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border.all(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          children: [
            Container(
              height: 44,
              color: c.sidebar,
              child: Row(
                children: [
                  draggable(
                    SizedBox(
                      width: 156,
                      height: 44,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Row(
                          children: [
                            Icon(FluentIcons.globe, size: 15, color: c.accent),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'RimWorld',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: c.text),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ?menu,
                  Expanded(
                    child: draggable(
                      const SizedBox(height: 44, width: double.infinity),
                    ),
                  ),
                  windowControl(
                    '最小化',
                    'window-minimize',
                    FluentIcons.chrome_minimize,
                    'minimize',
                  ),
                  windowControl(
                    '关闭应用',
                    'window-close',
                    FluentIcons.chrome_close,
                    'close',
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.minimumWidth = 96,
  }) : primary = false;
  const ActionButton.primary({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.minimumWidth = 96,
  }) : primary = true;
  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;
  final bool primary;
  final double minimumWidth;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final label = DefaultTextStyle(
      style: FluentTheme.of(context).typography.body!.copyWith(
        fontSize: 13,
        height: 1,
        fontWeight: FontWeight.w500,
        color: onPressed == null
            ? c.secondary
            : primary
            ? c.onAccent
            : c.text,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      child: child,
    );
    return SizedBox(
      width: minimumWidth,
      height: controlHeight,
      child: primary
          ? FilledButton(onPressed: onPressed, style: style, child: label)
          : Button(onPressed: onPressed, style: style, child: label),
    );
  }
}

String? officialContentLabel(String id, String source) {
  if (source != '游戏本体 / DLC') return null;
  if (id == 'ludeon.rimworld') return '游戏本体';
  return id.startsWith('ludeon.rimworld.') ? '官方 DLC' : null;
}

class OfficialContentBadge extends StatelessWidget {
  const OfficialContentBadge(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dlc = label == '官方 DLC';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: dlc ? c.officialBackground : c.selection,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.shield,
            size: 12,
            color: dlc ? c.officialText : c.accent,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: dlc ? c.officialText : c.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.placeholder,
    this.controller,
    this.onChanged,
    this.onSubmitted,
  });
  final String placeholder;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged, onSubmitted;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: controlHeight,
    child: TextBox(
      decoration: inputDecoration(context),
      controller: controller,
      placeholder: placeholder,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: TextStyle(
        color: AppColors.of(context).text,
        fontSize: 14,
        height: 1.2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      prefix: Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Icon(
          FluentIcons.search,
          size: 15,
          color: AppColors.of(context).secondary,
        ),
      ),
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.selected = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: selected ? c.accent : c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class StatusLabel extends StatelessWidget {
  const StatusLabel(this.text, {super.key, this.selected = false});
  final String text;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? c.selection : c.elevated,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: selected ? c.accent : c.secondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ModPreview extends StatelessWidget {
  const ModPreview({
    super.key,
    this.url = '',
    this.localPath,
    this.contain = false,
  });
  final String url;
  final String? localPath;
  final bool contain;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fallback = ColoredBox(
      color: c.elevated,
      child: Center(
        child: Icon(FluentIcons.packages, size: 36, color: c.secondary),
      ),
    );
    return ColoredBox(
      color: c.elevated,
      child: localPath != null
          ? Image.file(
              File(localPath!),
              fit: contain ? BoxFit.contain : BoxFit.cover,
              errorBuilder: (context, error, stack) => fallback,
            )
          : url.isEmpty
          ? fallback
          : Image.network(
              url,
              fit: contain ? BoxFit.contain : BoxFit.cover,
              errorBuilder: (context, error, stack) => fallback,
            ),
    );
  }
}

class TargetGame extends StatelessWidget {
  const TargetGame({
    super.key,
    required this.path,
    this.label = '当前游戏',
    this.trailing,
  });
  final String? path;
  final String label;
  final String? trailing;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(FluentIcons.folder_open, size: 14, color: c.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: path ?? '请在首页选择游戏',
              child: Text(
                path == null ? '请在首页选择游戏' : '$label  ·  $path',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FluentTheme.of(context).typography.caption,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Text(trailing!, style: FluentTheme.of(context).typography.caption),
          ],
        ],
      ),
    );
  }
}
