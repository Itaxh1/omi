import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';

import 'package:omi/pages/apps/providers/add_app_provider.dart';
import 'package:omi/pages/home/page.dart';
import 'package:omi/pages/home/widgets/home_ask_bar.dart';
import 'package:omi/pages/home/widgets/home_pull.dart';
import 'package:omi/pages/home/widgets/home_top_bar.dart';
import 'package:omi/providers/action_items_provider.dart';
import 'package:omi/providers/announcement_provider.dart';
import 'package:omi/providers/app_provider.dart';
import 'package:omi/providers/auth_provider.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/goals_provider.dart';
import 'package:omi/providers/locale_provider.dart';
import 'package:omi/providers/local_recordings_provider.dart';
import 'package:omi/providers/memories_provider.dart';
import 'package:omi/providers/people_provider.dart';
import 'package:omi/providers/phone_call_provider.dart';
import 'package:omi/providers/sync_provider.dart';
import 'package:omi/providers/task_integration_provider.dart';
import 'package:omi/providers/user_provider.dart';
import 'package:omi/services/account_cutover/account_cutover_runtime.dart';
import 'package:omi/services/capture/local_segment_store.dart';
import 'package:omi/services/services.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';

import '../../integration_test/journeys/support/hermetic_boot.dart';

/// Home once its first-run tip is done (every launch after the first): the Scaffold gives its body
/// loose constraints, so one zero-size child in the body's Stack shrank the whole Stack to nothing
/// and left only the gradient on screen. The top bar, the page and the Ask bar must fill the screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home fills the screen when the first-run tip is not showing', (tester) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    _stubPlugins();
    setupFirebaseCoreMocks();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'fake',
          appId: '1:1:ios:fake',
          messagingSenderId: '1',
          projectId: 'demo-omi-local',
        ),
      );
    }
    AccountCutoverRuntime.instance.resetForTesting();
    await tester.runAsync(() async {
      await JourneyHermeticBoot.start(
        extraPrefs: {
          'onboardingCompleted': true,
          'permissionsCompleted': true,
          'aiConsentGiven': true,
          'home/omiTaught': true,
          'home/omiTapped': true,
          'home/omiOpens': 5,
        },
      );
      try {
        await ServiceManager.init();
      } catch (_) {}
    });
    addTearDown(JourneyHermeticBoot.stop);
    addTearDown(AccountCutoverRuntime.instance.resetForTesting);

    await JourneyHermeticBoot.pumpPage(tester, page: const HomePageWrapper(), providers: _homeProviders());
    // Past the moment the tip would have appeared.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HomePage), findsOneWidget);

    const screen = Size(430, 932);
    final pull = tester.getRect(find.byType(HomePullGestures));
    expect(pull.size, screen, reason: 'the top bar and the page lay out over the whole screen');

    final topBar = tester.getRect(find.byType(HomeTopBar));
    expect(topBar.width, screen.width);
    expect(topBar.height, greaterThan(0));

    final ask = tester.getRect(find.byKey(const Key('home_ask_bar')));
    expect(ask.width, screen.width - 2 * HomeAskBar.sideInset);
    expect(ask.height, kAskBarHeight);
    expect(ask.bottom, lessThan(screen.height), reason: 'the Ask bar sits inside the screen, above the home indicator');
    expect(ask.top, greaterThan(screen.height / 2));

    await tester.pumpWidget(const SizedBox.shrink());
    // Flush HomePage's pending timers (announcements, prewarm).
    await tester.pump(const Duration(milliseconds: 2100));
    expect(tester.takeException(), isNull);
  });
}

List<SingleChildWidget> _homeProviders() {
  return [
    ChangeNotifierProvider(create: (_) => AuthenticationProvider(initializeListeners: false)),
    ChangeNotifierProvider(create: (_) => CaptureProvider(localSegmentStore: LocalSegmentStore.disabled())),
    ChangeNotifierProvider(create: (_) => LocalRecordingsProvider()),
    ChangeNotifierProvider(
      create: (_) => DeviceProvider(
        bleDiagnosticsLoader: (_) async => throw StateError('fixture: BLE diagnostics unused'),
        findDeviceRunner: (_) async => false,
      ),
    ),
    ChangeNotifierProvider(create: (_) => AnnouncementProvider()),
    ChangeNotifierProvider(create: (_) => ActionItemsProvider()),
    ChangeNotifierProvider(create: (_) => SyncProvider(startBackgroundSync: false)),
    ChangeNotifierProvider(create: (_) => TaskIntegrationProvider()),
    ChangeNotifierProvider(create: (_) => PhoneCallProvider.forTesting()),
    ChangeNotifierProvider(create: (_) => GoalsProvider()),
    ChangeNotifierProxyProvider<AppProvider, AddAppProvider>(
      create: (_) => AddAppProvider(),
      update: (_, app, previous) => (previous?..setAppProvider(app)) ?? (AddAppProvider()..setAppProvider(app)),
    ),
    ChangeNotifierProvider(
      create: (_) =>
          UserProvider(privateCloudSyncFetcher: () async => false, privateCloudSyncSetter: (_) async => true),
    ),
    ChangeNotifierProvider(create: (_) => MemoriesProvider()),
    ChangeNotifierProvider(create: (_) => PeopleProvider()),
    ChangeNotifierProvider(create: (_) => LocaleProvider()),
  ];
}

void _stubPlugins() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channels = [
    'flutter_foreground_task/methods',
    'flutter.baseflow.com/geolocator',
    'dev.fluttercommunity.plus/connectivity',
    'dev.fluttercommunity.plus/connectivity_status',
    'xyz.luan/audioplayers',
    'plugins.flutter.io/path_provider',
    'plugins.flutter.io/shared_preferences',
    'plugins.flutter.io/firebase_messaging',
    'com.omi/phone_calls',
    'com.omi/phone_calls/events',
    'flutter.baseflow.com/permissions/methods',
  ];
  for (final name in channels) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      switch (call.method) {
        case 'check':
          return ['wifi'];
        case 'checkPermission':
        case 'checkPermissionStatus':
        case 'checkServiceStatus':
          return 1;
        case 'getAll':
          return <String, Object>{};
        case 'getApplicationDocumentsDirectory':
        case 'getTemporaryDirectory':
        case 'getApplicationSupportDirectory':
          return '/tmp/omi-home-layout';
        default:
          return null;
      }
    });
  }
  messenger.setMockStreamHandler(
    const EventChannel('com.omi/phone_calls/events'),
    MockStreamHandler.inline(onListen: (args, sink) {}, onCancel: (args) {}),
  );
}
