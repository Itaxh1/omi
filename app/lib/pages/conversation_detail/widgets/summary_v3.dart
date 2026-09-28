import 'package:flutter/material.dart';

import 'package:omi/ui/ui.dart';

/// A conversation's summary as the v3 mock sets it (`.sum`): headings at 17/600, bullets at 17 pt
/// on a 1.5 line in the 80 % ink, paragraphs the same. Reads the summary's markdown: `#` headings,
/// `-`/`*`/`•`/`1.` bullets, `**bold**`, blank lines.
class SummaryV3 extends StatelessWidget {
  const SummaryV3({super.key, required this.markdown});

  final String markdown;

  static final RegExp _heading = RegExp(r'^#{1,6}\s+');
  static final RegExp _bullet = RegExp(r'^(\s*)([-*•]|\d+[.)])\s+');
  static final RegExp _bold = RegExp(r'\*\*(.+?)\*\*');

  @override
  Widget build(BuildContext context) {
    final body = OmiType.body.copyWith(fontWeight: FontWeight.w400, height: 1.5, color: OmiColors.ink80);
    final heading = OmiType.body.copyWith(fontWeight: FontWeight.w600, height: 1.4);
    final children = <Widget>[];
    var first = true;
    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      if (_heading.hasMatch(line)) {
        children.add(Padding(
          padding: EdgeInsets.only(top: first ? 18 : 26, bottom: 6),
          child: Semantics(header: true, child: Text(_plain(line.replaceFirst(_heading, '')), style: heading)),
        ));
      } else if (_bullet.hasMatch(line)) {
        final text = line.replaceFirst(_bullet, '');
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Text('•', style: body.copyWith(color: OmiColors.textPrimary)),
              ),
              Expanded(child: Text.rich(_spans(text), style: body)),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: EdgeInsets.only(top: first ? 18 : 8, bottom: 4),
          child: Text.rich(_spans(line.trim()), style: body),
        ));
      }
      first = false;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  static String _plain(String text) => text.replaceAllMapped(_bold, (m) => m.group(1)!);

  static TextSpan _spans(String text) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _bold.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w600)));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(children: spans);
  }
}
