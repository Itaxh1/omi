import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/http/api/knowledge_graph_api.dart';
import 'package:omi/backend/preferences.dart';
import 'package:omi/pages/home/widgets/listening_strip.dart';
import 'package:omi/pages/memories/memory_bulk_actions.dart';
import 'package:omi/pages/memories/widgets/memory_dialog.dart';
import 'package:omi/pages/memories/widgets/memory_row.dart';
import 'package:omi/providers/memories_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/platform/platform_manager.dart';
import 'package:omi/widgets/extensions/string.dart';

/// Memories (v3 `memsc`): the people and topics Omi knows, drawn as a small graph around "You";
/// how many memories there are; then each memory with where it came from. Tapping a name in the
/// graph shows only the memories that mention it; tapping a memory edits it; + adds one.
class MemoriesPage extends StatefulWidget {
  const MemoriesPage({super.key, this.loadGraph});

  /// The knowledge graph; the API by default.
  final Future<Map<String, dynamic>> Function()? loadGraph;

  @override
  State<MemoriesPage> createState() => MemoriesPageState();
}

class MemoriesPageState extends State<MemoriesPage> {
  final ScrollController _scroll = ScrollController();
  String? _focus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<MemoriesProvider>();
      if (provider.memories.isEmpty) unawaited(provider.init());
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: OmiMotion.emphasizedDuration, curve: OmiMotion.emphasizedCurve);
    }
  }

  Future<void> _create(MemoriesProvider provider) async {
    PlatformManager.instance.analytics.memoriesPageCreateMemoryBtn();
    await showMemoryDialog(context, provider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Consumer<MemoriesProvider>(
      builder: (context, provider, _) {
        final all = provider.filteredMemories.where((m) => !m.deleted).toList();
        final focus = _focus?.toLowerCase();
        final shown =
            focus == null ? all : all.where((m) => m.content.decodeString.toLowerCase().contains(focus)).toList();
        return Scaffold(
          backgroundColor: OmiColors.surface0,
          appBar: OmiScreenHeader(
            title: l10n.memories,
            trailing: OmiRingButton.glass(
              key: const Key('memories_add'),
              glyph: OmiGlyphs.plusLine,
              label: l10n.createMemoryTooltip,
              onPressed: () => _create(provider),
            ),
          ),
          bottomNavigationBar: const ListeningStrip(),
          body: RefreshIndicator(
            onRefresh: provider.init,
            color: OmiColors.onAccent,
            backgroundColor: OmiColors.accent,
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 10, OmiSize.screenMargin, 20),
              children: [
                if (all.isNotEmpty) ...[
                  MemoryGraphPreview(
                    loadGraph: widget.loadGraph ?? KnowledgeGraphApi.getKnowledgeGraph,
                    selected: _focus,
                    onSelect: (label) => setState(() => _focus = _focus == label ? null : label),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _focus == null ? l10n.memoriesGraphCaption(all.length) : l10n.memoriesAbout(_focus!),
                    style: OmiType.footnote.copyWith(height: 1.4, color: OmiColors.textSecondary),
                  ),
                  const SizedBox(height: 18),
                ],
                if (provider.loading && all.isEmpty)
                  const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: OmiSpinner()))
                else if (all.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Text(
                      l10n.memoriesEmptyV3,
                      textAlign: TextAlign.center,
                      style: OmiType.callout.copyWith(height: 1.5, color: OmiColors.textSecondary),
                    ),
                  )
                else ...[
                  for (final m in shown) MemoryRow(key: ValueKey('memory_row_${m.id}'), memory: m, provider: provider),
                  if (_focus == null) MemoryBulkActions(provider: provider),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The mock's graph (`#memB svg`): the reader in the middle as a filled dot, up to six of the most
/// connected people and topics around them as open rings with their names, thin lines between.
class MemoryGraphPreview extends StatefulWidget {
  const MemoryGraphPreview({super.key, required this.loadGraph, required this.onSelect, this.selected});

  final Future<Map<String, dynamic>> Function() loadGraph;
  final ValueChanged<String> onSelect;
  final String? selected;

  static const double height = 257;

  @override
  State<MemoryGraphPreview> createState() => _MemoryGraphPreviewState();
}

class _GraphNode {
  _GraphNode(this.id, this.label);
  final String id;
  final String label;
  Offset at = Offset.zero;
}

class _MemoryGraphPreviewState extends State<MemoryGraphPreview> {
  List<_GraphNode> _nodes = [];
  List<(int, int)> _edges = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await widget.loadGraph();
      if (!mounted) return;
      final nodes = (data['nodes'] as List<dynamic>? ?? const []).whereType<Map>().toList();
      final edges = (data['edges'] as List<dynamic>? ?? const []).whereType<Map>().toList();
      final name = SharedPreferencesUtil().givenName.trim().toLowerCase();
      bool isUser(Map n) {
        final label = (n['label'] ?? '').toString().trim().toLowerCase();
        return (n['node_type'] ?? '').toString() == 'user' ||
            label == 'me' ||
            label == 'the user' ||
            (name.isNotEmpty && label == name);
      }

      final userIds = {
        for (final n in nodes)
          if (isUser(n)) (n['id'] ?? '').toString()
      };
      final degree = <String, int>{};
      for (final e in edges) {
        for (final k in ['source_id', 'target_id']) {
          final id = (e[k] ?? '').toString();
          degree[id] = (degree[id] ?? 0) + 1;
        }
      }
      final others = nodes.where((n) => !isUser(n) && (n['label'] ?? '').toString().trim().isNotEmpty).toList()
        ..sort((a, b) => (degree[(b['id'] ?? '').toString()] ?? 0).compareTo(degree[(a['id'] ?? '').toString()] ?? 0));
      final top = others.take(6).toList();
      // Around the reader, a node linked to the one before it goes next to it, so lines between
      // names stay short and do not cross the middle.
      final neighbours = <String, Set<String>>{};
      for (final e in edges) {
        final a = (e['source_id'] ?? '').toString(), b = (e['target_id'] ?? '').toString();
        neighbours.putIfAbsent(a, () => {}).add(b);
        neighbours.putIfAbsent(b, () => {}).add(a);
      }
      final picked = <Map>[];
      final left = [...top];
      while (left.isNotEmpty) {
        final last = picked.isEmpty ? null : (picked.last['id'] ?? '').toString();
        final next = left.firstWhere((n) => neighbours[last]?.contains((n['id'] ?? '').toString()) ?? false,
            orElse: () => left.first);
        picked.add(next);
        left.remove(next);
      }
      final list = [
        _GraphNode('you', ''),
        for (final n in picked) _GraphNode((n['id'] ?? '').toString(), (n['label'] ?? '').toString().trim()),
      ];
      final index = {for (final (i, n) in list.indexed) n.id: i};
      final pairs = <(int, int)>{};
      for (var i = 1; i < list.length; i++) {
        pairs.add((0, i));
      }
      for (final e in edges) {
        var a = (e['source_id'] ?? '').toString();
        var b = (e['target_id'] ?? '').toString();
        if (userIds.contains(a)) a = 'you';
        if (userIds.contains(b)) b = 'you';
        final ia = index[a], ib = index[b];
        if (ia != null && ib != null && ia != ib && ia != 0 && ib != 0) pairs.add(ia < ib ? (ia, ib) : (ib, ia));
      }
      setState(() {
        _nodes = list;
        _edges = pairs.toList();
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  /// The mock's places around the reader, clockwise from the top left, for a 346 pt wide graph.
  static const List<(double, double)> _slots = [(-104, -66), (74, -83), (123, 10), (86, 93), (-25, 107), (-116, 59)];

  /// Which of [_slots] [n] names use, spread round the circle.
  static List<int> _slotsFor(int n) => switch (n) {
        1 => const [1],
        2 => const [0, 3],
        3 => const [0, 2, 4],
        4 => const [0, 1, 3, 5],
        5 => const [0, 1, 2, 3, 5],
        _ => const [0, 1, 2, 3, 4, 5],
      };

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _nodes.length < 2) return const SizedBox.shrink();
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        const h = MemoryGraphPreview.height;
        final center = Offset(w / 2, h * 0.48);
        final n = _nodes.length - 1;
        final slots = _slotsFor(n);
        for (var i = 1; i <= n; i++) {
          final (dx, dy) = _slots[slots[i - 1]];
          _nodes[i].at = center + Offset(dx * w / 346, dy * h / MemoryGraphPreview.height);
        }
        _nodes[0].at = center;
        final label = OmiType.caption1.copyWith(color: OmiColors.textPrimary, height: 1.2);
        return SizedBox(
          height: h,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GraphPainter(
                    points: [for (final node in _nodes) node.at],
                    edges: _edges,
                    line: OmiColors.faint.withValues(alpha: 0.5),
                    ink: OmiColors.textPrimary,
                    paper: OmiColors.surface0,
                    selected: _nodes.indexWhere((node) => node.label == widget.selected),
                  ),
                ),
              ),
              Positioned(
                left: center.dx - 30,
                top: center.dy + 12,
                width: 60,
                child: Text(l10n.you, textAlign: TextAlign.center, style: label),
              ),
              for (final node in _nodes.skip(1))
                Positioned(
                  left: node.at.dx - 44,
                  top: node.at.dy - 16,
                  width: 88,
                  height: 46,
                  child: Semantics(
                    button: true,
                    selected: widget.selected == node.label,
                    label: node.label,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        OmiHaptics.selection();
                        widget.onSelect(node.label);
                      },
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Text(
                          node.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: label.copyWith(
                              fontWeight: widget.selected == node.label ? FontWeight.w700 : FontWeight.w400),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.points,
    required this.edges,
    required this.line,
    required this.ink,
    required this.paper,
    required this.selected,
  });

  final List<Offset> points;
  final List<(int, int)> edges;
  final Color line;
  final Color ink;
  final Color paper;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final (a, b) in edges) {
      canvas.drawLine(points[a], points[b], stroke);
    }
    canvas.drawCircle(points[0], 9, Paint()..color = ink);
    final ring = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 1; i < points.length; i++) {
      canvas.drawCircle(points[i], 7, Paint()..color = i == selected ? ink : paper);
      canvas.drawCircle(points[i], 7, ring);
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.points != points || old.edges != edges || old.selected != selected || old.ink != ink;
}
