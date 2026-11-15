import 'package:fluent_ui/fluent_ui.dart';

import 'rust/api.dart' as core;
import 'app_theme.dart';
import 'ui.dart';
import 'mod_details.dart';
import 'mod_card.dart';

class WorkshopView extends StatefulWidget {
  final bool visible;
  final core.Game? game;
  final List<core.LocalMod> mods;
  final void Function(String, String, [String]) onInstall;
  const WorkshopView({
    super.key,
    required this.visible,
    required this.game,
    required this.mods,
    required this.onInstall,
  });
  @override
  State<WorkshopView> createState() => _WorkshopViewState();
}

class _WorkshopViewState extends State<WorkshopView> {
  final input = TextEditingController();
  String query = '', error = '';
  int page = 1, serial = 0;
  bool loading = false, started = false;
  core.SearchPage? results;
  @override
  void didUpdateWidget(covariant WorkshopView old) {
    super.didUpdateWidget(old);
    if (widget.visible && !started) {
      started = true;
      search('', 1);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> search(String q, int p) async {
    final token = ++serial;
    setState(() {
      query = q;
      page = p;
      loading = true;
      error = '';
      results = null;
    });
    try {
      final res = await core.searchWorkshop(query: q, page: p);
      if (mounted && token == serial) setState(() => results = res);
    } catch (e) {
      if (mounted && token == serial) setState(() => error = '$e');
    } finally {
      if (mounted && token == serial) setState(() => loading = false);
    }
  }

  core.LocalMod? installed(String id) =>
      widget.mods.where((m) => m.itemId == id).firstOrNull;
  void install(core.WorkshopItem item) =>
      widget.onInstall(item.id, item.title, installed(item.id)?.folder ?? '');
  void details(core.WorkshopItem item) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      item.updated.toInt() * 1000,
    ).toLocal();
    final local = installed(item.id);
    showDialog<void>(
      context: context,
      builder: (ctx) => ModDetails(
        title: item.title,
        category: '创意工坊详情',
        previewUrl: item.preview,
        description: item.description,
        fields: [
          DetailField('工坊 ID', item.id),
          DetailField(
            '最近更新',
            item.updated.toInt() > 0
                ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
                : '未提供',
          ),
          DetailField('安装状态', local == null ? '尚未安装到当前游戏' : '已安装到当前游戏'),
          if (local != null) DetailField('包 ID', local.packageId),
        ],
        target: widget.game?.path,
        actionLabel: local == null ? '安装 Mod' : '更新 Mod',
        onAction: widget.game == null
            ? null
            : () {
                Navigator.pop(ctx);
                install(item);
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SearchField(
                  controller: input,
                  placeholder: '搜索 Mod 名称、工坊链接或 ID',
                  onSubmitted: (s) => search(s.trim(), 1),
                ),
              ),
              const SizedBox(width: 8),
              ActionButton.primary(
                onPressed: () => search(input.text.trim(), 1),
                child: const Text('搜索'),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: '上一页',
                child: IconButton(
                  onPressed: loading || page == 1
                      ? null
                      : () => search(query, page - 1),
                  icon: const Icon(FluentIcons.chevron_left, size: 16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('第 $page 页', style: t.typography.caption),
              ),
              Tooltip(
                message: '下一页',
                child: IconButton(
                  onPressed: loading || results?.hasNext != true
                      ? null
                      : () => search(query, page + 1),
                  icon: const Icon(FluentIcons.chevron_right, size: 16),
                ),
              ),
            ],
          ),
          TargetGame(
            path: widget.game?.path,
            label: '安装到',
            trailing: results == null ? null : '本页 ${results!.items.length} 项',
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: ProgressBar(),
            ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InfoBar(
                title: const Text('工坊查询失败'),
                content: Text(
                  error,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                severity: InfoBarSeverity.error,
                action: ActionButton(
                  onPressed: () => search(query, page),
                  child: const Text('重试'),
                ),
              ),
            ),
          Expanded(
            child: results == null
                ? const SizedBox.shrink()
                : results!.items.isEmpty
                ? const Center(child: Text('没有找到匹配的 Mod'))
                : ListView.separated(
                    key: ValueKey('$query/$page'),
                    primary: false,
                    itemCount: results!.items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = results!.items[index];
                      final local = installed(item.id);
                      final updated = DateTime.fromMillisecondsSinceEpoch(
                        item.updated.toInt() * 1000,
                      ).toLocal();
                      final date =
                          '${updated.year}-${updated.month.toString().padLeft(2, '0')}-${updated.day.toString().padLeft(2, '0')}';
                      final excerpt = workshopExcerpt(item.description);
                      return ModListCard(
                        key: ValueKey(item.id),
                        title: item.title,
                        subtitle: excerpt.isEmpty
                            ? '暂无 Mod 说明，可打开详情查看。'
                            : excerpt,
                        metadata:
                            '工坊 ID ${item.id}${item.updated.toInt() > 0 ? '  ·  更新于 $date' : ''}',
                        preview: ModPreview(url: item.preview),
                        status: local == null
                            ? null
                            : Text(
                                '已安装',
                                style: t.typography.caption?.copyWith(
                                  color: c.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                        onDetails: () => details(item),
                        actions: [
                          Tooltip(
                            message: '查看详情',
                            child: IconButton(
                              onPressed: () => details(item),
                              icon: const Icon(FluentIcons.info, size: 16),
                            ),
                          ),
                          ActionButton.primary(
                            onPressed: widget.game == null
                                ? null
                                : () => install(item),
                            child: Text(local == null ? '安装' : '更新'),
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
