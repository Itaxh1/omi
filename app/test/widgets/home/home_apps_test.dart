import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/schema/app.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/home/widgets/home_sections.dart';
import 'package:omi/providers/app_provider.dart';

class _Apps extends ChangeNotifier implements AppProvider {
  _Apps({List<App> apps = const [], List<App> popular = const []})
      : _apps = apps,
        _popular = popular;

  final List<App> _apps;
  final List<App> _popular;

  @override
  List<App> get apps => _apps;

  @override
  List<App> get popularApps => _popular;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

App _app(String id, {bool enabled = false}) => App.fromJson({
      'id': id,
      'name': 'App $id',
      'author': 'Omi',
      'description': 'd',
      'image': '',
      'category': 'productivity-and-organization',
      'capabilities': ['memories'],
      'enabled': enabled,
    });

Future<List<String>> _pump(WidgetTester tester, AppProvider apps) async {
  final opened = <String>[];
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: apps,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: HomeApps(onAllApps: () => opened.add('store'))),
      ),
    ),
  );
  await tester.pump();
  return opened;
}

void main() {
  testWidgets('Home ends with three of the reader\'s apps and + for the app store', (tester) async {
    final opened = await _pump(
      tester,
      _Apps(apps: [
        _app('a', enabled: true),
        _app('off'),
        _app('b', enabled: true),
        _app('c', enabled: true),
        _app('d', enabled: true),
      ]),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeApps)));

    expect(find.byKey(const Key('home_app_a')), findsOneWidget);
    expect(find.byKey(const Key('home_app_b')), findsOneWidget);
    expect(find.byKey(const Key('home_app_c')), findsOneWidget);
    expect(find.byKey(const Key('home_app_d')), findsNothing, reason: 'three apps, then +');
    expect(find.byKey(const Key('home_app_off')), findsNothing, reason: 'only enabled apps');
    expect(find.text(l10n.homeAppsMore), findsOneWidget);

    await tester.tap(find.byKey(const Key('home_apps_more')));
    expect(opened, ['store']);
  });

  testWidgets('before any app is enabled it offers popular ones to try', (tester) async {
    await _pump(tester, _Apps(popular: [_app('p1'), _app('p2'), _app('p3'), _app('p4')]));

    expect(find.byKey(const Key('home_app_p1')), findsOneWidget);
    expect(find.byKey(const Key('home_app_p3')), findsOneWidget);
    expect(find.byKey(const Key('home_app_p4')), findsNothing);
    expect(find.byKey(const Key('home_apps_more')), findsOneWidget);
  });

  testWidgets('with no apps at all, + still opens the store', (tester) async {
    final opened = await _pump(tester, _Apps());

    await tester.tap(find.byKey(const Key('home_apps_more')));
    expect(opened, ['store']);
  });
}
