import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:rimworld_launcher/main.dart';
import 'package:rimworld_launcher/src/rust/api.dart';
import 'package:rimworld_launcher/src/rust/frb_generated.dart';
import 'package:rimworld_launcher/src/app_theme.dart';
import 'package:rimworld_launcher/src/mod_details.dart';
import 'package:rimworld_launcher/src/mod_card.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:rimworld_launcher/src/load_order_view.dart';
import 'package:rimworld_launcher/src/ui.dart';
import 'package:rimworld_launcher/src/menu_motion.dart';

class LibraryFixture extends Fake implements RustLibApi {
  bool populated = false;
  List<String>? lastSavedOrder;
  String? lastSavedGame, lastSource;
  @override
  Future<ModOrder> crateApiModOrder({required String game}) async =>
      const ModOrder(
        mods: [
          OrderMod(id: 'ludeon.rimworld', name: 'Core', source: '游戏本体 / DLC'),
          OrderMod(id: 'brrainz.harmony', name: 'Harmony', source: '本地 Mod'),
          OrderMod(id: 'speed.mod', name: 'Speed', source: '本地 Mod'),
          OrderMod(
            id: 'ludeon.rimworld.royalty',
            name: 'Royalty',
            source: '游戏本体 / DLC',
          ),
        ],
        active: ['speed.mod', 'ludeon.rimworld', 'brrainz.harmony'],
        configPath: r'C:\Config\ModsConfig.xml',
        revision: 'original',
        warnings: [],
      );
  @override
  Future<OrderCheck> crateApiOrganizeMods({
    required String game,
    required List<String> active,
    required bool sort,
  }) async => const OrderCheck(
    active: ['brrainz.harmony', 'ludeon.rimworld', 'speed.mod'],
    problems: [],
    warnings: [],
  );
  @override
  Future<ModOrder> crateApiSaveModOrder({
    required String game,
    required List<String> active,
    required String revision,
  }) async {
    lastSavedOrder = [...active];
    lastSavedGame = game;
    return ModOrder(
      mods: (await crateApiModOrder(game: game)).mods,
      active: active,
      configPath: r'C:\Config\ModsConfig.xml',
      revision: 'saved',
      warnings: [],
    );
  }

  @override
  Future<void> crateApiSetGameUrl({required String url}) async {
    lastSource = url;
  }

  static const game = Game(
    path: r'G:\Games\RimWorld',
    version: '1.7.4990',
    steam: false,
  );
  @override
  Future<Library> crateApiLibrary() async => const Library(
    games: [game],
    selected: r'G:\Games\RimWorld',
    steamcmd: r'G:\steamcmd.exe',
    gameUrl: '',
  );
  @override
  Future<List<LocalMod>> crateApiListMods({required String game}) async => [
    LocalMod(
      folder: 'HarmonyMod',
      path: r'G:\Games\RimWorld\Mods\HarmonyMod',
      name: 'Harmony',
      author: 'pardeike',
      packageId: 'brrainz.harmony',
      versions: '1.7',
      itemId: '2009463077',
      issue: '',
    ),
    if (populated)
      for (var i = 1; i < 4; i++)
        LocalMod(
          folder: 'mod_$i',
          path: '${LibraryFixture.game.path}\\Mods\\mod_$i',
          name: '测试 Mod $i',
          author: '作者 $i',
          packageId: 'test.mod.$i',
          versions: '1.6、1.7',
          itemId: '100000000$i',
          issue: '',
        ),
  ];
  @override
  Stream<TaskEvent> crateApiTask({required TaskRequest request}) =>
      Stream.value(const TaskEvent(stage: '已完成', done: true, error: false));
  @override
  Future<SearchPage> crateApiSearchWorkshop({
    required String query,
    required int page,
  }) async => SearchPage(
    items: populated
        ? [
            for (var i = 0; i < 4; i++)
              WorkshopItem(
                id: i == 0 ? '2009463077' : '100000000$i',
                title: i == 0 ? 'Harmony' : '创意工坊 Mod $i',
                preview: '',
                description: '[b]功能说明[/b]\n\n这是第 $i 个 Mod 的简介。',
                updated: 1700000000,
              ),
          ]
        : [],
    hasNext: populated,
  );
}

void main() {
  final fixture = LibraryFixture();
  setUpAll(() => RustLib.initMock(api: fixture));
  setUp(() => fixture.populated = false);

  for (final axis in [Axis.horizontal, Axis.vertical]) {
    testWidgets('$axis indicator extends to its target before retracting', (
      tester,
    ) async {
      final first = axis == Axis.horizontal
          ? const Rect.fromLTWH(20, 20, 60, 3)
          : const Rect.fromLTWH(20, 20, 3, 36);
      final last = axis == Axis.horizontal
          ? const Rect.fromLTWH(220, 20, 80, 3)
          : const Rect.fromLTWH(20, 220, 3, 36);
      var target = first;
      late StateSetter redraw;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: StatefulBuilder(
              builder: (context, setState) {
                redraw = setState;
                return Stack(
                  children: [
                    StretchMenuIndicator(
                      target: target,
                      color: const Color(0xff2459c4),
                      markerKey: const ValueKey('motion-test-marker'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      final marker = find.byKey(const ValueKey('motion-test-marker'));
      double leading(Rect rect) =>
          axis == Axis.horizontal ? rect.left : rect.top;
      double trailing(Rect rect) =>
          axis == Axis.horizontal ? rect.right : rect.bottom;
      redraw(() => target = last);
      await tester.pump();
      expect(tester.getRect(marker), first);
      await tester.pump(const Duration(milliseconds: 80));
      final growing = tester.getRect(marker);
      expect(leading(growing), leading(first));
      expect(trailing(growing), greaterThan(trailing(first)));
      expect(trailing(growing), lessThan(trailing(last)));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(marker), first.expandToInclude(last));
      await tester.pump(const Duration(milliseconds: 80));
      final shrinking = tester.getRect(marker);
      expect(leading(shrinking), greaterThan(leading(first)));
      expect(leading(shrinking), lessThan(leading(last)));
      expect(trailing(shrinking), trailing(last));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(marker), last);
      // The opposite direction grows the other edge first.
      redraw(() => target = first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.getRect(marker), first.expandToInclude(last));
      await tester.pump(const Duration(milliseconds: 80));
      expect(leading(tester.getRect(marker)), leading(first));
      expect(trailing(tester.getRect(marker)), lessThan(trailing(last)));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(marker), first);
      // Interrupt an in-progress stretch without resetting its painted bounds.
      redraw(() => target = last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final interrupted = tester.getRect(marker);
      redraw(() => target = first);
      await tester.pump();
      expect(tester.getRect(marker), interrupted);
      await tester.pumpAndSettle();
      expect(tester.getRect(marker), first);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion snaps both indicator axes to their destination', (
    tester,
  ) async {
    var changed = false;
    late StateSetter redraw;
    const horizontal = Rect.fromLTWH(180, 0, 72, 2);
    const vertical = Rect.fromLTWH(0, 180, 3, 36);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) {
              redraw = setState;
              return Stack(
                children: [
                  StretchMenuIndicator(
                    target: changed
                        ? horizontal
                        : const Rect.fromLTWH(0, 0, 72, 2),
                    color: const Color(0xff2459c4),
                    markerKey: const ValueKey('horizontal-marker'),
                  ),
                  StretchMenuIndicator(
                    target: changed
                        ? vertical
                        : const Rect.fromLTWH(0, 0, 3, 36),
                    color: const Color(0xff2459c4),
                    markerKey: const ValueKey('vertical-marker'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    redraw(() => changed = true);
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const ValueKey('horizontal-marker'))),
      horizontal,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('vertical-marker'))),
      vertical,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      '$mode sidebar stretches and selection never flashes after pointer input',
      (tester) async {
        tester.view.physicalSize = const Size(900, 550);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          LauncherApp(initialThemeMode: mode, saveAppearance: (_) async {}),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('top-menu-3')));
        await tester.pumpAndSettle();
        final marker = find.byKey(const ValueKey('side-menu-indicator'));
        final start = tester.getRect(marker);
        final menu = find.byKey(const ValueKey('section-3-2'));
        final destination = tester.getRect(menu);
        final surface = find.descendant(
          of: menu,
          matching: find.byKey(const ValueKey('menu-item-surface')),
        );
        final idle = tester.widget<Container>(surface).decoration;
        final pointer = await tester.startGesture(tester.getCenter(menu));
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.widget<Container>(surface).decoration, idle);
        await pointer.up();
        await tester.pump();
        final selected = tester.widget<Container>(surface).decoration;
        final colors = mode == ThemeMode.light
            ? AppColors.light
            : AppColors.dark;
        expect((selected as BoxDecoration).color, colors.selection);
        await tester.pump(const Duration(milliseconds: 80));
        final growing = tester.getRect(marker);
        expect(growing.top, start.top);
        expect(growing.bottom, greaterThan(start.bottom));
        expect(growing.bottom, lessThan(destination.bottom));
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getRect(marker).top, start.top);
        expect(tester.getRect(marker).bottom, destination.bottom);
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getRect(marker).top, greaterThan(start.top));
        expect(tester.getRect(marker).bottom, destination.bottom);
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getRect(marker).top, destination.top);
        expect(tester.getRect(marker).height, destination.height);
        for (var i = 0; i < 20; i++) {
          expect(tester.widget<Container>(surface).decoration, selected);
          await tester.pump(const Duration(milliseconds: 16));
        }
        // Include the bottom task menu in the same vertical animation.
        final tasks = find.byKey(const ValueKey('side-menu-tasks'));
        await tester.tap(tasks);
        await tester.pumpAndSettle();
        expect(tester.getRect(marker).top, tester.getRect(tasks).top);
        await tester.tap(find.byKey(const ValueKey('section-3-0')));
        await tester.pumpAndSettle();
        expect(tester.getRect(marker), start);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$mode underline slides while menu and content typography stay fixed',
      (tester) async {
        tester.view.physicalSize = const Size(900, 550);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          LauncherApp(initialThemeMode: mode, saveAppearance: (_) async {}),
        );
        await tester.pumpAndSettle();
        List<Object?> metrics(Finder target) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find
                .descendant(
                  of: target,
                  matching: find.byType(RichText, skipOffstage: false),
                  skipOffstage: false,
                )
                .first,
          );
          final style = paragraph.text.style!;
          return [
            style.fontSize,
            style.fontWeight,
            style.fontFamily,
            style.height,
            paragraph.size,
            paragraph.getTransformTo(null).getMaxScaleOnAxis(),
          ];
        }

        final menuFinders = [
          for (var i = 0; i < 4; i++) find.byKey(ValueKey('top-menu-$i')),
        ];
        final textBefore = [for (final menu in menuFinders) metrics(menu)];
        final harmony = find.text('Harmony', skipOffstage: false);
        final contentBefore = metrics(harmony);
        final firstCard = find.byType(ModListCard, skipOffstage: false).first;
        final update = find.descendant(
          of: firstCard,
          matching: find.text('更新', skipOffstage: false),
          skipOffstage: false,
        );
        final buttonBefore = metrics(update);
        void expectStableText() {
          for (var i = 0; i < menuFinders.length; i++) {
            expect(metrics(menuFinders[i]), textBefore[i]);
          }
          expect(metrics(harmony), contentBefore);
          expect(metrics(update), buttonBefore);
        }

        final indicator = find.byKey(const ValueKey('top-menu-indicator'));
        final start = tester.getRect(indicator);
        final destination = tester.getRect(menuFinders[2]);
        await tester.tap(menuFinders[2]);
        await tester.pump();
        expect(tester.getRect(indicator).left, start.left);
        expectStableText();
        await tester.pump(const Duration(milliseconds: 50));
        final middle = tester.getRect(indicator);
        expect(middle.left, start.left);
        expect(middle.right, greaterThan(start.right));
        expect(middle.right, lessThan(destination.right));
        expectStableText();
        // Retarget before the first animation finishes; only the underline moves.
        await tester.tap(menuFinders[3]);
        await tester.pump();
        expect(tester.getRect(indicator).left, closeTo(middle.left, 0.01));
        for (var i = 0; i < 18; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          expectStableText();
        }
        final finalBounds = tester.getRect(menuFinders[3]);
        expect(tester.getRect(indicator).left, closeTo(finalBounds.left, 0.01));
        expect(
          tester.getRect(indicator).width,
          closeTo(finalBounds.width, 0.01),
        );
        await tester.tap(menuFinders[0]);
        await tester.pumpAndSettle();
        expect(tester.getRect(indicator), start);
        expectStableText();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$mode hovering menus and Mod cards does not preview selection',
      (tester) async {
        tester.view.physicalSize = const Size(900, 550);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          LauncherApp(initialThemeMode: mode, saveAppearance: (_) async {}),
        );
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(895, 545));
        addTearDown(mouse.removePointer);
        final menu = find.byKey(const ValueKey('top-menu-2'));
        final menuContainer = find.descendant(
          of: menu,
          matching: find.byKey(const ValueKey('menu-item-surface')),
        );
        final before = tester.widget<Container>(menuContainer).decoration;
        final indicator = tester.getRect(
          find.byKey(const ValueKey('top-menu-indicator')),
        );
        await mouse.moveTo(tester.getCenter(menu));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.widget<Container>(menuContainer).decoration, before);
        expect(
          tester.getRect(find.byKey(const ValueKey('top-menu-indicator'))),
          indicator,
        );
        await tester.tap(menu);
        await tester.pumpAndSettle();
        final card = find.byType(ModListCard).first;
        final container = find
            .descendant(of: card, matching: find.byType(Container))
            .first;
        final cardBefore = tester.widget<Container>(container).decoration;
        await mouse.moveTo(tester.getTopLeft(card) + const Offset(160, 40));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.widget<Container>(container).decoration, cardBefore);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$mode title menus and sidebar switch real content without button borders',
      (tester) async {
        tester.view.physicalSize = const Size(900, 550);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final commands = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AppWindowChrome.channel, (
              MethodCall call,
            ) async {
              commands.add(call.method);
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(AppWindowChrome.channel, null),
        );
        await tester.pumpWidget(
          LauncherApp(initialThemeMode: mode, saveAppearance: (_) async {}),
        );
        await tester.pumpAndSettle();
        commands.clear();
        for (var i = 0; i < 4; i++) {
          final rect = tester.getRect(find.byKey(ValueKey('top-menu-$i')));
          expect(rect.top, 1);
          expect(rect.height, 44);
        }
        final menuSurfaces = find.descendant(
          of: find.byType(LauncherMenuItem),
          matching: find.byKey(const ValueKey('menu-item-surface')),
        );
        expect(menuSurfaces, findsNWidgets(7));
        for (final element in menuSurfaces.evaluate()) {
          expect(
            ((element.widget as Container).decoration as BoxDecoration).border,
            isNull,
          );
        }
        for (final key in ['window-minimize', 'window-close']) {
          final button = tester.widget<IconButton>(find.byKey(ValueKey(key)));
          expect(
            (button.style!.shape!.resolve(
              {},
            ) as RoundedRectangleBorder).side.style,
            BorderStyle.none,
          );
        }
        await tester.tap(find.byKey(const ValueKey('section-0-1')));
        await tester.pumpAndSettle();
        expect(find.text('添加目录').hitTestable(), findsOneWidget);
        expect(find.text('启动游戏').hitTestable(), findsNothing);
        await tester.tap(find.byKey(const ValueKey('top-menu-2')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('section-2-1')), findsOneWidget);
        expect(find.text('Harmony').hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('top-menu-0')));
        await tester.pumpAndSettle();
        expect(find.text('添加目录').hitTestable(), findsOneWidget);
        expect(
          commands,
          isEmpty,
          reason: 'Menu clicks must not initiate window dragging',
        );
        await tester.tap(find.byKey(const ValueKey('window-minimize')));
        await tester.tap(find.byKey(const ValueKey('window-close')));
        await tester.pumpAndSettle();
        expect(commands, ['minimize', 'close']);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$mode horizontal Mod cards fit the fixed window', (
      tester,
    ) async {
      fixture.populated = true;
      tester.view.physicalSize = const Size(900, 550);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        LauncherApp(initialThemeMode: mode, saveAppearance: (_) async {}),
      );
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('home-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        0,
      );
      expect(find.text('启动游戏').hitTestable(), findsOneWidget);
      expect(find.text('工具与设置').hitTestable(), findsOneWidget);

      for (final page in ['已安装 Mod', '创意工坊']) {
        await tester.tap(find.byTooltip(page).first);
        await tester.pumpAndSettle();
        final cards = find.byType(ModListCard).hitTestable();
        expect(cards, findsNWidgets(4));
        final rectangles = [
          for (var i = 0; i < 4; i++) tester.getRect(cards.at(i)),
        ];
        for (var i = 0; i < rectangles.length; i++) {
          final rect = rectangles[i];
          expect(rect.width, greaterThan(660));
          expect(
            rect.left,
            greaterThan(
              tester
                  .getRect(find.byKey(const ValueKey('section-sidebar')))
                  .right,
            ),
          );
          expect(rect.left, rectangles.first.left);
          expect(rect.bottom, lessThanOrEqualTo(550));
          if (i > 0) expect(rect.top, greaterThan(rectangles[i - 1].bottom));
          final info = find.descendant(
            of: cards.at(i),
            matching: find.byTooltip('查看详情'),
          );
          expect(tester.getCenter(info).dy, closeTo(rect.center.dy, 1));
        }
        expect(tester.takeException(), isNull);
      }
      expect(find.text('已安装').hitTestable(), findsNWidgets(4));
    });
  }
  testWidgets('home, local mods, workshop and settings', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LauncherApp());
    await tester.pumpAndSettle();
    expect(find.text('启动游戏'), findsOneWidget);
    for (final element in find.byType(ActionButton).evaluate()) {
      expect(
        tester.getSize(find.byWidget(element.widget)).height,
        controlHeight,
      );
      expect(tester.getSize(find.byWidget(element.widget)).width, 96);
    }
    await tester.tap(find.text('已安装 Mod').first);
    await tester.pumpAndSettle();
    expect(find.text('Harmony'), findsOneWidget);
    await tester.tap(find.text('创意工坊').first);
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的 Mod'), findsOneWidget);
    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载与工具').first);
    await tester.pumpAndSettle();
    expect(find.text('游戏 ZIP 下载源'), findsOneWidget);
  });

  testWidgets('sort and save from the installed Mods entry point', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 550);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LauncherApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('已安装 Mod').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载顺序'));
    await tester.pumpAndSettle();
    expect(find.byType(LoadOrderView), findsOneWidget);
    expect(find.text('官方 DLC'), findsOneWidget);
    await tester.tap(find.text('自动排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存顺序'));
    await tester.pumpAndSettle();
    expect(fixture.lastSavedOrder, [
      'brrainz.harmony',
      'ludeon.rimworld',
      'speed.mod',
    ]);
    expect(fixture.lastSavedGame, LibraryFixture.game.path);
    tester.view.physicalSize = const Size(700, 560);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing download source routes to inline settings editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LauncherApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('section-0-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从网址安装'));
    await tester.pumpAndSettle();
    expect(find.byType(ContentDialog), findsNothing);
    final source = find.byType(TextFormBox);
    await tester.ensureVisible(source);
    await tester.enterText(source, 'https://example.com/rimworld.zip');
    await tester.tap(find.text('保存下载源'));
    await tester.pumpAndSettle();
    expect(fixture.lastSource, 'https://example.com/rimworld.zip');
  });

  testWidgets('Steam detail collapses excess blank lines across BBCode tags', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: launcherTheme(Brightness.light),
        home: const SteamDescription(
          '\r\n \r\n[h1]标题[/h1]\r\n  \r\n\r\n[b]段落[/b]\n\n\n[list][*]项目[/list]\n\n\n[code]    x();\n[/code]\n尾部\n \n',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .toPlainText();
    expect(text, startsWith('标题'));
    expect(text, endsWith('尾部'));
    expect(text, isNot(contains('\n\n\n')));
    expect(text, contains('段落'));
    expect(text, contains('项目'));
    expect(text, contains('    x();'));
  });

  test('text and button foregrounds have at least 4.5:1 contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    for (final palette in [AppColors.light, AppColors.dark]) {
      for (final surface in [
        palette.background,
        palette.sidebar,
        palette.surface,
        palette.elevated,
        palette.selection,
      ]) {
        expect(contrast(palette.text, surface), greaterThanOrEqualTo(4.5));
        expect(contrast(palette.secondary, surface), greaterThanOrEqualTo(4.5));
      }
      expect(
        contrast(palette.accent, palette.selection),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(palette.onAccent, palette.accent),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(palette.danger, palette.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(palette.officialText, palette.officialBackground),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test(
    'official badges use trusted installation source and explicit labels',
    () {
      expect(officialContentLabel('ludeon.rimworld', '游戏本体 / DLC'), '游戏本体');
      expect(
        officialContentLabel('ludeon.rimworld.royalty', '游戏本体 / DLC'),
        '官方 DLC',
      );
      expect(officialContentLabel('ludeon.rimworld.royalty', '本地 Mod'), isNull);
    },
  );

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      '$brightness action controls share height and rounded borders',
      (tester) async {
        final theme = launcherTheme(brightness);
        await tester.pumpWidget(
          FluentApp(
            theme: theme,
            home: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ActionButton(
                    key: const ValueKey('normal-action'),
                    onPressed: () {},
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ActionButton.primary(
                    key: const ValueKey('primary-action'),
                    onPressed: () {},
                    child: const Text('保存'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const ValueKey('icon-action'),
                    onPressed: () {},
                    icon: const Icon(FluentIcons.refresh),
                  ),
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 180,
                    child: SearchField(
                      key: ValueKey('search-control'),
                      placeholder: '搜索',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final key in [
          'normal-action',
          'primary-action',
          'icon-action',
          'search-control',
        ]) {
          expect(
            tester.getSize(find.byKey(ValueKey(key))).height,
            controlHeight,
            reason: key,
          );
        }
        for (final style in [
          theme.buttonTheme.defaultButtonStyle!,
          theme.buttonTheme.filledButtonStyle!,
          theme.buttonTheme.iconButtonStyle!,
        ]) {
          expect(
            style.backgroundColor!.resolve({WidgetState.hovered}),
            style.backgroundColor!.resolve({}),
          );
          expect(
            style.backgroundColor!.resolve({WidgetState.pressed}),
            style.backgroundColor!.resolve({}),
          );
          for (final state in <Set<WidgetState>>[
            {},
            {WidgetState.hovered},
            {WidgetState.pressed},
            {WidgetState.disabled},
          ]) {
            expect(
              (style.shape!.resolve(
                state,
              ) as RoundedRectangleBorder).borderRadius,
              BorderRadius.circular(6),
            );
          }
        }
        expect(
          (theme.buttonTheme.iconButtonStyle!.shape!.resolve(
            {},
          ) as RoundedRectangleBorder).side.style,
          BorderStyle.none,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('$mode details and settings at desktop and narrow widths', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        LauncherApp(initialThemeMode: mode, saveAppearance: (_) async {}),
      );
      for (final size in [const Size(900, 550), const Size(700, 560)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        // Compact navigation exposes labels in its tooltips.
        await tester.tap(find.byTooltip('已安装 Mod').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('查看详情').first);
        await tester.pumpAndSettle();
        expect(find.text('本地 Mod 详情'), findsOneWidget);
        expect(find.text('支持版本'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ModDetails),
            matching: find.text('brrainz.harmony'),
          ),
          findsOneWidget,
        );
        expect(find.text('更新 Mod'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('close-details')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('设置').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode == ThemeMode.light ? '深色' : '浅色').first);
      await tester.pumpAndSettle();
      final context = tester.element(find.text('外观主题').first);
      expect(
        FluentTheme.of(context).brightness,
        mode == ThemeMode.light ? Brightness.dark : Brightness.light,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$mode workshop long title and description remain scrollable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final longPath =
          r'G:\Games\游戏与模组\RimWorld\Mods\' + 'long_folder_name_' * 12;
      final longTitle = '拥有很长名称的创意工坊模组 ' * 5;
      await tester.pumpWidget(
        FluentApp(
          theme: launcherTheme(
            mode == ThemeMode.light ? Brightness.light : Brightness.dark,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Button(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => ModDetails(
                  title: longTitle,
                  category: '创意工坊详情',
                  previewUrl: '',
                  description:
                      '[h1]模组说明[/h1]\n[b]功能[/b]\n[list][*]说明内容[/list]\n' * 30,
                  fields: [
                    DetailField('工坊 ID', '1504723424'),
                    DetailField('安装目录', longPath),
                  ],
                  target: longPath,
                  actionLabel: '安装到当前游戏',
                ),
              ),
              child: const Text('打开详情'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();
      expect(find.text('安装到当前游戏'), findsOneWidget);
      expect(find.text(longTitle), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('mod-description-scroll')),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();
      final text = tester
          .widget<SelectableText>(find.byType(SelectableText).last)
          .textSpan!
          .toPlainText();
      expect(text, contains('模组说明'));
      expect(text, isNot(contains('[h1]')));
      expect(text, contains('说明内容'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('close-details')));
      await tester.pumpAndSettle();
      expect(find.text('打开详情'), findsOneWidget);
    });
  }
}
