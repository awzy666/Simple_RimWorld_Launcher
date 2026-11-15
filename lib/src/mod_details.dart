import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import 'app_theme.dart';
import 'ui.dart';

class DetailField {
  const DetailField(this.label, this.value);
  final String label, value;
}

/// A compact reading view sized for the fixed launcher window.
class ModDetails extends StatelessWidget {
  const ModDetails({
    super.key,
    required this.title,
    required this.category,
    required this.fields,
    this.previewUrl,
    this.description,
    this.issue = '',
    this.target,
    this.actionLabel,
    this.onAction,
  });
  final String title, category, issue;
  final List<DetailField> fields;
  final String? previewUrl, description, target, actionLabel;
  final VoidCallback? onAction;

  Widget metadata(BuildContext context, {bool singleColumn = false}) {
    final t = FluentTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = !singleColumn && constraints.maxWidth >= 560;
        return Wrap(
          spacing: 20,
          runSpacing: 12,
          children: [
            for (final field in fields)
              SizedBox(
                width: !columns || field.label == '安装目录'
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 20) / 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(field.label, style: t.typography.caption),
                    const SizedBox(height: 3),
                    SelectableText(
                      field.value.isEmpty ? '未提供' : field.value,
                      style: t.typography.body,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = FluentTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: 860,
          height: math.min(720, size.height - 24),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x30000000),
                blurRadius: 32,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(category, style: t.typography.caption),
                          const SizedBox(height: 2),
                          Tooltip(
                            message: title,
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.typography.subtitle?.copyWith(
                                fontSize: 20,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Tooltip(
                      message: '关闭详情',
                      child: IconButton(
                        key: const ValueKey('close-details'),
                        icon: const Icon(FluentIcons.chrome_close, size: 16),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: description == null
                      ? SingleChildScrollView(
                          primary: false,
                          key: const ValueKey('mod-details-body'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              metadata(context),
                              if (issue.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                InfoBar(
                                  title: const Text('Mod 信息读取异常'),
                                  content: SelectableText(issue),
                                  severity: InfoBarSeverity.error,
                                ),
                              ],
                            ],
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final information = Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    height: 92,
                                    child: ModPreview(
                                      url: previewUrl ?? '',
                                      contain: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                metadata(context, singleColumn: true),
                              ],
                            );
                            final reading = Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('关于此 Mod', style: t.typography.bodyStrong),
                                const SizedBox(height: 8),
                                SteamDescription(
                                  description!.isEmpty ? '暂无说明' : description!,
                                ),
                              ],
                            );
                            return constraints.maxWidth >= 640
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        width: 200,
                                        child: SingleChildScrollView(
                                          primary: false,
                                          child: information,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Container(width: 1, color: c.border),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          primary: false,
                                          key: const ValueKey(
                                            'mod-description-scroll',
                                          ),
                                          child: reading,
                                        ),
                                      ),
                                    ],
                                  )
                                : SingleChildScrollView(
                                    primary: false,
                                    key: const ValueKey(
                                      'mod-description-scroll',
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        information,
                                        const SizedBox(height: 20),
                                        reading,
                                      ],
                                    ),
                                  );
                          },
                        ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: c.background,
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final location = Tooltip(
                      message: target ?? '请先在首页选择游戏',
                      child: Text(
                        target == null ? '请先在首页选择游戏' : '目标游戏 · $target',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.typography.caption,
                      ),
                    );
                    final actions = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ActionButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                        if (actionLabel != null) ...[
                          const SizedBox(width: 8),
                          ActionButton.primary(
                            onPressed: onAction,
                            child: Text(actionLabel!),
                          ),
                        ],
                      ],
                    );
                    return constraints.maxWidth >= 600
                        ? Row(
                            children: [
                              Expanded(child: location),
                              const SizedBox(width: 16),
                              actions,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              location,
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: actions,
                              ),
                            ],
                          );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Render Steam's common BBCode without taking foreground colors from a Mod.
class SteamDescription extends StatelessWidget {
  const SteamDescription(this.source, {super.key});
  final String source;

  @override
  Widget build(BuildContext context) {
    final t = FluentTheme.of(context);
    final c = AppColors.of(context);
    final spans = <TextSpan>[];
    final active = <String>[];
    final links = <String>[];
    final tags = RegExp(r'\[(/?)([a-zA-Z*][\w*]*)(?:[= ][^\]]*)?\]');
    final blocks = {
      'h1',
      'h2',
      'h3',
      'list',
      'olist',
      'quote',
      'code',
      'table',
      'tr',
    };
    var offset = 0;
    var consecutiveNewlines = 2;
    var pendingIndentation = '';
    void add(String text) {
      // Normalize after BBCode has added its own block separators as well.
      // Whitespace-only lines count as blank, including CRLF input.
      text = text
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .replaceAll(RegExp(r'[ \t\u00a0]+\n'), '\n');
      final normalized = StringBuffer();
      for (final char in text.split('')) {
        if (char == '\n') {
          pendingIndentation = '';
          if (consecutiveNewlines < 2) normalized.write(char);
          consecutiveNewlines++;
        } else {
          if (consecutiveNewlines > 0 &&
              (char == ' ' || char == '\t' || char == '\u00a0')) {
            pendingIndentation += char;
            continue;
          }
          if (pendingIndentation.isNotEmpty) {
            normalized.write(pendingIndentation);
            pendingIndentation = '';
          }
          normalized.write(char);
          consecutiveNewlines = 0;
        }
      }
      text = normalized.toString();
      if (text.isEmpty) return;
      final heading = active.any(
        (tag) => tag == 'h1' || tag == 'h2' || tag == 'h3',
      );
      spans.add(
        TextSpan(
          text: text,
          style: TextStyle(
            fontSize: heading ? 19 : 14,
            fontWeight: heading || active.contains('b')
                ? FontWeight.w600
                : FontWeight.w400,
            fontStyle: active.contains('i')
                ? FontStyle.italic
                : FontStyle.normal,
            decoration: active.contains('u') || active.contains('url')
                ? TextDecoration.underline
                : TextDecoration.none,
            color: active.contains('url') ? c.accent : c.text,
          ),
        ),
      );
    }

    for (final tag in tags.allMatches(source)) {
      add(source.substring(offset, tag.start));
      final name = tag[2]!.toLowerCase();
      final closing = tag[1] == '/';
      if (blocks.contains(name)) add('\n\n');
      if (name == '*' || name == 'li') add(closing ? '\n' : '\n•  ');
      if (name == 'br' || name == 'hr') add('\n');
      if (closing) {
        if (name == 'url' && links.isNotEmpty) {
          final destination = links.removeLast();
          if (destination.isNotEmpty) add(' ($destination)');
        }
        final index = active.lastIndexOf(name);
        if (index >= 0) active.removeAt(index);
      } else {
        active.add(name);
        if (name == 'url') {
          final raw = tag[0]!;
          final equals = raw.indexOf('=');
          links.add(
            equals < 0 ? '' : raw.substring(equals + 1, raw.length - 1),
          );
        }
      }
      offset = tag.end;
    }
    add(source.substring(offset));
    while (spans.isNotEmpty) {
      final last = spans.last;
      final trimmed = last.text!.trimRight();
      if (trimmed.isNotEmpty) {
        spans[spans.length - 1] = TextSpan(text: trimmed, style: last.style);
        break;
      }
      spans.removeLast();
    }
    return SelectableText.rich(
      TextSpan(
        style: t.typography.body?.copyWith(height: 1.85),
        children: spans,
      ),
    );
  }
}
