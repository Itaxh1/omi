import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/ui/ui.dart';

void main() {
  testWidgets('editor surface reaches beneath the keyboard while controls stay above it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: TextButton(
            onPressed: () => showOmiEditSheet<void>(
              context: context,
              builder: (_) => const OmiEditSheet(
                title: 'Edit Task',
                isDirty: false,
                child: SizedBox(key: Key('editor_controls'), height: 180),
              ),
            ),
            child: const Text('Edit'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final surface = find.byKey(const Key('omi_edit_sheet_surface'));
    expect(tester.getBottomLeft(surface).dy, 844);
    expect(tester.widget<Material>(surface).color, OmiColors.sheet);
    expect(tester.getBottomLeft(find.byKey(const Key('editor_controls'))).dy, lessThanOrEqualTo(524));
    expect(tester.takeException(), isNull);
  });
}
