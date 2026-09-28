import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:upgrader/upgrader.dart';

import 'package:omi/backend/http/api/users.dart';
import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/backend/schema/geolocation.dart';
import 'package:omi/gen/pigeon_communicator.g.dart';
import 'package:omi/pages/action_items/todo_list_page.dart';
import 'package:omi/pages/memories/page.dart';
import 'package:omi/pages/chat/page.dart';
import 'package:omi/pages/conversations/all_conversations_page.dart';
import 'package:omi/pages/home/home_content.dart';
import 'package:omi/pages/home/widgets/home_ask_bar.dart';
import 'package:omi/pages/home/widgets/folders_sidebar.dart';
import 'package:omi/pages/home/widgets/home_top_bar.dart';
import 'package:omi/pages/home/widgets/home_pull.dart';
import 'package:omi/pages/home/widgets/home_recorder_actions.dart';
import 'package:omi/pages/home/your_omi_page.dart';
import 'package:omi/pages/settings/settings_drawer.dart';
import 'package:omi/pages/settings/you_sheet.dart';
import 'package:omi/pages/settings/task_integrations_page.dart';
import 'package:omi/providers/action_items_provider.dart';
import 'package:omi/providers/app_provider.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/connectivity_provider.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/local_recordings_provider.dart';
import 'package:omi/providers/announcement_provider.dart';
import 'package:omi/providers/home_provider.dart';
import 'package:omi/providers/message_provider.dart';
import 'package:omi/providers/sync_provider.dart';
import 'package:omi/providers/task_integration_provider.dart';
import 'package:omi/services/integrations/apple_reminders_sync_service.dart';
import 'package:omi/services/quick_actions_service.dart';
import 'package:omi/utils/platform/platform_service.dart';
import 'package:omi/services/announcement_service.dart';
import 'package:omi/services/account_cutover/account_cutover_blocking_gate.dart';
import 'package:omi/services/notifications.dart';
import 'package:omi/services/wals/recording_transfer_coordinator.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/utils/audio/foreground.dart';
import 'package:omi/utils/analytics/background_resource_telemetry.dart';
import 'package:omi/utils/analytics/background_checkpoint_store.dart';
import 'package:omi/utils/analytics/analytics_manager.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/logger.dart';
import 'package:omi/utils/platform/platform_manager.dart';
import 'package:omi/widgets/freemium_switch_dialog.dart';
import 'package:omi/widgets/upgrade_alert.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';
import 'package:omi/services/sockets/listen_client_state.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/pages/apps/apps_v3.dart';
import 'package:omi/pages/chat/open_ask.dart';
import 'home_deep_links.dart';
import 'home_navigation.dart';
import 'home_widgets_publisher.dart';
import 'home_prompt_gate.dart';

class HomePageWrapper extends StatefulWidget {
  final String? navigateToRoute;
  const HomePageWrapper({super.key, this.navigateToRoute});

  @override
  State<HomePageWrapper> createState() => _HomePageWrapperState();
}

class _HomePageWrapperState extends State<HomePageWrapper> {
  @override
  Widget build(BuildContext context) {
    // Self-gate so onboarding/pushAndRemoveUntil destinations cannot boot
    // product traffic while cutover enforcement is blocking.
    return AccountCutoverBlockingGate(
      productBuilder: (context) => _HomePageProduct(navigateToRoute: widget.navigateToRoute),
    );
  }
}

class _HomePageProduct extends StatefulWidget {
  const _HomePageProduct({this.navigateToRoute});

  final String? navigateToRoute;

  @override
  State<_HomePageProduct> createState() => _HomePageProductState();
}

class _HomePageProductState extends State<_HomePageProduct> {
  String? _navigateToRoute;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        context.read<DeviceProvider>().initiateConnection('HomePageWrapper', boundDeviceOnly: true);
      }
      // Check actual system permission state — the SharedPreferences flag may
      // be stale (e.g. user granted via Settings > Permissions, or reinstall).
      final notifGranted = await Permission.notification.isGranted;
      if (!mounted) return;
      if (notifGranted) {
        SharedPreferencesUtil().notificationsEnabled = true;
        NotificationService.instance.register();
        NotificationService.instance.saveNotificationToken();
      }
    });
    _navigateToRoute = widget.navigateToRoute;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return HomePage(navigateToRoute: _navigateToRoute);
  }
}

class HomePage extends StatefulWidget {
  final String? navigateToRoute;
  const HomePage({super.key, this.navigateToRoute});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver, TickerProviderStateMixin {
  ForegroundUtil foregroundUtil = ForegroundUtil();

  final _upgrader = MyUpgrader(debugLogging: false, debugDisplayOnce: false);
  bool scriptsInProgress = false;
  StreamSubscription? _notificationStreamSubscription;

  final GlobalKey<HomeContentPageState> _homeContentPageKey = GlobalKey<HomeContentPageState>();

  // Freemium switch handler for auto-switch dialogs
  final FreemiumSwitchHandler _freemiumHandler = FreemiumSwitchHandler();

  // Holds startup prompts while recording, on a call or during a firmware update.
  final HomePromptGate _promptGate = HomePromptGate();

  late final BackgroundResourceTelemetry _backgroundResourceTelemetry = BackgroundResourceTelemetry(
    checkpointStore: PreferencesBackgroundCheckpointStore(),
    ownerKey: () => AnalyticsManager.currentIdentity ?? '',
    identityEpoch: () => AnalyticsManager.identityEpoch,
    enabled: () => AnalyticsManager.identityKnown && AnalyticsManager.trackingEnabled,
    emit: (eventName, properties) => PlatformManager.instance.analytics.track(eventName, properties: properties),
  );

  /// Home's controller, kept so dispose can clear the section hook without a context lookup.
  HomeProvider? _homeProvider;

  /// The pulls on Home (v8.6, v8.14): how far down (for the label) and up (for the dots).
  final ValueNotifier<HomePullPhase> _pullDown = ValueNotifier<HomePullPhase>(HomePullPhase.none);
  final ValueNotifier<double> _pullUp = ValueNotifier<double>(0);

  /// The first-run tip under the label, and the ring around the mark (v8.1).
  final ValueNotifier<bool> _teachTip = ValueNotifier<bool>(false);
  final ValueNotifier<int> _teachPulse = ValueNotifier<int>(0);

  CaptureProvider? _captureProvider;
  DeviceProvider? _deviceProviderForQuickActions;
  CaptureProvider? _captureProviderForQuickActions;
  Timer? _announcementTimer;
  Timer? _teachTimer;

  /// v3: Home is the root and everything else is pushed on top of it. `HomeProvider.setIndex`
  /// (links, notifications, widgets, quick actions) opens Conversations (1), To do (2) or Apps (3).
  void _onSectionRequested(int index) {
    if (index <= 0 || !mounted) return;
    context.read<HomeProvider>().selectedIndex = 0;
    unawaited(routeToPage(context, _sectionPage(index)));
  }

  static Widget _sectionPage(int index) => switch (index) {
        2 => const TodoListPage(),
        3 => const AddAnAppPage(),
        _ => const AllConversationsPage(),
      };

  /// Your Omi, from the label or the pull up. Tapping the mark ends the first-run tip.
  void _openOmi() {
    HomeTeach.markTapped();
    if (_teachTip.value) _teachDone();
    PlatformManager.instance.analytics.pageOpened('Your Omi');
    unawaited(openYourOmi(context));
  }

  void _teachDone() {
    HomeTeach.markTaught();
    _teachTip.value = false;
  }

  /// A moment after Home opens: the tip and two pulses the first time, one pulse on the third open
  /// if the mark was never tapped.
  void _teachOnArrival() {
    _teachTimer?.cancel();
    _teachTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final teach = HomeTeach.onHomeOpened();
      if (teach.tip) _teachTip.value = true;
      if (teach.tip || teach.nudge) {
        _teachPulse.value = 0;
        _teachPulse.value = teach.tip ? 2 : 1;
      }
    });
  }

  /// The folder button: the folders sidebar.
  void _openFolders() {
    unawaited(FoldersSidebar.show(context));
  }

  BackgroundResourceSnapshot _captureBackgroundResourceSnapshot({
    CaptureProvider? captureProvider,
    DeviceProvider? deviceProvider,
    bool foregroundTaskRunning = false,
    int backgroundDisconnectCount = 0,
    int connectionTimeoutCount = 0,
    int failToConnectCount = 0,
    int reconnectCount = 0,
    int maxReconnectDurationMs = 0,
    int reconnectionCountTotal = 0,
    int failToConnectCountTotal = 0,
    bool bleHistorySaturated = false,
    int nativeBackgroundBytesConsumed = 0,
    int nativeBackgroundPacketsConsumed = 0,
  }) {
    final capture = captureProvider ?? Provider.of<CaptureProvider>(context, listen: false);
    final devices = deviceProvider ?? Provider.of<DeviceProvider>(context, listen: false);
    final device = devices.connectedDevice ?? devices.pairedDevice;
    return BackgroundResourceSnapshot(
      bleBytesReceived: capture.lifetimeBleBytesReceived,
      websocketBytesSent: capture.lifetimeWsSocketBytesSent,
      recordingState: capture.recordingState.name,
      deviceConnected: devices.isConnected,
      deviceType: device?.type.name ?? 'none',
      batchModeEnabled: SharedPreferencesUtil().batchModeEnabled,
      foregroundTaskRunning: foregroundTaskRunning,
      backgroundDisconnectCount: backgroundDisconnectCount,
      connectionTimeoutCount: connectionTimeoutCount,
      failToConnectCount: failToConnectCount,
      reconnectCount: reconnectCount,
      maxReconnectDurationMs: maxReconnectDurationMs,
      reconnectionCountTotal: reconnectionCountTotal,
      failToConnectCountTotal: failToConnectCountTotal,
      bleHistorySaturated: bleHistorySaturated,
      nativeBackgroundBytesConsumed: nativeBackgroundBytesConsumed,
      nativeBackgroundPacketsConsumed: nativeBackgroundPacketsConsumed,
      diagnosticsDeviceId: device?.id,
    );
  }

  Future<BackgroundResourceSnapshot> _loadBackgroundResourceSnapshot(
    DateTime backgroundStartedAt,
    BackgroundResourceSnapshot startSnapshot,
  ) async {
    final captureProvider = Provider.of<CaptureProvider>(context, listen: false);
    final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
    final diagnosticsDeviceId = startSnapshot.diagnosticsDeviceId;
    var foregroundTaskRunning = false;
    try {
      foregroundTaskRunning = await FlutterForegroundTask.isRunningService;
    } catch (_) {}

    var backgroundDisconnectCount = 0;
    var connectionTimeoutCount = 0;
    var failToConnectCount = 0;
    var reconnectCount = 0;
    var maxReconnectDurationMs = 0;
    var reconnectionCountTotal = 0;
    var failToConnectCountTotal = 0;
    var bleHistorySaturated = false;
    var nativeBackgroundBytesConsumed = 0;
    var nativeBackgroundPacketsConsumed = 0;

    if (Platform.isIOS && diagnosticsDeviceId != null) {
      try {
        final diagnostics = await BleHostApi().getDeviceDiagnostics(diagnosticsDeviceId);
        final startMs = backgroundStartedAt.millisecondsSinceEpoch;
        final recentEvents =
            diagnostics.disconnectHistory.where((event) => event.timestamp >= startMs && !event.isManual).toList();
        final backgroundEvents =
            recentEvents.where((event) => event.appState == 'background' || event.appState == 'inactive').toList();
        backgroundDisconnectCount = backgroundEvents.where((event) => event.eventType == 'disconnect').length;
        failToConnectCount = backgroundEvents.where((event) => event.eventType == 'fail_to_connect').length;
        connectionTimeoutCount =
            backgroundEvents.where((event) => event.reason.toLowerCase().contains('timeout')).length;
        final reconnectedEvents = backgroundEvents.where((event) => event.timeToReconnectMs > 0).toList();
        reconnectCount = reconnectedEvents.length;
        for (final event in reconnectedEvents) {
          if (event.timeToReconnectMs > maxReconnectDurationMs) {
            maxReconnectDurationMs = event.timeToReconnectMs;
          }
        }
        reconnectionCountTotal = diagnostics.reconnectionCount;
        failToConnectCountTotal = diagnostics.failToConnectCount;
        bleHistorySaturated = diagnostics.disconnectHistory.length >= 20 &&
            diagnostics.disconnectHistory.every((event) => event.timestamp >= startMs);
        nativeBackgroundBytesConsumed = diagnostics.nativeBackgroundBytesConsumed;
        nativeBackgroundPacketsConsumed = diagnostics.nativeBackgroundPacketsConsumed;
      } catch (_) {}
    }

    return _captureBackgroundResourceSnapshot(
      captureProvider: captureProvider,
      deviceProvider: deviceProvider,
      foregroundTaskRunning: foregroundTaskRunning,
      backgroundDisconnectCount: backgroundDisconnectCount,
      connectionTimeoutCount: connectionTimeoutCount,
      failToConnectCount: failToConnectCount,
      reconnectCount: reconnectCount,
      maxReconnectDurationMs: maxReconnectDurationMs,
      reconnectionCountTotal: reconnectionCountTotal,
      failToConnectCountTotal: failToConnectCountTotal,
      bleHistorySaturated: bleHistorySaturated,
      nativeBackgroundBytesConsumed: nativeBackgroundBytesConsumed,
      nativeBackgroundPacketsConsumed: nativeBackgroundPacketsConsumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    ListenClientState.instance.onLifecycle(state);
    String event = '';
    if (state == AppLifecycleState.paused) {
      event = 'App is paused';
      if (mounted) {
        _backgroundResourceTelemetry.onPaused(_captureBackgroundResourceSnapshot());
        Provider.of<CaptureProvider>(context, listen: false).setMetricsAppActive(false);
      }
    } else if (state == AppLifecycleState.resumed) {
      event = 'App is resumed';

      // Reload convos
      if (mounted) {
        Provider.of<ConversationProvider>(context, listen: false).refreshConversations();
        final captureProvider = Provider.of<CaptureProvider>(context, listen: false);
        captureProvider.setMetricsAppActive(true);
        unawaited(_backgroundResourceTelemetry.onResumed(_loadBackgroundResourceSnapshot));
        captureProvider.refreshInProgressConversations();
        // Heal phone-mic sessions that went silent while another app played
        // audio (Stage Manager / YouTube) without an AVAudioSession interrupt.
        captureProvider.onAppResumed();
        // Pick up any batch recordings the native layer wrote while backgrounded/closed.
        Provider.of<LocalRecordingsProvider>(context, listen: false).refresh();
      }
      // Sync Apple Reminders on foreground resume
      if (mounted && PlatformService.isApple) {
        final taskProvider = Provider.of<TaskIntegrationProvider>(context, listen: false);
        if (taskProvider.selectedApp == TaskIntegrationApp.appleReminders) {
          AppleRemindersSyncService().syncOnForegroundResume().then((_) {
            if (mounted) {
              Provider.of<ActionItemsProvider>(context, listen: false).forceRefreshActionItems();
            }
          });
        }
      }
    } else if (state == AppLifecycleState.hidden) {
      event = 'App is hidden';
    } else if (state == AppLifecycleState.detached) {
      event = 'App is detached';
    } else {
      return;
    }
    Logger.debug(event);
    PlatformManager.instance.crashReporter.logInfo(event);
  }

  bool? previousConnection;

  void _onReceiveTaskData(dynamic data) async {
    if (data is! Map<String, dynamic>) return;
    if (!(data.containsKey('latitude') && data.containsKey('longitude'))) return;
    await updateUserGeolocation(
      geolocation: Geolocation(
        latitude: data['latitude'],
        longitude: data['longitude'],
        accuracy: data['accuracy'],
        altitude: data['altitude'],
        time: DateTime.parse(data['time']).toUtc(),
      ),
    );
  }

  @override
  void initState() {
    unawaited(_backgroundResourceTelemetry.recoverInterrupted());
    SharedPreferencesUtil().onboardingCompleted = true;
    if (!SharedPreferencesUtil().permissionsCompleted) {
      SharedPreferencesUtil().permissionsCompleted = true;
    }
    updateUserOnboardingState(completed: true);

    // A link the shell was opened with: select its tab now (parent), open its page after start-up.
    final initialLink = HomeDeepLink.parse(widget.navigateToRoute);
    final homePageIdx = initialLink?.tabIndex ?? 0;

    // Home controller: Home stays the root; a link's section opens on top of it.
    final home = _homeProvider = context.read<HomeProvider>();
    home.selectedIndex = 0;
    home.onSelectedIndexChanged = _onSectionRequested;
    if (homePageIdx > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _onSectionRequested(homePageIdx));
    _teachOnArrival();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Android needs a foreground service to keep capture/location work alive.
      // On iOS this plugin boots a second Flutter engine; conversation location
      // is captured directly at recording start and first transcript instead.
      if (Platform.isAndroid) {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          await ForegroundUtil.initializeForegroundService();
          await ForegroundUtil.startForegroundTask();
        }
      } else if (Platform.isIOS) {
        // Stop a headless foreground-task engine persisted by an older build.
        // Native BLE/audio background modes continue to own active capture.
        await ForegroundUtil.stopForegroundTask();
      }
      if (mounted) {
        await Provider.of<HomeProvider>(context, listen: false).setUserPeople();
      }
      if (mounted) {
        await Provider.of<CaptureProvider>(
          context,
          listen: false,
        ).streamDeviceRecording(device: Provider.of<DeviceProvider>(context, listen: false).capabilityNormalizedDevice);
      }

      if (!mounted || initialLink == null) return;
      await openHomeDeepLink(context, initialLink, openSettings: _openSettings);
    });

    HomeNavigation.register(_openRoute);
    _listenToMessagesFromNotification();
    _listenToFreemiumThreshold();
    _checkForAnnouncements();
    _registerAutoSyncCallback();
    _initQuickActions();
    _startHomeWidgets();
    // Toasts float above the tab bar (and the chat bar on Home) while this shell is the visible route.
    OmiFeedback.bottomClearance = (ctx) => bottomNavBarClearance(ctx) - bottomNavBarReservedInset(ctx);
    super.initState();

    // After init
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  /// Opens a link inside this shell (notification taps, quick actions, app links): its tab first,
  /// then its page — never a second Home (nav #3, #18).
  Future<void> _openRoute(String route) async {
    final link = HomeDeepLink.parse(route);
    if (link == null || !mounted) return;
    final tab = link.tabIndex;
    if (tab != null && tab > 0) _onSectionRequested(tab);
    await openHomeDeepLink(context, link, openSettings: _openSettings);
  }

  /// Opens Settings, and once the reader is back on Home restarts capture if they changed the
  /// language, speech profile or transcription model (onboarding-home #25: compare after the sheet
  /// closes, not the moment it opens).
  Future<void> _openSettings() async {
    final prefs = SharedPreferencesUtil();
    final language = prefs.userPrimaryLanguage;
    final hasSpeech = prefs.hasSpeakerProfile;
    final transcriptModel = prefs.transcriptionModel;
    await SettingsDrawer.show(context);
    if (!mounted) return;
    if (language != prefs.userPrimaryLanguage ||
        hasSpeech != prefs.hasSpeakerProfile ||
        transcriptModel != prefs.transcriptionModel) {
      context.read<CaptureProvider>().onRecordProfileSettingChanged();
    }
  }

  /// Startup prompts (changelog, announcements, device tutorial, firmware notices) go through
  /// [PromptQueue]: one at a time, never while recording, on a call or during a firmware update.
  void _checkForAnnouncements() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _promptGate.attach(
        capture: Provider.of<CaptureProvider>(context, listen: false),
        device: Provider.of<DeviceProvider>(context, listen: false),
      );
      _announcementTimer?.cancel();
      _announcementTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;

        final announcementProvider = Provider.of<AnnouncementProvider>(context, listen: false);
        final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
        PromptQueue.instance.enqueue(
          'home-announcements',
          PromptPriority.normal,
          show: (_) async {
            if (!mounted) return;
            await AnnouncementService().checkAndShowAnnouncements(
              context,
              announcementProvider,
              connectedDevice: deviceProvider.connectedDevice,
            );
          },
        );

        // A device connecting checks its firmware announcements. (The device tutorial that used to
        // open here is retired: getting Omi to know you is the first To do now.)
        deviceProvider.onDeviceConnected = _onDeviceConnectedForAnnouncements;
      });
    });
  }

  void _registerAutoSyncCallback() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
      final syncProvider = Provider.of<SyncProvider>(context, listen: false);
      deviceProvider.onOfflineDataDetected = (device, fileCount, totalBytes) {
        // Custom STT users sync manually (with confirmation) — never auto-sync,
        // since offline files are transcribed on Omi and count toward the limit.
        if (SharedPreferencesUtil().useCustomStt) {
          Logger.debug('HomePage: Auto-sync skipped, custom STT provider enabled');
          return;
        }
        // Omi users can disable auto-sync from device settings. Defaults to on.
        if (!SharedPreferencesUtil().autoSyncOfflineRecordings) {
          Logger.debug('HomePage: Auto-sync skipped, disabled by user');
          return;
        }
        if (!syncProvider.isSyncing) {
          Logger.debug('HomePage: Auto-sync triggered ($fileCount files, $totalBytes bytes)');
          syncProvider.syncWals(trigger: WakeTrigger.deviceConnected);
        }
      };
    });
  }

  /// The iOS Home Screen widgets (Devices, Up next, Latest) follow what this Home shows.
  HomeWidgetsPublisher? _homeWidgets;

  void _startHomeWidgets() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _homeWidgets != null) return;
      _homeWidgets = HomeWidgetsPublisher(
        devices: context.read<DeviceProvider>(),
        tasks: context.read<ActionItemsProvider>(),
        conversations: context.read<ConversationProvider>(),
        l10n: () => context.l10n,
      )..start();
    });
  }

  void _initQuickActions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      QuickActionsService.instance.initialize(context);
      _deviceProviderForQuickActions = Provider.of<DeviceProvider>(context, listen: false);
      _deviceProviderForQuickActions!.addListener(_onDeviceStateChangedForQuickActions);
      _captureProviderForQuickActions = Provider.of<CaptureProvider>(context, listen: false);
      _captureProviderForQuickActions!.addListener(_onDeviceStateChangedForQuickActions);
    });
  }

  void _onDeviceStateChangedForQuickActions() {
    if (!mounted) return;
    QuickActionsService.instance.updateShortcuts(context);
  }

  void _onDeviceConnectedForAnnouncements(BtDevice device) {
    if (!mounted) return;

    final announcementProvider = Provider.of<AnnouncementProvider>(context, listen: false);
    PromptQueue.instance.enqueue(
      'firmware-announcements',
      PromptPriority.high,
      show: (_) async {
        if (!mounted) return;
        await AnnouncementService().showFirmwareUpdateAnnouncements(
          context,
          announcementProvider,
          device.firmwareRevision,
          device.modelNumber,
        );
      },
    );
  }

  void _listenToFreemiumThreshold() {
    // Listen to capture provider for freemium threshold events
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _captureProvider = Provider.of<CaptureProvider>(context, listen: false);
      _captureProvider!.addListener(_onCaptureProviderChanged);
      // Connect freemium session reset callback
      _captureProvider!.onFreemiumSessionReset = () {
        _freemiumHandler.resetDialogFlag();
      };
    });
  }

  void _onCaptureProviderChanged() {
    if (!mounted || _captureProvider == null) return;

    _freemiumHandler.checkAndShowPaywall(context, _captureProvider!);
  }

  void _listenToMessagesFromNotification() {
    _notificationStreamSubscription = NotificationService.instance.listenForServerMessages.listen((message) {
      if (mounted) {
        var selectedApp = Provider.of<AppProvider>(context, listen: false).getSelectedApp();
        if (selectedApp == null || message.appId == selectedApp.id) {
          Provider.of<MessageProvider>(context, listen: false).addMessage(message);
        }
        // chatPageKey.currentState?.scrollToBottom();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MyUpgradeAlert(
      upgrader: _upgrader,
      dialogStyle: Platform.isIOS ? UpgradeDialogStyle.cupertino : UpgradeDialogStyle.material,
      child: Consumer<ConnectivityProvider>(
        builder: (ctx, connectivityProvider, child) {
          bool isConnected = connectivityProvider.isConnected;
          previousConnection ??= true;

          if (previousConnection != isConnected &&
              connectivityProvider.isInitialized &&
              connectivityProvider.previousConnection != isConnected) {
            previousConnection = isConnected;
            if (isConnected) {
              Future.delayed(Duration.zero, () {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!mounted) return;

                  final convoProvider = ctx.read<ConversationProvider>();
                  final messageProvider = ctx.read<MessageProvider>();

                  if (convoProvider.conversations.isEmpty) {
                    await convoProvider.getInitialConversations();
                  } else {
                    // Force refresh when internet connection is restored
                    await convoProvider.forceRefreshConversations();
                  }

                  if (messageProvider.messages.isEmpty) {
                    await messageProvider.refreshMessages();
                  }
                });
              });
            }
          }
          return child!;
        },
        // v3: Home is the one root screen, on the warm gradient fixed to the screen: the top bar,
        // the content, the pinned Ask bar and the recorder card over them.
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: HomeTone.gradient()),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                // The top bar and the page move together under a pull; the Ask bar stays.
                Positioned.fill(
                  child: HomePullGestures(
                    down: _pullDown,
                    up: _pullUp,
                    onPullDown: () => HomeRecorderActions.act(context),
                    onPullUp: _openOmi,
                    child: Column(
                      children: [
                        HomeTopBar(
                          onOpenOmi: _openOmi,
                          pull: _pullDown,
                          pulse: _teachPulse,
                          onPullAction: () => HomeRecorderActions.act(context),
                          onFolders: _openFolders,
                          onYou: () {
                            PlatformManager.instance.analytics.pageOpened('You');
                            unawaited(YouSheet.show(context, openSettings: _openSettings));
                          },
                        ),
                        Expanded(child: HomeContentPage(key: _homeContentPageKey)),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Center(child: HomePullUpHint(progress: _pullUp)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: HomeAskBar(onOpen: _openChat, onHold: _openMemories),
                ),
                // `.tip`: under the label, 82 pt from the top of the screen.
                ValueListenableBuilder<bool>(
                  valueListenable: _teachTip,
                  builder: (context, show, _) => show
                      ? Positioned(
                          top: MediaQuery.viewPaddingOf(context).top + 82,
                          left: 0,
                          right: 0,
                          child: Center(child: HomeTeachTip(onDone: _teachDone)),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// v3: Ask rises over Home from the Ask bar (the design's `#chat`) and starts fresh.
  void _openChat({bool voice = false}) {
    OmiHaptics.selection();
    PlatformManager.instance.analytics.bottomNavigationTabClicked(voice ? 'Chat Voice' : 'Chat');
    openAsk(context, ChatPage(isPivotBottom: false, autoStartVoice: voice));
  }

  /// Holding the dock's Omi mark: Memories (a hidden shortcut; screen readers get it as an action).
  void _openMemories() {
    PlatformManager.instance.analytics.pageOpened('Memories');
    routeToPage(context, const MemoriesPage());
  }

  @override
  void dispose() {
    _homeWidgets?.dispose();
    // Only this Home's own hook: a later Home may already have set its own.
    if (_homeProvider?.onSelectedIndexChanged == _onSectionRequested) _homeProvider?.onSelectedIndexChanged = null;
    _homeProvider = null;
    _pullDown.dispose();
    _pullUp.dispose();
    _teachTip.dispose();
    _teachPulse.dispose();
    HomeNavigation.unregister(_openRoute);
    _promptGate.detach();
    // These prompts close over this Home; a later Home (after sign-out and sign-in) enqueues its own.
    for (final id in const ['home-announcements', 'device-tutorial', 'firmware-announcements']) {
      PromptQueue.instance.remove(id);
    }
    OmiFeedback.bottomClearance = null;
    _announcementTimer?.cancel();
    _announcementTimer = null;
    _teachTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Cancel stream subscription to prevent memory leak
    _notificationStreamSubscription?.cancel();
    // Remove capture provider listener using stored reference
    if (_captureProvider != null) {
      _captureProvider!.removeListener(_onCaptureProviderChanged);
      _captureProvider!.onFreemiumSessionReset = null;
      _captureProvider = null;
    }
    // Remove device provider callback
    try {
      final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
      deviceProvider.onDeviceConnected = null;
      deviceProvider.onOfflineDataDetected = null;
    } catch (_) {}
    _deviceProviderForQuickActions?.removeListener(_onDeviceStateChangedForQuickActions);
    _deviceProviderForQuickActions = null;
    _captureProviderForQuickActions?.removeListener(_onDeviceStateChangedForQuickActions);
    _captureProviderForQuickActions = null;
    QuickActionsService.instance.reset();
    _homeWidgets?.dispose();
    // Clean up freemium handler
    _freemiumHandler.dispose();
    // Remove foreground task callback to prevent memory leak
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    if (Platform.isAndroid) {
      ForegroundUtil.stopForegroundTask();
    }
    super.dispose();
  }
}
