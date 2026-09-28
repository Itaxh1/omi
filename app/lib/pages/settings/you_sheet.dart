import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/pages/devices/devices_screen.dart';
import 'package:omi/pages/memories/page.dart';
import 'package:omi/pages/settings/settings_destinations.dart';
import 'package:omi/pages/settings/settings_search_index.dart' show SettingsDestination;
import 'package:omi/providers/app_provider.dart';
import 'package:omi/providers/memories_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/pages/apps/apps_v3.dart';

/// You (v3 `me`): a sheet from Home's initial button. The reader's name and Done; Look (White or
/// Black); Listening (Start when Omi opens, the pendant button); You (Teach Omi your voice,
/// Memories with their count, Apps); and All settings, where everything else lives.
abstract final class YouSheet {
  /// [openSettings] shows the full Settings sheet (Home's, which restarts capture when a listening
  /// setting changed there).
  static Future<void> show(BuildContext context, {required Future<void> Function() openSettings}) {
    final name = SharedPreferencesUtil().givenName.trim();
    return showOmiSheet<void>(
      context: context,
      title: name.isEmpty ? context.l10n.you : name,
      builder: (sheetContext) => _YouBody(hostContext: context, openSettings: openSettings),
    );
  }
}

class _YouBody extends StatefulWidget {
  const _YouBody({required this.hostContext, required this.openSettings});

  final BuildContext hostContext;
  final Future<void> Function() openSettings;

  @override
  State<_YouBody> createState() => _YouBodyState();
}

class _YouBodyState extends State<_YouBody> {
  /// Closes the sheet, then opens [page] from Home.
  void _open(Widget page) {
    Navigator.of(context).pop();
    if (widget.hostContext.mounted) routeToPage(widget.hostContext, page);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prefs = SharedPreferencesUtil();
    final memories = context.select<MemoriesProvider, int>((p) => p.memories.length);
    final apps = context.select<AppProvider, String>(
      (p) => p.apps.where((a) => a.enabled).map((a) => a.name).take(2).join(', '),
    );
    final light = OmiColors.isLight;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
      child: ListView(
        key: const Key('you_sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: 4, bottom: 20),
        children: [
          OmiSectionLabel(title: l10n.look, top: 6),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _LookButton(
                  key: const Key('look_white'),
                  label: l10n.lookWhite,
                  selected: light,
                  onTap: () => setState(() => OmiAppearance.mode.value = OmiAppearanceMode.light),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LookButton(
                  key: const Key('look_black'),
                  label: l10n.lookBlack,
                  selected: !light,
                  onTap: () => setState(() => OmiAppearance.mode.value = OmiAppearanceMode.dark),
                ),
              ),
            ],
          ),
          OmiSectionLabel(title: l10n.listening, top: 30),
          _Row(
            key: const Key('you_auto_start'),
            title: l10n.startWhenOmiOpens,
            value: prefs.autoRecordingEnabled ? l10n.on : l10n.off,
            onTap: () => setState(() => prefs.autoRecordingEnabled = !prefs.autoRecordingEnabled),
          ),
          _Row(
            key: const Key('you_pendant_button'),
            title: l10n.pendantButton,
            value: DevicesScreen.doubleTapLabel(context, prefs.doubleTapAction),
            onTap: () => _open(const DevicesScreen()),
          ),
          OmiSectionLabel(title: l10n.you, top: 30),
          _Row(
            key: const Key('you_voice'),
            title: l10n.teachOmiYourVoice,
            onTap: () {
              Navigator.of(context).pop();
              if (widget.hostContext.mounted) {
                openSettingsDestination(widget.hostContext, SettingsDestination.voiceProfile);
              }
            },
          ),
          _Row(
            key: const Key('you_memories'),
            title: l10n.memories,
            value: memories > 0 ? '$memories' : null,
            onTap: () => _open(const MemoriesPage()),
          ),
          _Row(
            key: const Key('you_apps'),
            title: l10n.connectorsV3,
            value: apps.isEmpty ? null : apps,
            onTap: () => _open(const AddAnAppPage()),
          ),
          _Row(
            key: const Key('you_all_settings'),
            title: l10n.allSettings,
            value: '›',
            last: true,
            onTap: () {
              Navigator.of(context).pop();
              widget.openSettings();
            },
          ),
        ],
      ),
    );
  }
}

/// White / Black (`.modes`): 40 pt pills, the chosen one filled with ink.
class _LookButton extends StatelessWidget {
  const _LookButton({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: OmiPressable(
        onTap: () {
          if (selected) return;
          OmiHaptics.selection();
          onTap();
        },
        child: Container(
          height: 40,
          alignment: Alignment.center,
          // v8.10 `.modes button`: paper with a 10 % outline; chosen, the warm tone and 30 %.
          decoration: BoxDecoration(
            color: selected ? OmiColors.tone : OmiColors.surface0,
            borderRadius: OmiRadius.pillAll,
            border: Border.all(color: OmiColors.textPrimary.withValues(alpha: selected ? 0.30 : 0.10)),
          ),
          child: Text(
            label,
            style: OmiType.callout.copyWith(fontWeight: FontWeight.w600, color: OmiColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// A row (`.row`): the name at 17/500, a value on the right at 13 pt, a hairline under it.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.title, required this.onTap, this.value, this.last = false});

  final String title;
  final String? value;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: value == null || value == '›' ? title : '$title, $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          OmiHaptics.selection();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: OmiColors.divider))),
          child: Row(
            children: [
              Expanded(child: Text(title, style: OmiType.body.copyWith(fontWeight: FontWeight.w500, height: 1.3))),
              if (value != null) ...[
                const SizedBox(width: 14),
                // The value sits on the right edge and gives way first (up to 40 % of the row).
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: value == '›'
                        ? OmiType.title3.copyWith(color: OmiColors.faint, height: 1)
                        : OmiType.footnote.copyWith(height: 1.4, color: OmiColors.textSecondary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
