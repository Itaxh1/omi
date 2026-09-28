import 'dart:async';

import 'package:flutter/material.dart';


import 'package:collection/collection.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/schema/app.dart';
import 'package:omi/pages/apps/add_app.dart';
import 'package:omi/pages/apps/add_mcp_server_page.dart';
import 'package:omi/pages/apps/app_detail/app_detail.dart';
import 'package:omi/pages/apps/providers/add_app_provider.dart';
import 'package:omi/pages/apps/widgets/app_actions.dart';
import 'package:omi/pages/home/widgets/listening_strip.dart';
import 'package:omi/providers/app_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/app_localizations_helper.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/utils/platform/platform_manager.dart';
import 'package:omi/widgets/extensions/string.dart';

/// Loads the catalogue once when a v3 apps page opens with nothing loaded yet.
void _ensureAppsLoaded(BuildContext context) {
  final provider = context.read<AppProvider>();
  if (provider.apps.isEmpty) unawaited(provider.getApps());
}

/// The apps a v3 list shows, once each, the reader's first, then the most installed.
List<App> _ranked(Iterable<App> apps) {
  final seen = <String>{};
  final unique = [
    for (final a in apps)
      if (seen.add(a.id)) a
  ];
  return unique..sort((a, b) => a.enabled == b.enabled ? b.installs.compareTo(a.installs) : (a.enabled ? -1 : 1));
}

/// Add an app (v3 `appsAll`): "Browse all apps" on top, then the apps that take Omi's summaries and
/// to-dos elsewhere, and the apps you ask Omi with. Each row is a letter tile, the name, one line
/// on what it does, and Add / Added.
class AddAnAppPage extends StatefulWidget {
  const AddAnAppPage({super.key});

  /// How many apps each group shows (the reader's own always show).
  static const int perGroup = 5;

  @override
  State<AddAnAppPage> createState() => _AddAnAppPageState();
}

class _AddAnAppPageState extends State<AddAnAppPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureAppsLoaded(context);
    });
  }

  Future<void> _create(BuildContext context) async {
    final l10n = context.l10n;
    final choice = await showOmiPopoverMenu<String>(context, entries: [
      OmiMenuEntry(value: 'app', label: l10n.createAnApp, glyph: OmiGlyphs.apps),
      OmiMenuEntry(value: 'mcp', label: l10n.addMcpServer, glyph: OmiGlyphs.plusLine),
    ]);
    if (!context.mounted || choice == null) return;
    PlatformManager.instance.analytics.pageOpened(choice == 'app' ? 'Submit App' : 'Add MCP Server');
    await routeToPage(context, choice == 'app' ? const AddAppPage() : const AddMcpServerPage());
  }

  List<App> _group(List<App> apps, bool Function(App) test) {
    final all = _ranked(apps.where(test));
    final mine = all.where((a) => a.enabled).toList();
    final rest =
        all.where((a) => !a.enabled).take((AddAnAppPage.perGroup - mine.length).clamp(0, AddAnAppPage.perGroup));
    return [...mine, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.watch<AppProvider>();
    final sendTo = _group(provider.apps, (a) => a.worksExternally());
    final askWith = _group(provider.apps, (a) => a.worksWithChat() && !a.worksExternally());
    return Scaffold(
      backgroundColor: OmiColors.surface0,
      appBar: OmiScreenHeader(
        title: l10n.yourConnectors,
        // Beyond the design: making an app or adding an MCP server lived only on the old Apps page.
        trailing: OmiRingButton.glass(
          key: const Key('apps_create'),
          glyph: OmiGlyphs.plusLine,
          label: l10n.createAnApp,
          onPressed: () => _create(context),
        ),
      ),
      bottomNavigationBar: const ListeningStrip(),
      body: ListView(
        // `.sb`: 4 pt under the header.
        padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 4, OmiSize.screenMargin, 24),
        children: [
          _BrowseCard(onTap: () => routeToPage(context, const AllAppsPage())),
          if (provider.apps.isEmpty && provider.isLoading)
            const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: OmiSpinner()))
          else ...[
            if (sendTo.isNotEmpty) ...[
              OmiSectionLabel(title: l10n.appsSendTo, top: 6, bottom: 4),
              for (final app in sendTo) AppRowV3(key: ValueKey('app_${app.id}'), app: app),
            ],
            if (askWith.isNotEmpty) ...[
              OmiSectionLabel(title: l10n.appsAskWith, top: 30, bottom: 4),
              for (final app in askWith) AppRowV3(key: ValueKey('app_${app.id}'), app: app),
            ],
          ],
        ],
      ),
    );
  }
}

/// "Browse all apps" (`.browse`): an outlined 18 pt card with a line under the name and an arrow.
class _BrowseCard extends StatelessWidget {
  const _BrowseCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.browseAllApps,
      excludeSemantics: true,
      child: OmiPressable(
        key: const Key('apps_browse_all'),
        onTap: () {
          OmiHaptics.selection();
          onTap();
        },
        child: Container(
          margin: const EdgeInsets.only(top: 6, bottom: 8),
          padding: const EdgeInsets.all(16),
          // v8.12 `.browse`: the warm tone with a 10 % outline.
          decoration: BoxDecoration(
            color: OmiColors.tone,
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            border: Border.all(color: OmiColors.textPrimary.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.browseAllApps, style: OmiType.body.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
                    const SizedBox(height: 2),
                    Text(l10n.browseAllAppsDetail,
                        style: OmiType.detail.copyWith(height: 1.4, color: OmiColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Text('→', style: OmiType.lead.copyWith(fontWeight: FontWeight.w400, height: 1)),
            ],
          ),
        ),
      ),
    );
  }
}

/// All apps (v3 `store`): search, category pills, how many apps show, then every app as a row.
class AllAppsPage extends StatefulWidget {
  const AllAppsPage({super.key});

  @override
  State<AllAppsPage> createState() => _AllAppsPageState();
}

class _AllAppsPageState extends State<AllAppsPage> {
  final TextEditingController _query = TextEditingController();
  String? _category;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureAppsLoaded(context);
      final categories = context.read<AddAppProvider>();
      if (categories.categories.isEmpty) {
        // The provider does not notify when its categories land.
        unawaited(categories.getCategories().then((_) {
          if (mounted) setState(() {});
        }).catchError((_) {}));
      }
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.watch<AppProvider>();
    final categories = context.read<AddAppProvider>().categories;
    final all = _ranked(provider.apps);
    final used = all.map((a) => a.category).toSet();
    final chips = categories.where((c) => used.contains(c.id)).toList();
    final q = _query.text.trim().toLowerCase();
    final shown = all.where((a) {
      if (_category != null && a.category != _category) return false;
      if (q.isEmpty) return true;
      return '${a.name} ${a.description}'.decodeString.toLowerCase().contains(q);
    }).toList();
    final chosen = chips.firstWhereOrNull((c) => c.id == _category);
    final count = shown.isEmpty && q.isNotEmpty
        ? l10n.noAppsMatch(_query.text.trim())
        : chosen == null
            ? l10n.appsCountV3(shown.length)
            : l10n.appsInCategory(shown.length, chosen.getLocalizedTitle(context));
    return Scaffold(
      backgroundColor: OmiColors.surface0,
      appBar: OmiScreenHeader(title: l10n.connectorsV3),
      bottomNavigationBar: const ListeningStrip(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OmiSize.screenMargin),
            child: OmiSearchPill(
              key: const Key('apps_search'),
              controller: _query,
              hint: l10n.searchApps,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            key: const Key('apps_categories'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: OmiSize.screenMargin, vertical: 8),
            child: Row(
              children: [
                _CategoryPill(
                  key: const Key('apps_category_all'),
                  label: l10n.all,
                  selected: _category == null,
                  onTap: () => setState(() => _category = null),
                ),
                for (final c in chips) ...[
                  const SizedBox(width: 6),
                  _CategoryPill(
                    key: ValueKey('apps_category_${c.id}'),
                    label: c.getLocalizedTitle(context),
                    selected: _category == c.id,
                    onTap: () => setState(() => _category = c.id),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 4, OmiSize.screenMargin, 2),
            child: Text(count,
                key: const Key('apps_count'),
                style: OmiType.footnote.copyWith(height: 1.4, color: OmiColors.textSecondary)),
          ),
          if (provider.apps.isEmpty && provider.isLoading)
            const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: OmiSpinner()))
          else
            for (final app in shown)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: OmiSize.screenMargin),
                child: AppRowV3(key: ValueKey('store_${app.id}'), app: app),
              ),
        ],
      ),
    );
  }
}

/// A category (`.stchips button`): a 34 pt pill, ink when chosen.
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({super.key, required this.label, required this.selected, required this.onTap});

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
        // 34 pt to the eye inside a 44 pt target.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            alignment: Alignment.center,
            // v8.12 `#stC button`: paper with a 12 % outline; chosen, the warm tone and 35 %.
            decoration: BoxDecoration(
              color: selected ? OmiColors.tone : OmiColors.surface0,
              borderRadius: OmiRadius.pillAll,
              border: Border.all(color: OmiColors.textPrimary.withValues(alpha: selected ? 0.35 : 0.12)),
            ),
            child: Text(
              label,
              style: OmiType.detail.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: OmiColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One connector (`.arow`, v8.12): the app's logo in a 44 pt tile, the name at 16.5/500 over
/// one line on what it does, and Add / Added on the right. The row opens the app's page.
class AppRowV3 extends StatelessWidget {
  const AppRowV3({super.key, required this.app});

  final App app;

  @override
  Widget build(BuildContext context) {
    final name = app.name.decodeString.trim();
    final letter = name.isEmpty ? '·' : name.characters.first.toUpperCase();
    return InkWell(
      onTap: () {
        OmiHaptics.selection();
        routeToPage(context, AppDetailPage(app: app));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OmiColors.divider))),
        child: Row(
          children: [
            // v8.12 `.lg`: the app's own logo in a 44 pt tile with a 10 % outline (its first letter
            // until the logo loads, or if it can't).
            ExcludeSemantics(
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: OmiColors.surface0,
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  border: Border.all(color: OmiColors.textPrimary.withValues(alpha: 0.10)),
                ),
                child: Image.network(
                  app.getImageUrl(),
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  cacheWidth: (44 * MediaQuery.devicePixelRatioOf(context)).round(),
                  frameBuilder: (context, child, frame, sync) =>
                      frame == null && !sync ? _LetterTile(letter: letter) : child,
                  errorBuilder: (context, _, __) => _LetterTile(letter: letter),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OmiType.askBar.copyWith(height: 1.3)),
                  const SizedBox(height: 1),
                  Text(
                    app.description.decodeString.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OmiType.footnote.copyWith(height: 1.4, color: OmiColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            AppAddButton(app: app),
          ],
        ),
      ),
    );
  }
}

/// Add / Added (`.ad`): a 34 pt pill, outlined to add, ink once added. Add enables the app in place
/// (asking about data first when it works outside Omi), or opens its page when it needs setup or
/// payment; Added turns it off with Undo.
class AppAddButton extends StatefulWidget {
  const AppAddButton({super.key, required this.app});

  final App app;

  @override
  State<AppAddButton> createState() => _AppAddButtonState();
}

class _AppAddButtonState extends State<AppAddButton> {
  bool _busy = false;
  bool? _shownOff;

  Future<void> _add() async {
    final app = widget.app;
    if (appNeedsDetailToEnable(app)) {
      await routeToPage(context, AppDetailPage(app: app));
      return;
    }
    if (!await confirmAppDataAccess(context, app) || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<AppProvider>().toggleApp(app.id, true, null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    await disableAppWithUndo(
      context,
      widget.app,
      onHidden: () => mounted ? setState(() => _shownOff = true) : null,
      onRestored: () => mounted ? setState(() => _shownOff = null) : null,
    );
    if (mounted) setState(() => _shownOff = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final app = widget.app;
    final enabled = context.select<AppProvider, bool>(
          (p) => (p.apps.firstWhereOrNull((a) => a.id == app.id) ?? app).enabled,
        ) &&
        _shownOff != true;
    final label = enabled ? l10n.appAdded : l10n.add;
    return Semantics(
      button: true,
      toggled: enabled,
      label: '$label ${app.name.decodeString}',
      excludeSemantics: true,
      child: OmiPressable(
        key: ValueKey('app_add_${app.id}'),
        onTap: _busy
            ? null
            : () {
                OmiHaptics.selection();
                enabled ? _remove() : _add();
              },
        // 34 pt to the eye inside a 44 pt target.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: AnimatedContainer(
            duration: OmiMotion.of(context).quick,
            constraints: const BoxConstraints(minHeight: 34, minWidth: 57),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            alignment: Alignment.center,
            // v8.12 `.ad`: paper with a 14 % outline; added, the warm tone and "✓ Added".
            decoration: BoxDecoration(
              color: enabled ? OmiColors.tone : OmiColors.surface0,
              borderRadius: OmiRadius.pillAll,
              border: Border.all(color: OmiColors.textPrimary.withValues(alpha: enabled ? 0.10 : 0.14)),
            ),
            child: _busy
                ? const OmiSpinner(size: OmiSpinnerSize.small)
                : Text(
                    enabled ? '✓ $label' : label,
                    style: OmiType.detail.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: OmiColors.textPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The app's first letter in the tile, while its logo loads or when it has none.
class _LetterTile extends StatelessWidget {
  const _LetterTile({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(letter, style: OmiType.subhead.copyWith(fontWeight: FontWeight.w700, height: 1)));
  }
}
