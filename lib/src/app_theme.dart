import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// Opaque foreground/surface pairs keep contrast predictable in both themes.
class AppColors {
  final Color background, sidebar, surface, elevated, border;
  final Color text, secondary, accent, onAccent, selection, danger;
  final Color officialBackground, officialText;
  const AppColors({
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.elevated,
    required this.border,
    required this.text,
    required this.secondary,
    required this.accent,
    required this.onAccent,
    required this.selection,
    required this.danger,
    required this.officialBackground,
    required this.officialText,
  });
  static const light = AppColors(
    background: Color(0xfff4f6fa),
    sidebar: Color(0xffedf0f6),
    surface: Color(0xffffffff),
    elevated: Color(0xffe9edf5),
    border: Color(0xffd4dbe7),
    text: Color(0xff1c2638),
    secondary: Color(0xff526078),
    accent: Color(0xff2459c4),
    onAccent: Color(0xffffffff),
    selection: Color(0xffdde7fc),
    danger: Color(0xffb32c36),
    officialBackground: Color(0xfffcedc7),
    officialText: Color(0xff704414),
  );
  static const dark = AppColors(
    background: Color(0xff131923),
    sidebar: Color(0xff10151e),
    surface: Color(0xff1c2533),
    elevated: Color(0xff273344),
    border: Color(0xff3b485d),
    text: Color(0xffedf2fc),
    secondary: Color(0xffb5c1d5),
    accent: Color(0xffa9c2ff),
    onAccent: Color(0xff13203b),
    selection: Color(0xff30446b),
    danger: Color(0xffffa9b0),
    officialBackground: Color(0xff44341b),
    officialText: Color(0xfff5d487),
  );
  static AppColors of(BuildContext context) =>
      FluentTheme.of(context).brightness == Brightness.dark ? dark : light;
}

WidgetStateProperty<BoxDecoration> inputDecoration(BuildContext context) {
  final c = AppColors.of(context);
  final border = FluentTheme.of(context).brightness == Brightness.dark
      ? const Color(0xff71839f)
      : const Color(0xff8190a7);
  return WidgetStateProperty.resolveWith(
    (states) => BoxDecoration(
      color: states.isDisabled ? c.elevated : c.surface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: states.isFocused ? c.accent : border),
    ),
  );
}

FluentThemeData launcherTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final resources = brightness == Brightness.dark
      ? ResourceDictionary.dark(
          textFillColorPrimary: c.text,
          textFillColorSecondary: c.secondary,
          textFillColorTertiary: c.secondary,
          textFillColorDisabled: c.secondary,
          textOnAccentFillColorPrimary: c.onAccent,
          textOnAccentFillColorSecondary: c.onAccent,
          textOnAccentFillColorDisabled: c.secondary,
          textOnAccentFillColorSelectedText: c.onAccent,
          controlFillColorDefault: c.surface,
          controlFillColorSecondary: c.elevated,
          controlFillColorTertiary: c.elevated,
          controlFillColorDisabled: c.elevated,
          controlFillColorInputActive: c.background,
          controlSolidFillColorDefault: c.surface,
          accentFillColorDisabled: c.elevated,
          controlStrokeColorDefault: c.border,
          controlStrokeColorSecondary: c.border,
          controlStrongStrokeColorDefault: c.secondary,
          cardStrokeColorDefault: c.border,
          dividerStrokeColorDefault: c.border,
          cardBackgroundFillColorDefault: c.surface,
          subtleFillColorSecondary: c.elevated,
          subtleFillColorTertiary: c.elevated,
        )
      : ResourceDictionary.light(
          textFillColorPrimary: c.text,
          textFillColorSecondary: c.secondary,
          textFillColorTertiary: c.secondary,
          textFillColorDisabled: c.secondary,
          textOnAccentFillColorPrimary: c.onAccent,
          textOnAccentFillColorSecondary: c.onAccent,
          textOnAccentFillColorDisabled: c.secondary,
          textOnAccentFillColorSelectedText: c.onAccent,
          controlFillColorDefault: c.surface,
          controlFillColorSecondary: c.elevated,
          controlFillColorTertiary: c.elevated,
          controlFillColorDisabled: c.elevated,
          controlFillColorInputActive: c.surface,
          controlSolidFillColorDefault: c.surface,
          accentFillColorDisabled: c.elevated,
          controlStrokeColorDefault: c.border,
          controlStrokeColorSecondary: c.border,
          controlStrongStrokeColorDefault: c.secondary,
          cardStrokeColorDefault: c.border,
          dividerStrokeColorDefault: c.border,
          cardBackgroundFillColorDefault: c.surface,
          subtleFillColorSecondary: c.elevated,
          subtleFillColorTertiary: c.elevated,
        );
  final controlBorder = brightness == Brightness.dark
      ? const Color(0xff71839f)
      : const Color(0xff8190a7);
  final shape = WidgetStateProperty.resolveWith<ShapeBorder>(
    (states) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: states.isDisabled ? c.border : controlBorder),
    ),
  );
  const buttonText = WidgetStatePropertyAll(
    TextStyle(fontSize: 13, height: 1, fontWeight: FontWeight.w500),
  );
  const buttonPadding = WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  );
  final typography = Typography.raw(
    titleLarge: TextStyle(
      fontSize: 34,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: c.text,
    ),
    title: TextStyle(
      fontSize: 26,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: c.text,
    ),
    subtitle: TextStyle(
      fontSize: 19,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: c.text,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.6, color: c.text),
    body: TextStyle(fontSize: 14, height: 1.5, color: c.text),
    bodyStrong: TextStyle(
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: c.text,
    ),
    caption: TextStyle(fontSize: 12, height: 1.5, color: c.secondary),
  );
  return FluentThemeData(
    brightness: brightness,
    visualDensity: VisualDensity.standard,
    fontFamily: 'Segoe UI',
    typography: typography,
    accentColor: c.accent.toAccentColor(),
    activeColor: c.onAccent,
    inactiveColor: c.text,
    inactiveBackgroundColor: c.elevated,
    scaffoldBackgroundColor: c.background,
    cardColor: c.surface,
    menuColor: c.surface,
    micaBackgroundColor: c.sidebar,
    selectionColor: c.selection,
    resources: resources,
    iconTheme: IconThemeData(color: c.secondary, size: 16),
    buttonTheme: ButtonThemeData(
      defaultButtonStyle: ButtonStyle(
        shape: shape,
        padding: buttonPadding,
        textStyle: buttonText,
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.isDisabled ? c.elevated : c.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.isDisabled ? c.secondary : c.text,
        ),
      ),
      filledButtonStyle: ButtonStyle(
        shape: WidgetStateProperty.resolveWith(
          (states) => RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: states.isDisabled ? c.border : c.accent),
          ),
        ),
        padding: buttonPadding,
        textStyle: buttonText,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.isDisabled ? c.secondary : c.onAccent,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.isDisabled ? c.elevated : c.accent,
        ),
      ),
      iconButtonStyle: ButtonStyle(
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
            side: BorderSide.none,
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(7)),
        iconSize: const WidgetStatePropertyAll(16),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.isDisabled ? c.secondary : c.text,
        ),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    dialogTheme: ContentDialogThemeData(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      titleStyle: typography.subtitle,
      bodyStyle: typography.body,
    ),
  );
}

class Appearance {
  static File? get _file {
    final root =
        Platform.environment['RIMLAUNCHER_DATA'] ??
        (Platform.environment['LOCALAPPDATA'] == null
            ? null
            : '${Platform.environment['LOCALAPPDATA']}/RimWorldLauncher');
    return root == null ? null : File('$root/appearance.json');
  }

  static Future<ThemeMode> read() async {
    try {
      final file = _file;
      if (file == null || !await file.exists()) return ThemeMode.system;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return ThemeMode.values.firstWhere(
        (m) => m.name == data['themeMode'],
        orElse: () => ThemeMode.system,
      );
    } on Object {
      return ThemeMode.system;
    }
  }

  static Future<void> save(ThemeMode mode) async {
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'themeMode': mode.name}), flush: true);
  }
}

class WindowTheme extends StatefulWidget {
  const WindowTheme({super.key, required this.brightness, required this.child});
  final Brightness brightness;
  final Widget child;
  @override
  State<WindowTheme> createState() => _WindowThemeState();
}

class _WindowThemeState extends State<WindowTheme> {
  static const channel = MethodChannel('rimworld_launcher/appearance');
  @override
  void initState() {
    super.initState();
    updateFrame();
  }

  @override
  void didUpdateWidget(covariant WindowTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brightness != widget.brightness) updateFrame();
  }

  Future<void> updateFrame() async {
    try {
      await channel.invokeMethod<void>(
        'setDark',
        widget.brightness == Brightness.dark,
      );
    } on MissingPluginException {
      // Widget tests and older runners can still render the Flutter theme.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
