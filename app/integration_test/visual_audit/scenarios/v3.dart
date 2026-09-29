// The v3 surfaces that have no older counterpart: the folders sidebar, You, Devices and what the
// pendant's light means.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/backend/schema/folder.dart';
import 'package:omi/pages/devices/devices_screen.dart';
import 'package:omi/pages/devices/light_legend_page.dart';
import 'package:omi/pages/home/widgets/folders_sidebar.dart';
import 'package:omi/pages/settings/you_sheet.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/folder_provider.dart';
import 'package:omi/providers/onboarding_provider.dart';

import '../fakes.dart';
import '../harness.dart';
import 'capture.dart' show auditPendant;

Folder _folder(String id, String name, int count, int order) => Folder(
      id: id,
      name: name,
      color: '#000000',
      icon: 'folder',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      order: order,
      isDefault: false,
      isSystem: false,
      conversationCount: count,
    );

final v3Scenarios = <AuditScenario>[
  AuditScenario(
    id: 'v3-folders-sidebar',
    title: 'Folders: All conversations, each folder with its count, Not in a folder, Apps',
    page: 'lib/pages/home/widgets/folders_sidebar.dart (FoldersSidebar)',
    state: 'Three folders (Work 12, Family 4, Ideas 2) and twenty conversations',
    run: (a) async {
      final folders = FolderProvider(
          foldersFetcher: () async =>
              [_folder('w', 'Work', 12, 0), _folder('f', 'Family', 4, 1), _folder('i', 'Ideas', 2, 2)]);
      await a.tester.runAsync(folders.loadFolders);
      final conversations = ConversationProvider(isSignedIn: () => true)
        ..conversations = [for (var i = 0; i < 20; i++) auditConversation('c$i', title: 'Conversation $i')];
      await a.pumpHost(FoldersSidebar.show, providers: [
        ChangeNotifierProvider<FolderProvider>.value(value: folders),
        ChangeNotifierProvider<ConversationProvider>.value(value: conversations),
      ]);
      await a.shot('Open the folders sidebar from Home');
    },
  ),
  AuditScenario(
    id: 'v3-you-sheet',
    title: 'You: Look, Listening, You and All settings',
    page: 'lib/pages/settings/you_sheet.dart (YouSheet)',
    state: 'A named account; Start when Omi opens on; no memories',
    prefs: {'givenName': 'Ashwin'},
    run: (a) async {
      await a.pumpHost((context) => YouSheet.show(context, openSettings: () async {}));
      await a.shot("Tap the initial on Home: the You sheet");
    },
  ),
  AuditScenario(
    id: 'v3-devices',
    title: 'Devices: the pendant, its light, Pause, Record from, the button, firmware, Add a device',
    page: 'lib/pages/devices/devices_screen.dart (DevicesScreen)',
    state: 'An Omi pendant connected at 72% battery',
    run: (a) async {
      await a.pump(const DevicesScreen(), scaffold: false, providers: [
        ChangeNotifierProvider<DeviceProvider>.value(
            value: AuditDeviceProvider(connected: true, battery: 72, device: auditPendant)),
      ]);
      await a.scrollSeries('Open Devices with the pendant connected');
    },
  ),
  AuditScenario(
    id: 'v3-devices-none',
    title: 'Devices with nothing paired: this phone records',
    page: 'lib/pages/devices/devices_screen.dart (DevicesScreen)',
    state: 'No device paired',
    run: (a) async {
      await a.pump(const DevicesScreen(), scaffold: false);
      await a.shot('Open Devices with no pendant');
    },
  ),
  AuditScenario(
    id: 'v3-pair-sheet',
    title: 'Add a device: looking, found, pairing, connected',
    page: 'lib/pages/devices/pair_device_sheet.dart (PairDeviceSheet)',
    state: 'Devices with nothing paired; Add a device tapped; a pendant turns up, is paired, and connects',
    run: (a) async {
      final onboarding = _PairingOnboarding();
      await a.pump(const DevicesScreen(), scaffold: false, providers: [
        ChangeNotifierProvider<OnboardingProvider>.value(value: onboarding),
      ]);
      await a.tap(find.byKey(const Key('devices_add')));
      await a.shot('Add a device: looking for the pendant', step: 'looking');
      onboarding.found();
      await a.settle();
      await a.shot('A pendant found nearby with Pair', step: 'found');
      await a.tap(find.byKey(const Key('onboarding_pair')));
      await a.shot('Pairing: hold on', step: 'pairing');
      onboarding.finishPairing();
      await a.settle();
      await a.shot('Paired: your pendant is connected', step: 'paired');
    },
  ),
  AuditScenario(
    id: 'v3-light-legend',
    title: 'What the light means',
    page: 'lib/pages/devices/light_legend_page.dart (showLightLegend)',
    state: 'Opened from Devices',
    run: (a) async {
      await a.pumpHost(showLightLegend);
      await a.shot('What the light means: six states');
    },
  ),
];

/// A scan that turns up one pendant when the scenario says so; pairing finishes the same way.
class _PairingOnboarding extends OnboardingProvider {
  VoidCallback? _paired;

  @override
  Future<void> scanDevices({required VoidCallback onShowDialog, VoidCallback? onShowLocationDialog}) async {}

  @override
  void cancelActiveScan() {}

  @override
  Future<void> handleTap({required BtDevice device, required bool isFromOnboarding, VoidCallback? goNext}) async {
    _paired = goNext;
    connectingToDeviceId = device.id;
    notifyListeners();
  }

  void found() {
    deviceList = [BtDevice(id: '6C:2A:9E:11:A3:F2', name: 'Omi', type: DeviceType.omi, rssi: -48)];
    notifyListeners();
  }

  void finishPairing() {
    connectingToDeviceId = null;
    deviceName = 'Omi';
    batteryPercentage = 72;
    isConnected = true;
    notifyListeners();
    _paired?.call();
  }
}
