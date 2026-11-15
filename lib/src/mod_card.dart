import 'package:fluent_ui/fluent_ui.dart';

import 'app_theme.dart';

/// One horizontal record shared by Workshop results and installed Mods.
class ModListCard extends StatelessWidget {
  const ModListCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.metadata,
    required this.preview,
    required this.actions,
    required this.onDetails,
    this.status,
    this.warning = false,
  });
  final String title, subtitle, metadata;
  final Widget preview;
  final List<Widget> actions;
  final Widget? status;
  final VoidCallback onDetails;
  final bool warning;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = FluentTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0x08000000),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final information = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDetails,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 56, height: 56, child: preview),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: title,
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.typography.bodyStrong,
                              ),
                            ),
                          ),
                          if (status != null) ...[
                            const SizedBox(width: 8),
                            status!,
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: warning ? c.danger : c.secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        metadata,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.typography.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
          final actionRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                actions[i],
              ],
            ],
          );
          return constraints.maxWidth >= 570
              ? Row(
                  children: [
                    Expanded(child: information),
                    const SizedBox(width: 16),
                    actionRow,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    information,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: actionRow),
                  ],
                );
        },
      ),
    );
  }
}

String workshopExcerpt(String description) => description
    .replaceAll(RegExp(r'\[/?[^\]]+\]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
