import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/backend/schema/message.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/chat/widgets/message_action_bar.dart';
import 'package:omi/pages/chat/widgets/markdown_message_widget.dart';
import 'package:omi/pages/chat/widgets/user_message.dart';
import 'package:omi/ui/ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(
          theme: buildOmiTheme(),
          home: Scaffold(body: child),
        ),
      );

  testWidgets('the question sits in a hairline outline with no fill, its corner by the composer squared off',
      (tester) async {
    final message = ServerMessage(
      'q1',
      DateTime.utc(2026),
      'Did Dan send the model link?',
      MessageSender.human,
      MessageType.text,
      null,
      false,
      [],
      [],
      [],
    );
    await pump(tester, HumanMessage(message: message));

    final box = tester.widget<Container>(find.byKey(const Key('chat_user_message')));
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, isNull, reason: 'no filled bubble');
    final border = decoration.border! as Border;
    expect(border.top.color, OmiColors.border, reason: 'a hairline, not an ink outline');
    expect(border.top.width, 1);
    final corners = decoration.borderRadius! as BorderRadius;
    expect(corners.topLeft, const Radius.circular(OmiRadius.lg));
    expect(corners.bottomLeft, const Radius.circular(OmiRadius.lg));
    expect(corners.bottomRight.x, lessThan(OmiRadius.lg), reason: 'the corner nearest the composer is squared off');
    expect(find.text('Did Dan send the model link?'), findsOneWidget);
  });

  testWidgets("Omi's answer is larger than the question, in a regular weight, and no heading is smaller",
      (tester) async {
    await pump(
        tester, Builder(builder: (context) => getMarkdownWidget(context, 'Not sure. Nothing about that today.')));

    final sheet = tester.widget<MarkdownBody>(find.byType(MarkdownBody)).styleSheet!;
    final words = sheet.p!;
    expect(words.fontSize, greaterThan(OmiType.callout.fontSize!),
        reason: 'the question is callout; the answer reads larger');
    expect(words.fontWeight, FontWeight.w400);
    expect(sheet.listBullet!.fontSize, words.fontSize, reason: 'list items read at the same size as the words');
    for (final heading in [sheet.h1, sheet.h2, sheet.h3, sheet.h4, sheet.h5, sheet.h6]) {
      expect(heading!.fontSize, greaterThanOrEqualTo(words.fontSize!));
    }
    expect(find.text('Not sure. Nothing about that today.'), findsOneWidget);
  });

  testWidgets('a "[1]" pointing at a source is small and quiet, inside its sentence', (tester) async {
    await pump(
      tester,
      Builder(
          builder: (context) => getMarkdownWidget(context, 'Not about the V2 yet. [1] See [the doc](https://omi.me).')),
    );

    final paragraph = tester.widget<RichText>(find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText().contains('Not about the V2 yet.'),
    ));
    expect(paragraph.text.toPlainText(), contains('[1]'),
        reason: 'the marker stays in the sentence, not on its own line');
    TextStyle? markerStyle;
    paragraph.text.visitChildren((span) {
      if (span is TextSpan && span.text == '[1]') markerStyle = span.style;
      return markerStyle == null;
    });
    expect(markerStyle?.fontSize, OmiType.footnote.fontSize);
    expect(markerStyle?.color, OmiColors.textTertiary);
    expect(paragraph.text.toPlainText(), contains('the doc'), reason: 'a real link is untouched');
  });

  testWidgets('Copy, Helpful, Not Helpful and Share are small quiet glyphs on 44 pt targets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildOmiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: MessageActionBar(messageText: 'An answer')),
      ),
    );

    final glyphs = tester.widgetList<FaIcon>(find.byType(FaIcon)).toList();
    expect(glyphs, hasLength(4));
    for (final glyph in glyphs) {
      expect(glyph.size, 15);
      expect(glyph.color, OmiColors.textTertiary);
    }
    for (final label in ['Copy Message', 'Helpful', 'Not Helpful', 'Share']) {
      expect(tester.getSize(find.bySemanticsLabel(label)), const Size(44, 44));
    }
  });
}
