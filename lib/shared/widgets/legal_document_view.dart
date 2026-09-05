/// A lightweight renderer that displays a legal markdown document
/// (headings, paragraphs, bullets, simple tables) in flowing paragraph
/// style — no card containers.
library;

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Renders the contents of a legal markdown asset as plain, document-style
/// paragraphs.
class LegalDocumentView extends StatelessWidget {
  const LegalDocumentView({super.key, required this.markdown});

  /// Raw markdown text of the document.
  final String markdown;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(markdown);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s4,
        AppTokens.s4,
        AppTokens.s4,
        AppTokens.s8,
      ),
      itemCount: blocks.length,
      itemBuilder: (context, index) => blocks[index].build(context),
    );
  }
}

abstract class _Block {
  Widget build(BuildContext context);
}

class _Heading implements _Block {
  _Heading(this.text, this.level);

  final String text;
  final int level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTitle = level <= 1;
    return Padding(
      padding: EdgeInsets.only(
        top: isTitle ? 0 : AppTokens.s6,
        bottom: AppTokens.s2,
      ),
      child: Text(
        text,
        style: isTitle
            ? theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              )
            : theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
      ),
    );
  }
}

class _Paragraph implements _Block {
  _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s3),
      child: _RichText(
        text: text,
        style: theme.textTheme.bodyMedium!.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.55,
        ),
      ),
    );
  }
}

/// A bulleted list rendered as an indented group of paragraphs.
class _BulletList implements _Block {
  _BulletList(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.55,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == items.length - 1 ? 0 : AppTokens.s2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: style),
                  Expanded(child: _RichText(text: items[i], style: style!)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A markdown table rendered as plain paragraphs (header bold, rows joined).
class _Table implements _Block {
  _Table(this.rows);

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.55,
    );
    final headerStyle = bodyStyle?.copyWith(fontWeight: FontWeight.w700);
    final header = rows.first;
    final dataRows = rows.skip(1).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RichText(text: header.join(' — '), style: headerStyle!),
          for (final row in dataRows)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s2),
              child: _RichText(text: row.join(' — '), style: bodyStyle!),
            ),
        ],
      ),
    );
  }
}

class _Divider implements _Block {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppTokens.s3),
      child: Divider(height: 1),
    );
  }
}

/// Text with `**bold**`, `*italic*`, and `` `code` `` inline markup resolved.
class _RichText extends StatelessWidget {
  const _RichText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`');
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final bold = match.group(1) ?? match.group(2);
      final code = match.group(3);
      if (bold != null) {
        spans.add(
          TextSpan(
            text: bold,
            style: TextStyle(fontWeight: FontWeight.w700, color: style.color),
          ),
        );
      } else if (code != null) {
        spans.add(
          TextSpan(
            text: code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: style.fontSize != null ? style.fontSize! - 1 : null,
              color: style.color,
            ),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

List<_Block> _parseBlocks(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_Block>[];
  var paragraph = <String>[];
  var bullets = <String>[];
  var table = <List<String>>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(_Paragraph(paragraph.join(' ').trim()));
    paragraph = [];
  }

  void flushBullets() {
    if (bullets.isEmpty) return;
    blocks.add(_BulletList([for (final b in bullets) b.trim()]));
    bullets = [];
  }

  void flushTable() {
    if (table.isEmpty) return;
    // Drop the alignment separator row (--- | ---).
    final rows = table
        .where((r) => !r.every((c) => RegExp(r'^:?-+:?$').hasMatch(c)))
        .toList();
    if (rows.isNotEmpty) blocks.add(_Table(rows));
    table = [];
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.startsWith('|') && line.endsWith('|')) {
      flushParagraph();
      flushBullets();
      table.add(
        line.substring(1, line.length - 1).split('|').map((c) => c.trim()).toList(),
      );
      continue;
    }
    flushTable();

    if (line.isEmpty) {
      flushParagraph();
      flushBullets();
      continue;
    }
    if (line == '---' || line == '***') {
      flushParagraph();
      flushBullets();
      blocks.add(const _Divider());
      continue;
    }
    if (line.startsWith('#')) {
      flushParagraph();
      flushBullets();
      var level = 0;
      while (level < line.length && line[level] == '#') {
        level++;
      }
      blocks.add(_Heading(line.substring(level).trim(), level));
      continue;
    }
    if (line.startsWith('- ') || line.startsWith('* ')) {
      flushParagraph();
      bullets.add(line.substring(2));
      continue;
    }
    paragraph.add(line);
  }
  flushParagraph();
  flushBullets();
  flushTable();
  return blocks;
}

