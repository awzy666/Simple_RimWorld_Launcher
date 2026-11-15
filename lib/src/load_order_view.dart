import 'package:fluent_ui/fluent_ui.dart';

import 'app_theme.dart';
import 'ui.dart';
import 'rust/api.dart' as core;

class LoadOrderView extends StatefulWidget {
  const LoadOrderView({
    super.key,
    required this.game,
    required this.onBack,
    this.showBack = true,
  });
  final core.Game game;
  final VoidCallback onBack;
  final bool showBack;
  @override
  State<LoadOrderView> createState() => _LoadOrderViewState();
}

class _LoadOrderViewState extends State<LoadOrderView> {
  core.ModOrder? snapshot;
  List<String> active = [], problems = [], warnings = [];
  String filter = '', notice = '';
  bool busy = false, dirty = false;
  int requestSerial = 0;
  @override
  void initState() {
    super.initState();
    read();
  }

  @override
  void didUpdateWidget(covariant LoadOrderView old) {
    super.didUpdateWidget(old);
    if (old.game.path != widget.game.path) {
      snapshot = null;
      active = [];
      read();
    }
  }

  Future<void> read() async {
    final token = ++requestSerial;
    setState(() {
      busy = true;
      notice = '';
    });
    final path = widget.game.path;
    try {
      final data = await core.modOrder(game: path);
      if (!mounted || token != requestSerial) return;
      setState(() {
        snapshot = data;
        active = [...data.active];
        warnings = data.warnings;
        problems = [];
        dirty = false;
      });
    } catch (e) {
      if (mounted && token == requestSerial) setState(() => notice = '$e');
    } finally {
      if (mounted && token == requestSerial) setState(() => busy = false);
    }
  }

  Future<void> organize() async {
    final token = ++requestSerial;
    setState(() {
      busy = true;
      notice = '';
    });
    try {
      final result = await core.organizeMods(
        game: widget.game.path,
        active: active,
        sort: true,
      );
      if (!mounted || token != requestSerial) return;
      setState(() {
        active = result.active;
        problems = result.problems;
        warnings = result.warnings;
        dirty = true;
        if (problems.isEmpty) notice = '已按依赖与先后规则排序，保存后应用到游戏。';
      });
    } catch (e) {
      if (mounted && token == requestSerial) setState(() => notice = '$e');
    } finally {
      if (mounted && token == requestSerial) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final token = ++requestSerial;
    setState(() {
      busy = true;
      notice = '';
    });
    try {
      final result = await core.saveModOrder(
        game: widget.game.path,
        active: active,
        revision: snapshot!.revision,
      );
      if (!mounted || token != requestSerial) return;
      setState(() {
        snapshot = result;
        active = [...result.active];
        problems = [];
        warnings = result.warnings;
        dirty = false;
        notice = '已保存加载顺序。原配置已备份。';
      });
    } catch (e) {
      if (mounted && token == requestSerial) setState(() => notice = '$e');
    } finally {
      if (mounted && token == requestSerial) setState(() => busy = false);
    }
  }

  void change(VoidCallback edit) => setState(() {
    edit();
    dirty = true;
    problems = [];
    warnings = [];
    notice = '';
  });
  String name(String id) =>
      snapshot!.mods.where((m) => m.id == id).firstOrNull?.name ?? '$id（未找到）';
  String? officialLabel(String id) {
    final mod = snapshot!.mods.where((m) => m.id == id).firstOrNull;
    return mod == null ? null : officialContentLabel(mod.id, mod.source);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = FluentTheme.of(context);
    final data = snapshot;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.showBack)
                ActionButton(
                  onPressed: widget.onBack,
                  child: const Text('返回文件管理'),
                ),
              ActionButton(
                onPressed: busy ? null : read,
                child: const Text('重新读取'),
              ),
              ActionButton(
                onPressed: busy || data == null ? null : organize,
                child: const Text('自动排序'),
              ),
              ActionButton.primary(
                onPressed: busy || data == null || !dirty ? null : save,
                child: const Text('保存顺序'),
              ),
              if (dirty) Text('有未保存的调整', style: t.typography.caption),
            ],
          ),
          TargetGame(path: widget.game.path),
          if (data != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Tooltip(
                message: data.configPath,
                child: Text(
                  '加载配置（默认存档由各安装共享） · ${data.configPath}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.typography.caption,
                ),
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: ProgressBar(),
            ),
          if (notice.isNotEmpty || problems.isNotEmpty || warnings.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 118),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SelectableText(
                    [
                      ...problems,
                      if (notice.isNotEmpty) notice,
                      ...warnings,
                    ].join('\n'),
                    style: TextStyle(
                      color: problems.isNotEmpty ? c.danger : c.secondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: data == null
                ? Center(child: Text(busy ? '正在读取游戏配置…' : '暂时无法读取加载顺序'))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final installed = Panel(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('可用 Mod', style: t.typography.bodyStrong),
                            const SizedBox(height: 10),
                            SearchField(
                              placeholder: '筛选名称或包 ID',
                              onChanged: (s) =>
                                  setState(() => filter = s.toLowerCase()),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: ListView(
                                children: [
                                  for (final mod in data.mods.where(
                                    (m) => '${m.name} ${m.id}'
                                        .toLowerCase()
                                        .contains(filter),
                                  ))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Checkbox(
                                        checked: active.contains(mod.id),
                                        onChanged:
                                            busy ||
                                                (mod.id == 'ludeon.rimworld' &&
                                                    active.contains(mod.id))
                                            ? null
                                            : (checked) => change(() {
                                                if (checked == true) {
                                                  active.add(mod.id);
                                                } else {
                                                  active.remove(mod.id);
                                                }
                                              }),
                                        content: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              mod.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (officialContentLabel(
                                                  mod.id,
                                                  mod.source,
                                                )
                                                case final label?)
                                              OfficialContentBadge(label)
                                            else
                                              Text(
                                                mod.source,
                                                style: t.typography.caption,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                      final ordered = Panel(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '已启用 · ${active.length}',
                              style: t.typography.bodyStrong,
                            ),
                            const SizedBox(height: 5),
                            Text('拖动或使用箭头调整顺序', style: t.typography.caption),
                            const SizedBox(height: 12),
                            Expanded(
                              child: ReorderableList(
                                itemCount: active.length,
                                onReorderItem: (from, to) {
                                  if (busy) return;
                                  change(() {
                                    final id = active.removeAt(from);
                                    active.insert(to, id);
                                  });
                                },
                                itemBuilder: (context, index) {
                                  final id = active[index];
                                  return Container(
                                    key: ValueKey('$index/$id'),
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.surface,
                                      border: Border.all(color: c.border),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          child: Text(
                                            '${index + 1}',
                                            style: t.typography.caption,
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 4,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    name(id),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  if (officialLabel(id)
                                                      case final label?)
                                                    OfficialContentBadge(label),
                                                ],
                                              ),
                                              Text(
                                                id,
                                                style: t.typography.caption,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            FluentIcons.chevron_up,
                                            size: 16,
                                          ),
                                          onPressed: busy || index == 0
                                              ? null
                                              : () => change(() {
                                                  active.removeAt(index);
                                                  active.insert(index - 1, id);
                                                }),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            FluentIcons.chevron_down,
                                            size: 16,
                                          ),
                                          onPressed:
                                              busy || index == active.length - 1
                                              ? null
                                              : () => change(() {
                                                  active.removeAt(index);
                                                  active.insert(index + 1, id);
                                                }),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            FluentIcons.cancel,
                                            size: 16,
                                          ),
                                          onPressed:
                                              busy || id == 'ludeon.rimworld'
                                              ? null
                                              : () => change(
                                                  () => active.removeAt(index),
                                                ),
                                        ),
                                        ReorderableDragStartListener(
                                          index: index,
                                          enabled: !busy,
                                          child: Padding(
                                            padding: const EdgeInsets.all(10),
                                            child: Icon(
                                              FluentIcons.gripper_dots_vertical,
                                              size: 16,
                                              color: c.secondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                      return constraints.maxWidth >= 620
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 3, child: installed),
                                const SizedBox(width: 14),
                                Expanded(flex: 5, child: ordered),
                              ],
                            )
                          : ListView(
                              children: [
                                SizedBox(height: 260, child: installed),
                                const SizedBox(height: 12),
                                SizedBox(height: 400, child: ordered),
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
