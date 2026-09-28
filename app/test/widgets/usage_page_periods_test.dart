import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/models/user_usage.dart';
import 'package:omi/pages/settings/usage_page.dart';
import 'package:omi/providers/usage_provider.dart';

/// Usage already on hand: nothing is fetched, so the page shows exactly what was seeded.
class _SeededUsage extends UsageProvider {
  @override
  Future<void> fetchUsageStats({required String period}) async {}
  @override
  Future<void> fetchSubscription() async {}
  @override
  Future<void> loadAvailablePlans() async {}
}

UsageStats _stats(int minutes) => UsageStats(
      transcriptionSeconds: minutes * 60,
      speechSeconds: minutes * 60,
      wordsTranscribed: minutes * 150,
      insightsGained: 3,
      memoriesCreated: 5,
    );

/// Plan & usage (#19347): the period is a sliding segmented control under the title, not tabs.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  testWidgets('Today · Month · Year · All time switch the stats shown', (tester) async {
    final usage = _SeededUsage()
      ..debugSetUsageStats('today', _stats(12))
      ..debugSetUsageStats('monthly', _stats(400));
    addTearDown(usage.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<UsageProvider>.value(
        value: usage,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: UsagePage(),
        ),
      ),
    );
    await tester.pump();
    final en = AppLocalizations.of(tester.element(find.byType(UsagePage)));

    expect(find.byType(TabBar), findsNothing);
    final period = find.byType(CupertinoSlidingSegmentedControl<int>);
    expect(period, findsOneWidget);
    expect(tester.widget<CupertinoSlidingSegmentedControl<int>>(period).groupValue, 0);
    expect(find.text('12m'), findsOneWidget, reason: "today's 12 minutes listened");

    await tester.tap(find.descendant(of: period, matching: find.text(en.usageMonth)));
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSlidingSegmentedControl<int>>(period).groupValue, 1);
    expect(find.text('6h 40m'), findsOneWidget, reason: "this month's 400 minutes listened");
    expect(find.text('12m'), findsNothing);
  });
}
