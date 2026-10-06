import 'package:flutter/material.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:omi/ui/ui.dart';

/// Omi's answer in chat (Omi v8 `.an`): the words in a larger regular type than the question, with
/// no bubble. Headings keep the answer's size and take the weight; none is smaller than the words.
Widget getMarkdownWidget(BuildContext context, String message, {Function(String)? onAskOmi}) {
  final words = OmiType.title3.copyWith(fontWeight: FontWeight.w400, height: 1.45);
  final heading = OmiType.title3.copyWith(height: 1.3);
  return MarkdownBody(
    data: message.trimRight(),
    selectable: false,
    styleSheet: MarkdownStyleSheet(
      p: words,
      h1: OmiType.title2.copyWith(height: 1.25),
      h2: heading,
      h3: heading,
      h4: heading,
      h5: heading,
      h6: heading,
      // Links are neutral (INV-UI-1): white and underlined, not a blue accent.
      a: TextStyle(color: OmiColors.textPrimary, decoration: TextDecoration.underline),
      listBullet: words,
      blockquote: words.copyWith(backgroundColor: Colors.transparent),
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
