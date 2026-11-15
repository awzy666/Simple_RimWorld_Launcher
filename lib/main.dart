import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import 'src/rust/api.dart' as core;
import 'src/rust/frb_generated.dart';
import 'src/workshop_view.dart';
import 'src/mods_view.dart';
import 'src/app_theme.dart';
import 'src/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final path = File(Platform.resolvedExecutable).parent.path;
  String? failure;
  try {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open('$path/rimworld_core.dll'),
    );
  } catch (e) {
    failure = e.toString();
  }
  final appearance = await Appearance.read();
  runApp(LauncherApp(startupError: failure, initialThemeMode: appearance));
}

class LauncherApp extends StatefulWidget {
  final String? startupError;
  final ThemeMode initialThemeMode;
  final Future<void> Function(ThemeMode)? saveAppearance;
  const LauncherApp({
    super.key,
    this.startupError,
    this.initialThemeMode = ThemeMode.system,
    this.saveAppearance,
  });
  @override
  State<LauncherApp> createState() => _LauncherAppState();
}

class _LauncherAppState extends State<LauncherApp> {
  late ThemeMode mode = widget.initialThemeMode;
  late final lightTheme = launcherTheme(Brightness.light);
  late final darkTheme = launcherTheme(Brightness.dark);
  int page = 0;
  Future<void> changeTheme(ThemeMode next) async {
    setState(() => mode = next);
    await (widget.saveAppearance ?? Appearance.save)(next);
  }

  @override
  Widget build(BuildContext context) => FluentApp(
    title: 'RimWorld 启动器',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: const [
      FluentLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    themeMode: mode,
    theme: lightTheme,
    darkTheme: darkTheme,
    builder: (context, child) => WindowTheme(
      brightness: FluentTheme.of(context).brightness,
      child: Overlay.wrap(
        child: AppWindowChrome(
          menu: widget.startupError == null
              ? LauncherTopMenuBar(
                  labels: _LibraryWindowState.titles,
                  selected: page,
                  onSelected: (value) => setState(() => page = value),
                )
              : null,
          child: child!,
        ),
      ),
    ),
    home: widget.startupError == null
        ? LibraryWindow(
            themeMode: mode,
            onThemeChanged: changeTheme,
            page: page,
            onNavigate: (value) => setState(() => page = value),
          )
        : Center(child: Text('启动核心加载失败\n${widget.startupError}')),
  );
}

class Job {
  final core.TaskRequest request;
  final String label;
  core.TaskEvent status = const core.TaskEvent(
    stage: '准备中',
    done: false,
    error: false,
  );
  Job(this.request, this.label);
}

class LibraryWindow extends StatefulWidget {
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeChanged;
  final int page;
  final ValueChanged<int> onNavigate;
  const LibraryWindow({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.page,
    required this.onNavigate,
  });
  @override
  State<LibraryWindow> createState() => _LibraryWindowState();
}

class _LibraryWindowState extends State<LibraryWindow> {
  core.Library library = const core.Library(
    games: [],
    selected: '',
    steamcmd: '',
    gameUrl: '',
  );
  List<core.LocalMod> mods = [];
  String? gameSourceDraft;
  final downloadSourceKey = GlobalKey();
  int revision = 0, serial = 0;
  int get page => widget.page;
  final sections = [0, 0, 0, 0];
  bool showingJobs = false;
  String? notice;
  bool failed = false, launching = false;
  final jobs = <Job>[];
  static const titles = ['首页', '创意工坊', '已安装 Mod', '设置'];
  static const submenus = [
    ['游戏概览', '安装管理'],
    ['浏览与搜索'],
    ['本地 Mod', '加载顺序'],
    ['外观主题', '下载与工具', '扫描目录'],
  ];
  static const submenuIcons = [
    [FluentIcons.home, FluentIcons.folder_open],
    [FluentIcons.search],
    [FluentIcons.packages, FluentIcons.sort_lines],
    [FluentIcons.color, FluentIcons.download, FluentIcons.search],
  ];
  core.Game? get game =>
      library.games.where((g) => g.path == library.selected).firstOrNull;
  bool get scanning =>
      jobs.any((v) => v.request.kind == core.TaskKind.scan && !v.status.done);

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      await guard(refresh);
      if (mounted) scan('');
    }());
  }

  void message(String text, {bool error = false}) {
    if (mounted) {
      setState(() {
        notice = text;
        failed = error;
      });
    }
  }

  Future<void> guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      message('$e', error: true);
    }
  }

  Future<void> refresh() async {
    final token = ++revision;
    final state = await core.library_();
    if (!mounted || token != revision) return;
    setState(() {
      if (library.selected != state.selected) mods = [];
      library = state;
    });
    final items = state.selected.isEmpty
        ? <core.LocalMod>[]
        : await core.listMods(game: state.selected);
    if (mounted && token == revision) setState(() => mods = items);
  }

  void navigate(int value, [int? section]) {
    setState(() {
      showingJobs = false;
      if (section != null) sections[value] = section;
    });
    widget.onNavigate(value);
  }

  @override
  void didUpdateWidget(covariant LibraryWindow old) {
    super.didUpdateWidget(old);
    if (old.page != page) showingJobs = false;
  }

  void scan(String root) {
    if (!scanning) {
      enqueue(core.TaskKind.scan, root, '', '', root.isEmpty ? '自动发现' : '扫描目录');
    }
  }

  void enqueue(
    core.TaskKind kind,
    String target,
    String source,
    String folder,
    String label,
  ) {
    final request = core.TaskRequest(
      id: '${DateTime.now().microsecondsSinceEpoch}-${serial++}',
      kind: kind,
      target: target,
      source: source,
      folder: folder,
      steamcmd: library.steamcmd,
    );
    if (jobs.any(
      (j) =>
          !j.status.done &&
          j.request.kind == kind &&
          j.request.target == target &&
          j.request.source == source,
    )) {
      return;
    }
    final job = Job(request, label);
    setState(() {
      jobs.insert(0, job);
      if (jobs.length > 25 && jobs.last.status.done) jobs.removeLast();
    });
    unawaited(run(job));
  }

  Future<void> run(Job job) async {
    try {
      await for (final event in core.task(request: job.request)) {
        if (!mounted) return;
        setState(() => job.status = event);
        if (event.done) {
          if (event.error) {
            message('${job.label}失败 · ${event.stage}', error: true);
          } else {
            await refresh();
            if (job.request.kind != core.TaskKind.scan) {
              message('${job.label}已完成');
            }
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => job.status = core.TaskEvent(stage: '$e', done: true, error: true),
      );
      message('$e', error: true);
    }
  }

  Future<void> addGame() => guard(() async {
    final path = await core.chooseDirectory();
    if (path == null) return;
    await core.registerGame(path: path);
    await refresh();
  });
  Future<void> select(String path) => guard(() async {
    await core.selectGame(path: path);
    await refresh();
  });
  Future<void> chooseCmd() => guard(() async {
    final path = await core.chooseDirectory();
    if (path == null) return;
    await core.setSteamcmd(path: path);
    await refresh();
  });
  Future<void> installComponent(bool cmd) => guard(() async {
    final url = cmd ? '' : library.gameUrl;
    if (!cmd && url.isEmpty) {
      navigate(3, 1);
      message('请在设置中填写并保存游戏 ZIP 下载源', error: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final sourceContext = downloadSourceKey.currentContext;
        if (sourceContext != null) Scrollable.ensureVisible(sourceContext);
      });
      return;
    }
    final dir = await core.chooseDirectory();
    if (dir == null || !mounted) return;
    if (!cmd) {
      final known = library.games
          .where((g) => g.path.toLowerCase() == dir.toLowerCase())
          .firstOrNull;
      if (known != null) {
        await select(known.path);
        message('已选中现有游戏');
        return;
      }
      if (await File('$dir/RimWorld.exe').exists() ||
          await File('$dir/RimWorldWin64.exe').exists()) {
        if (!mounted) return;
        final yes = await confirm(context, '登记现有游戏？', dir, '登记');
        if (yes) {
          await core.registerGame(path: dir);
          await refresh();
        }
        return;
      }
    }
    if (!mounted) return;
    final yes = await confirm(
      context,
      cmd ? '安装 SteamCMD？' : '安装 RimWorld？',
      '安装目录\n$dir\n\n下载源\n${cmd ? 'Valve · steamcmd.zip' : url}',
      '安装',
    );
    if (yes) {
      enqueue(
        cmd ? core.TaskKind.installSteamcmd : core.TaskKind.installGame,
        dir,
        url,
        '',
        cmd ? '安装 SteamCMD' : '安装游戏',
      );
    }
  });
  void installMod(String id, String name, [String folder = '']) {
    if (game == null) {
      message('请先在首页选择游戏', error: true);
      return;
    }
    if (library.steamcmd.isEmpty) {
      message('请先在设置中选择或安装 SteamCMD', error: true);
      navigate(3, 1);
      return;
    }
    enqueue(
      core.TaskKind.installMod,
      game!.path,
      id,
      folder,
      '${folder.isEmpty ? '安装' : '更新'} $name',
    );
  }

  Future<void> launch() async {
    if (game == null || launching) return;
    final path = game!.path;
    setState(() => launching = true);
    await guard(() async {
      await core.launchGame(path: path);
      message('已发送游戏启动请求');
    });
    if (mounted) setState(() => launching = false);
  }

  Future<void> saveSource() async {
    await core.setGameUrl(url: (gameSourceDraft ?? library.gameUrl).trim());
    await refresh();
  }

  void showJobs() => setState(() => showingJobs = true);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final active = jobs.where((j) => !j.status.done).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('section-sidebar'),
          width: 156,
          decoration: BoxDecoration(
            color: c.sidebar,
            border: Border(right: BorderSide(color: c.border)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 20, 10, 12),
          child: LauncherSideMenuBar(
            title: titles[page],
            labels: submenus[page],
            icons: submenuIcons[page],
            selected: sections[page],
            menuKeyPrefix: 'section-$page',
            tasksSelected: showingJobs,
            tasksLabel: active.isEmpty ? '任务中心' : '任务 · ${active.length}',
            onTasks: showJobs,
            onSelected: (value) => setState(() {
              sections[page] = value;
              showingJobs = false;
            }),
            footer: game == null
                ? null
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 8, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前游戏',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          game!.version.isEmpty ? 'RimWorld' : game!.version,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentTheme.of(context).typography.bodyStrong
                              ?.copyWith(fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Tooltip(
                          message: game!.path,
                          child: Text(
                            game!.path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FluentTheme.of(context).typography.caption
                                ?.copyWith(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: InfoBar(
                    title: Text(
                      notice!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    severity: failed
                        ? InfoBarSeverity.error
                        : InfoBarSeverity.success,
                    onClose: () => setState(() => notice = null),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: showingJobs ? 1 : 0,
                  children: [
                    IndexedStack(
                      index: page,
                      children: [
                        IndexedStack(
                          index: sections[0],
                          children: [home(), installations()],
                        ),
                        WorkshopView(
                          visible: page == 1 && !showingJobs,
                          game: game,
                          mods: mods,
                          onInstall: installMod,
                        ),
                        ModsView(
                          game: game,
                          mods: mods,
                          onInstall: installMod,
                          showOrder: sections[2] == 1,
                          onOrderClosed: () => setState(() => sections[2] = 0),
                          onRefresh: () => guard(refresh),
                          onChanged: refresh,
                          onError: (s) => message(s, error: true),
                        ),
                        settings(),
                      ],
                    ),
                    tasks(),
                  ],
                ),
              ),
              if (active.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message:
                              '${active.first.status.stage}\n${active.first.request.target}',
                          child: Text(
                            '${active.first.label} · ${active.first.status.stage}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentTheme.of(context).typography.caption,
                          ),
                        ),
                      ),
                      if (active.first.request.kind == core.TaskKind.scan)
                        ActionButton(
                          onPressed: () =>
                              core.cancelScan(id: active.first.request.id),
                          child: const Text('取消扫描'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget heading(String title, String subtitle, {Widget? action}) {
    final t = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.typography.subtitle?.copyWith(fontSize: 20),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle, style: t.typography.caption),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action],
        ],
      ),
    );
  }

  Widget home() {
    final c = AppColors.of(context);
    final t = FluentTheme.of(context);
    final current = game;
    return ListView(
      key: const ValueKey('home-scroll'),
      primary: false,
      padding: const EdgeInsets.all(18),
      children: [
        heading('游戏概览', '选择一份安装，继续你的殖民地。'),
        Container(
          height: 174,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: LayoutBuilder(
            builder: (context, bounds) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RimWorld',
                          style: t.typography.title?.copyWith(fontSize: 26),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              current == null
                                  ? '尚未添加游戏'
                                  : current.steam
                                  ? 'Steam 安装'
                                  : '独立目录',
                              style: t.typography.caption,
                            ),
                            if (current != null) ...[
                              Text('  ·  ', style: t.typography.caption),
                              Flexible(
                                child: Text(
                                  current.version.isEmpty
                                      ? '版本未知'
                                      : current.version,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.typography.caption,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Tooltip(
                          message: current?.path ?? '添加游戏目录或从网址安装',
                          child: Text(
                            current?.path ?? '在安装管理中添加或下载游戏。',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.typography.caption,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            ActionButton.primary(
                              onPressed: current == null
                                  ? addGame
                                  : launching
                                  ? null
                                  : launch,
                              child: Text(current == null ? '选择游戏' : '启动游戏'),
                            ),
                            const SizedBox(width: 8),
                            ActionButton(
                              onPressed: () => navigate(0, 1),
                              child: const Text('安装管理'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (bounds.maxWidth >= 610)
                  SizedBox(
                    width: 200,
                    child: Image.asset(
                      'assets/colony.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                      errorBuilder: (context, error, stack) =>
                          ColoredBox(color: c.elevated),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Panel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('本地 Mod', style: t.typography.bodyStrong),
                    const SizedBox(height: 5),
                    Text(
                      '${mods.length} 个 Mod · 启用与排序可在应用内管理',
                      maxLines: 2,
                      style: t.typography.caption,
                    ),
                    const SizedBox(height: 16),
                    ActionButton(
                      onPressed: current == null ? null : () => navigate(2, 0),
                      child: const Text('管理 Mod'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Panel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'SteamCMD',
                            style: t.typography.bodyStrong,
                          ),
                        ),
                        Text(
                          library.steamcmd.isEmpty ? '未配置' : '已配置',
                          style: t.typography.caption?.copyWith(
                            color: c.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Tooltip(
                      message: library.steamcmd,
                      child: Text(
                        library.steamcmd.isEmpty
                            ? '选择已有工具或从 Valve 安装。'
                            : library.steamcmd,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.typography.caption,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ActionButton(
                      onPressed: () => navigate(3, 1),
                      child: const Text('工具与设置'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget installations() {
    final t = FluentTheme.of(context);
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading(
            '安装管理',
            '已发现 ${library.games.length} 份游戏，选中后应用于启动和 Mod 管理。',
            action: Tooltip(
              message: '重新检测',
              child: IconButton(
                icon: const Icon(FluentIcons.refresh, size: 16),
                onPressed: scanning ? null : () => scan(''),
              ),
            ),
          ),
          Expanded(
            child: library.games.isEmpty
                ? const Center(child: Text('添加已有游戏目录，或从网址安装。'))
                : ListView.separated(
                    primary: false,
                    itemCount: library.games.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final g = library.games[index];
                      final selected = g.path == library.selected;
                      return Panel(
                        padding: const EdgeInsets.all(14),
                        selected: selected,
                        child: Row(
                          children: [
                            RadioGroup<String>(
                              groupValue: library.selected,
                              onChanged: (value) {
                                if (value != null) select(value);
                              },
                              child: RadioButton<String>(
                                value: g.path,
                                semanticLabel: g.path,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'RimWorld  ${g.version}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.typography.bodyStrong,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    g.steam ? 'Steam 安装' : '独立目录',
                                    style: t.typography.caption?.copyWith(
                                      color: c.accent,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    g.path,
                                    style: t.typography.caption,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ActionButton(onPressed: addGame, child: const Text('添加目录')),
              const SizedBox(width: 8),
              ActionButton.primary(
                onPressed: () => installComponent(false),
                child: const Text('从网址安装'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget settings() => IndexedStack(
    index: sections[3],
    children: [appearanceSettings(), downloadSettings(), scanSettings()],
  );

  Widget appearanceSettings() {
    final t = FluentTheme.of(context);
    return ListView(
      primary: false,
      padding: const EdgeInsets.all(18),
      children: [
        heading('外观主题', '选择适合你的界面，浅色与深色均保持清晰的文字对比。'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: RadioGroup<ThemeMode>(
            groupValue: widget.themeMode,
            onChanged: (value) {
              if (value != null) guard(() => widget.onThemeChanged(value));
            },
            child: Column(
              children: [
                for (final option in [
                  (ThemeMode.light, '浅色', '明亮背景，适合日间使用。', FluentIcons.sunny),
                  (
                    ThemeMode.dark,
                    '深色',
                    '深色背景，适合较暗的环境。',
                    FluentIcons.clear_night,
                  ),
                  (
                    ThemeMode.system,
                    '跟随系统',
                    '与 Windows 当前的明暗设置同步。',
                    FluentIcons.desktop_screenshot,
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Icon(
                          option.$4,
                          size: 20,
                          color: AppColors.of(context).secondary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: RadioButton<ThemeMode>(
                            value: option.$1,
                            content: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(option.$2, style: t.typography.bodyStrong),
                                const SizedBox(height: 3),
                                Text(option.$3, style: t.typography.caption),
                              ],
                            ),
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
    );
  }

  Widget downloadSettings() {
    final t = FluentTheme.of(context);
    return ListView(
      primary: false,
      padding: const EdgeInsets.all(18),
      children: [
        heading('下载与工具', '配置 SteamCMD 和游戏 ZIP 直链。'),
        Panel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('SteamCMD', style: t.typography.bodyStrong),
                  ),
                  StatusLabel(
                    library.steamcmd.isEmpty ? '未配置' : '已配置',
                    selected: library.steamcmd.isNotEmpty,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                library.steamcmd.isEmpty
                    ? '选择已有工具目录，或下载 Valve 官方版本。'
                    : library.steamcmd,
                style: t.typography.caption,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ActionButton(onPressed: chooseCmd, child: const Text('选择目录')),
                  const SizedBox(width: 8),
                  ActionButton(
                    onPressed: () => installComponent(true),
                    child: const Text('从 Valve 安装'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          key: downloadSourceKey,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('游戏 ZIP 下载源', style: t.typography.bodyStrong),
              const SizedBox(height: 8),
              SizedBox(
                height: controlHeight,
                child: TextFormBox(
                  key: ValueKey(library.gameUrl),
                  initialValue: library.gameUrl,
                  decoration: inputDecoration(context),
                  placeholder: 'HTTP 或 HTTPS ZIP 直链',
                  style: const TextStyle(fontSize: 14, height: 1.2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  onChanged: (value) => gameSourceDraft = value,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ActionButton.primary(
                    onPressed: () => guard(() async {
                      await saveSource();
                      message('下载源已保存');
                    }),
                    child: const Text('保存下载源'),
                  ),
                  const SizedBox(width: 8),
                  ActionButton(
                    onPressed: () => guard(() async {
                      await saveSource();
                      await installComponent(false);
                    }),
                    child: const Text('下载并安装'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget scanSettings() {
    final t = FluentTheme.of(context);
    return ListView(
      primary: false,
      padding: const EdgeInsets.all(18),
      children: [
        heading('扫描目录', '自动发现已有游戏和 SteamCMD。'),
        Panel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('指定目录扫描', style: t.typography.bodyStrong),
              const SizedBox(height: 8),
              Text(
                '在所选目录及其子目录中查找 RimWorld 和 SteamCMD。扫描时可在任务中心取消。',
                style: t.typography.caption,
              ),
              const SizedBox(height: 16),
              ActionButton(
                onPressed: scanning
                    ? null
                    : () => guard(() async {
                        final dir = await core.chooseDirectory();
                        if (dir != null) scan(dir);
                      }),
                child: const Text('选择扫描目录'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '当前已登记 ${library.games.length} 份游戏。启动时也会自动检查 Steam 库和常见安装位置。',
          style: t.typography.caption,
        ),
      ],
    );
  }

  Widget tasks() {
    final t = FluentTheme.of(context);
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('任务中心', '下载任务始终绑定创建时选择的游戏目录。'),
          Expanded(
            child: jobs.isEmpty
                ? const Center(child: Text('暂无任务'))
                : ListView.separated(
                    primary: false,
                    itemCount: jobs.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final j = jobs[index];
                      return Panel(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    j.label,
                                    style: t.typography.bodyStrong,
                                  ),
                                ),
                                Text(
                                  j.status.error
                                      ? '失败'
                                      : j.status.done
                                      ? '已完成'
                                      : '进行中',
                                  style: t.typography.caption?.copyWith(
                                    color: j.status.error ? c.danger : c.accent,
                                  ),
                                ),
                              ],
                            ),
                            if (j.request.target.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              SelectableText(
                                j.request.target,
                                style: t.typography.caption,
                              ),
                            ],
                            const SizedBox(height: 6),
                            SelectableText(
                              j.status.stage,
                              style: t.typography.caption,
                            ),
                            if (!j.status.done) ...[
                              const SizedBox(height: 10),
                              ProgressBar(
                                value: j.status.progress == null
                                    ? null
                                    : j.status.progress! * 100,
                              ),
                            ],
                            if (j.status.error ||
                                (!j.status.done &&
                                    j.request.kind == core.TaskKind.scan)) ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ActionButton(
                                  onPressed: j.status.error
                                      ? () => enqueue(
                                          j.request.kind,
                                          j.request.target,
                                          j.request.source,
                                          j.request.folder,
                                          j.label,
                                        )
                                      : () => core.cancelScan(id: j.request.id),
                                  child: Text(j.status.error ? '重试' : '取消扫描'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String text,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: Text(title),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          ActionButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ActionButton.primary(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<String?> askText(
  BuildContext context,
  String title,
  String hint,
  String initial,
) async {
  var value = initial;
  return showDialog<String>(
    context: context,
    builder: (ctx) => ContentDialog(
      title: Text(title),
      content: TextFormBox(
        decoration: inputDecoration(ctx),
        initialValue: initial,
        autofocus: true,
        placeholder: hint,
        onChanged: (s) => value = s,
        onFieldSubmitted: (s) => Navigator.pop(ctx, s.trim()),
      ),
      actions: [
        ActionButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        ActionButton.primary(
          onPressed: () => Navigator.pop(ctx, value.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
}
