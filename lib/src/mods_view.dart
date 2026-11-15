import 'package:fluent_ui/fluent_ui.dart';

import '../main.dart' show askText, confirm;
import 'app_theme.dart';
import 'ui.dart';
import 'mod_details.dart';
import 'rust/api.dart' as core;
import 'load_order_view.dart';
import 'mod_card.dart';

class ModsView extends StatefulWidget {
  final core.Game? game;
  final List<core.LocalMod> mods;
  final void Function(String, String, [String]) onInstall;
  final Future<void> Function() onRefresh, onChanged;
  final void Function(String) onError;
  final bool showOrder;
  final VoidCallback? onOrderClosed;
  const ModsView({
    super.key,
    required this.game,
    required this.mods,
    required this.onInstall,
    required this.onRefresh,
    required this.onChanged,
    required this.onError,
    this.showOrder = false,
    this.onOrderClosed,
  });
  @override
  State<ModsView> createState() => _ModsViewState();
}

class _ModsViewState extends State<ModsView> {
  String query = '';
  Future<void> edit(core.LocalMod m, bool remove) async {
    final game = widget.game;
    if (game == null) return;
    try {
      if (remove) {
        if (!await confirm(
          context,
          '卸载 ${m.name}？',
          '目标游戏\n${game.path}\n\n将移除以下 Mod 目录\n${m.path}',
          '卸载',
        )) {
          return;
        }
        await core.uninstallMod(game: game.path, folder: m.folder);
      } else {
        final id = await askText(context, '关联 ${m.name}', '创意工坊数字 ID', '');
        if (id == null) return;
        await core.linkMod(game: game.path, folder: m.folder, itemId: id);
      }
      await widget.onChanged();
    } catch (e) {
      widget.onError('$e');
    }
  }

  void details(core.LocalMod m) => showDialog<void>(
    context: context,
    builder: (ctx) => ModDetails(
      title: m.name,
      category: '本地 Mod 详情',
      fields: [
        DetailField('作者', m.author),
        DetailField('支持版本', m.versions),
        DetailField('包 ID', m.packageId),
        DetailField('工坊 ID', m.itemId.isEmpty ? '未关联' : m.itemId),
        DetailField('安装目录', m.path),
      ],
      issue: m.issue,
      target: widget.game?.path,
      actionLabel: m.itemId.isNotEmpty && m.issue.isEmpty ? '更新 Mod' : null,
      onAction: widget.game == null
          ? null
          : () {
              Navigator.pop(ctx);
              widget.onInstall(m.itemId, m.name, m.folder);
            },
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (widget.showOrder && widget.game != null) {
      return LoadOrderView(
        game: widget.game!,
        onBack: widget.onOrderClosed ?? () {},
        showBack: false,
      );
    }
    final c = AppColors.of(context);
    final items = widget.mods
        .where(
          (m) => [
            m.name,
            m.author,
            m.packageId,
            m.itemId,
          ].any((s) => s.toLowerCase().contains(query)),
        )
        .toList();
    final version = widget.game?.version.split('.').take(2).join('.') ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SearchField(
                  placeholder: '筛选名称、作者、包 ID 或工坊 ID',
                  onChanged: (s) =>
                      setState(() => query = s.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '刷新列表',
                child: IconButton(
                  onPressed: widget.onRefresh,
                  icon: const Icon(FluentIcons.refresh, size: 16),
                ),
              ),
            ],
          ),
          TargetGame(
            path: widget.game?.path,
            trailing: '${items.length} 个 Mod',
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(query.isEmpty ? '当前没有本地 Mod' : '没有匹配的 Mod'),
                  )
                : ListView.separated(
                    primary: false,
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final m = items[index];
                      final declared = m.versions.split(RegExp(r'[、,\s]+'));
                      final mismatch =
                          version.isNotEmpty &&
                          m.versions.isNotEmpty &&
                          !declared.contains(version);
                      final compatibility = m.versions.isEmpty
                          ? '未声明支持版本'
                          : mismatch
                          ? '未声明支持 $version'
                          : '支持 $version';
                      return ModListCard(
                        key: ValueKey(m.path),
                        title: m.name,
                        subtitle: m.issue.isNotEmpty
                            ? m.issue
                            : [
                                if (m.author.isNotEmpty) m.author,
                                compatibility,
                              ].join('  ·  '),
                        metadata:
                            '${m.packageId.isEmpty ? m.folder : m.packageId}  ·  ${m.itemId.isEmpty ? '本地来源' : '创意工坊 ${m.itemId}'}',
                        preview: ModPreview(
                          localPath: '${m.path}/About/preview.png',
                        ),
                        warning: m.issue.isNotEmpty || mismatch,
                        onDetails: () => details(m),
                        actions: [
                          Tooltip(
                            message: '查看详情',
                            child: IconButton(
                              onPressed: () => details(m),
                              icon: const Icon(FluentIcons.info, size: 16),
                            ),
                          ),
                          ActionButton(
                            onPressed: m.issue.isNotEmpty
                                ? null
                                : m.itemId.isEmpty
                                ? () => edit(m, false)
                                : () => widget.onInstall(
                                    m.itemId,
                                    m.name,
                                    m.folder,
                                  ),
                            child: Text(m.itemId.isEmpty ? '关联 ID' : '更新'),
                          ),
                          Tooltip(
                            message: '卸载 Mod',
                            child: IconButton(
                              onPressed: () => edit(m, true),
                              icon: Icon(
                                FluentIcons.delete,
                                size: 16,
                                color: c.danger,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
