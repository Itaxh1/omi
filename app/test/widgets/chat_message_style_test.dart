import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/backend/schema/message.dart';
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

  testWidgets('the question sits in an ink outline with no fill, its corner by the composer squared off',
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
    expect(border.top.color, OmiColors.textPrimary);
    expect(border.top.width, 1.5);
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
}
