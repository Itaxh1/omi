import 'package:flutter/material.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:omi/ui/ui.dart';

Widget getMarkdownWidget(BuildContext context, String message, {Function(String)? onAskOmi}) {
  return MarkdownBody(
    data: message.trimRight(),
    selectable: false,
    // v3 Ask answers (`.an`): 19 pt on a 1.45 line, bold as semibold, short headings, and a little
    // air between list items.
    styleSheet: MarkdownStyleSheet(
      p: OmiType.answer,
      strong: const TextStyle(fontWeight: FontWeight.w600),
      h1: OmiType.title3.copyWith(fontWeight: FontWeight.w700, height: 1.3),
      h2: OmiType.headline.copyWith(fontSize: 19, height: 1.3),
      h3: OmiType.headline.copyWith(height: 1.35),
      h1Padding: const EdgeInsets.only(top: 6),
      h2Padding: const EdgeInsets.only(top: 6),
      h3Padding: const EdgeInsets.only(top: 4),
      blockSpacing: 10,
      listIndent: 20,
      listBulletPadding: const EdgeInsets.only(right: 6),
      // Links are neutral (INV-UI-1): white and underlined, not a blue accent.
      a: TextStyle(color: OmiColors.textPrimary, decoration: TextDecoration.underline),
      listBullet: OmiType.answer,
      blockquote: OmiType.answer.copyWith(backgroundColor: Colors.transparent),
      blockquoteDecoration: BoxDecoration(color: OmiColors.surface2, borderRadius: OmiRadius.smAll),
      code: TextStyle(
        color: OmiColors.textPrimary,
        backgroundColor: Colors.transparent,
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(color: OmiColors.surface1, borderRadius: OmiRadius.smAll),
    ),
    onTapLink: (text, href, title) {
      if (href != null) {
        launchUrl(Uri.parse(href));
      }
    },
  );
}
