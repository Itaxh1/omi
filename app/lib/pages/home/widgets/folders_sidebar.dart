import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/pages/conversations/all_conversations_page.dart';
import 'package:omi/pages/conversations/widgets/create_folder_sheet.dart';
import 'package:omi/providers/app_provider.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/folder_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/pages/apps/apps_v3.dart';

/// The folders sidebar (v3 `.side`): it slides in from the left at 82 % of the width (320 at most)
/// from Home's folder button. "Conversations" over All conversations, each folder with its count,
/// Not in a folder and "+ New folder"; Apps and Browse all apps at the bottom. No logo.
abstract final class FoldersSidebar {
  static Future<void> show(BuildContext context) {
    OmiHaptics.selection();
    final folders = context.read<FolderProvider>();
    if (folders.folders.isEmpty && !folders.isLoading) folders.loadFolders();
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: OmiColors.scrim,
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (dialogContext, _, __) => Align(
        alignment: Alignment.centerLeft,
        child: _Sidebar(hostContext: context),
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(-1.02, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: const Cubic(0.32, 0.72, 0, 1))),
        child: child,
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.hostContext});

  /// Home's context: pages open from there once the sidebar has closed.
  final BuildContext hostContext;

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).pop();
    routeToPage(hostContext, page);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = (MediaQuery.sizeOf(context).width * 0.82).clamp(0.0, 320.0);
    final folders =
        context.watch<FolderProvider>().folders.where((f) => !f.isSystem || f.conversationCount > 0).toList();
    // Counts for All and Not in a folder only once every conversation is loaded, so they are exact.
    final (all, unfiled) = context.select<ConversationProvider, (int?, int?)>((p) {
      if (p.hasMoreConversations) return (null, null);
      final kept = p.conversations.where((c) => !c.discarded);
      return (kept.length, kept.where((c) => (c.folderId ?? '').isEmpty).length);
    });
    final installed = context.select<AppProvider, String>(
      (p) => p.apps.where((a) => a.enabled).map((a) => a.name).take(3).join(', '),
    );
    return Material(
      color: OmiColors.surface0,
      child: Container(
        key: const Key('folders_sidebar'),
        width: width,
        height: double.infinity,
        decoration: BoxDecoration(border: Border(right: BorderSide(color: OmiColors.outline))),
        padding: EdgeInsets.fromLTRB(
            20, MediaQuery.paddingOf(context).top + 14, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: OmiRingButton(
                key: const Key('folders_sidebar_close'),
                glyph: OmiGlyphs.close,
                glyphSize: 16,
                size: 38,
                label: MaterialLocalizations.of(context).closeButtonLabel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 19),
            OmiSectionLabel(title: l10n.conversations, bottom: 4),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _FolderRow(
                    key: const Key('folder_all'),
                    label: l10n.allConversations,
                    count: all,
                    strong: true,
                    onTap: () => _open(context, const AllConversationsPage()),
                  ),
                  for (final f in folders)
                    _FolderRow(
                      key: ValueKey('folder_${f.id}'),
                      label: f.name,
                      count: f.conversationCount,
                      onTap: () => _open(context, AllConversationsPage(scope: FolderScope(f.id, f.name))),
                    ),
                  _FolderRow(
                    key: const Key('folder_unfiled'),
                    label: l10n.notInAFolder,
                    count: unfiled,
                    onTap: () => _open(context, const AllConversationsPage(scope: UnfiledScope())),
                  ),
                  const SizedBox(height: 4),
                  Semantics(
                    button: true,
                    label: l10n.newFolderV3,
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: const Key('folder_new'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showCreateFolderBottomSheet(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        child: Row(
                          children: [
                            OmiGlyph(OmiGlyphs.plusLine, size: 16, color: OmiColors.textPrimary),
                            const SizedBox(width: 11),
                            Text(l10n.newFolderV3,
                                style: OmiType.callout.copyWith(fontWeight: FontWeight.w600, height: 1.4)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: OmiColors.outline))),
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  children: [
                    _FolderRow(
                      key: const Key('sidebar_apps'),
                      glyph: OmiGlyphs.apps,
                      label: l10n.apps,
                      detail: installed.isEmpty ? null : installed,
                      onTap: () => _open(context, const AddAnAppPage()),
                    ),
                    _FolderRow(
                      key: const Key('sidebar_browse_apps'),
                      glyph: OmiGlyphs.browse,
                      label: l10n.browseAllApps,
                      detail: '›',
                      last: true,
                      onTap: () => _open(context, const AllAppsPage()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A sidebar row (`.frow`): a 15 pt glyph, the name at 17, a count or detail on the right, a
/// hairline under it.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    super.key,
    required this.label,
    required this.onTap,
    this.glyph = OmiGlyphs.folderLine,
    this.count,
    this.detail,
    this.strong = false,
    this.last = false,
  });

  final String label;
  final VoidCallback onTap;
  final String glyph;
  final int? count;
  final String? detail;
  final bool strong;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final trailing = detail ?? (count == null ? null : '$count');
    return Semantics(
      button: true,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          OmiHaptics.selection();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: OmiColors.divider))),
          child: Row(
            children: [
              OmiGlyph(glyph, size: 15, color: strong ? OmiColors.textPrimary : OmiColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OmiType.body.copyWith(height: 1.4, fontWeight: strong ? FontWeight.w600 : FontWeight.w400),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                Text(
                  trailing,
                  style: OmiType.subhead.copyWith(
                    fontSize: 14, // omi-ux-allow: font-size-literal -- the design's 14 pt count
                    height: 1.4,
                    color: OmiColors.textSecondary,
                    fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
