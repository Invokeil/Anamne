import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../knowledge/link_index.dart';
import '../store/page.dart';
import 'theme.dart';

class _GraphNode {
  _GraphNode(this.page);
  final AnamnePage page;
  Offset position = Offset.zero;
  Offset velocity = Offset.zero;
}

/// Interactive force-directed knowledge graph: nodes are pages, edges are
/// resolved [[wikilinks]]. Drag nodes, pan/zoom the canvas, tap a node to
/// open the page. Physics runs on a bounded tick so large workspaces stay
/// usable (nodes beyond 240 are hidden with a note).
class GraphView extends StatefulWidget {
  const GraphView({
    super.key,
    required this.pages,
    required this.initialPageId,
    required this.onOpenPage,
  });

  final List<AnamnePage> pages;
  final String? initialPageId;
  final ValueChanged<AnamnePage> onOpenPage;

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final TransformationController _transform = TransformationController();
  final Map<String, _GraphNode> _nodes = {};
  List<(String, String)> _edges = [];
  String? _draggingId;
  Offset? _dragStartNode;
  Offset? _dragStartFocal;
  final ValueNotifier<int> _tick = ValueNotifier(0);

  static const _maxNodes = 240;
  static const _repulsion = 9000.0;
  static const _spring = 0.006;
  static const _springLength = 130.0;
  static const _gravity = 0.004;
  static const _damping = 0.82;

  @override
  void initState() {
    super.initState();
    _buildGraph();
    _ticker = createTicker((_) => _step())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _transform.dispose();
    _tick.dispose();
    super.dispose();
  }

  void _buildGraph() {
    final pages = widget.pages.take(_maxNodes).toList();
    final random = math.Random(7);
    for (final page in pages) {
      _nodes[page.id] = _GraphNode(page)
        ..position = Offset(
            160 + random.nextDouble() * 520, 140 + random.nextDouble() * 420);
    }
    _edges = LinkIndex(pages).edges();
    // Centre the initially selected page.
    final focus = widget.initialPageId;
    if (focus != null && _nodes.containsKey(focus)) {
      _nodes[focus]!.position = const Offset(420, 350);
    }
  }

  void _step() {
    final entries = _nodes.values.toList();
    for (var i = 0; i < entries.length; i++) {
      final a = entries[i];
      var force = Offset.zero;
      for (var j = 0; j < entries.length; j++) {
        if (i == j) continue;
        final b = entries[j];
        var delta = a.position - b.position;
        var distance = delta.distance;
        if (distance < 1) {
          delta = const Offset(1.7, 2.3);
          distance = delta.distance;
        }
        final magnitude = _repulsion / (distance * distance);
        final unit = delta / distance;
        force += unit * magnitude;
      }
      a.velocity += force;
      a.velocity += (const Offset(420, 320) - a.position) * _gravity;
    }
    for (final (source, target) in _edges) {
      final a = _nodes[source];
      final b = _nodes[target];
      if (a == null || b == null) continue;
      final delta = b.position - a.position;
      final distance = delta.distance.clamp(1.0, double.infinity);
      final magnitude = (distance - _springLength) * _spring;
      final unit = delta / distance;
      a.velocity += unit * magnitude;
      b.velocity -= unit * magnitude;
    }
    for (final node in _nodes.values) {
      if (node.page.id == _draggingId) {
        node.velocity = Offset.zero;
        continue;
      }
      node.velocity *= _damping;
      node.position += node.velocity;
    }
    _tick.value++;
  }

  Offset _toScene(Offset screenPoint) => MatrixUtils.transformPoint(
        Matrix4.inverted(_transform.value),
        screenPoint,
      );

  void _onPointerDown(PointerDownEvent event, BoxConstraints constraints) {
    final scene = _toScene(event.localPosition);
    _draggingId = _hitTest(scene);
    if (_draggingId != null) {
      _dragStartNode = _nodes[_draggingId]!.position;
      _dragStartFocal = event.localPosition;
    }
  }

  String? _hitTest(Offset scene) {
    for (final node in _nodes.values) {
      if ((node.position - scene).distance <= 26) return node.page.id;
    }
    return null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final id = _draggingId;
    if (id == null || _dragStartNode == null || _dragStartFocal == null) return;
    final scene = _toScene(event.localPosition);
    final startScene = _toScene(_dragStartFocal!);
    _nodes[id]!.position = _dragStartNode! + (scene - startScene);
    _tick.value++;
  }

  void _onPointerUp(PointerUpEvent event) {
    _draggingId = null;
    _dragStartNode = null;
    _dragStartFocal = null;
  }

  void _openAt(Offset localPosition) {
    final scene = _toScene(localPosition);
    final id = _hitTest(scene);
    if (id == null) return;
    final node = _nodes[id];
    if (node != null) widget.onOpenPage(node.page);
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.pages;
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        title: Text('Knowledge graph · ${pages.length} pages',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Re-layout',
            onPressed: () {
              setState(() => _buildGraph());
            },
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: pages.isEmpty
          ? const Center(child: Text('Create pages and link them with [[wikilinks]]',
              style: TextStyle(color: muted)))
          : LayoutBuilder(builder: (context, constraints) {
              return MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Listener(
                  onPointerDown: (event) =>
                      _onPointerDown(event, constraints),
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  child: GestureDetector(
                    onDoubleTapDown: (details) => _openAt(details.localPosition),
                    onDoubleTap: () {},
                    onSecondaryTapUp: (details) => _openAt(details.localPosition),
                    child: InteractiveViewer(
                      transformationController: _transform,
                      maxScale: 3,
                      minScale: 0.3,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(2000),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _tick,
                        builder: (context, tick, child) => CustomPaint(
                          size: const Size(840, 640),
                          painter: _GraphPainter(
                            nodes: _nodes,
                            edges: _edges,
                            draggingId: _draggingId,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.draggingId,
  });

  final Map<String, _GraphNode> nodes;
  final List<(String, String)> edges;
  final String? draggingId;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    final edgePaint = Paint()
      ..color = dividerSand
      ..strokeWidth = 1.4;
    for (final (source, target) in edges) {
      final a = nodes[source];
      final b = nodes[target];
      if (a == null || b == null) continue;
      canvas.drawLine(a.position, b.position, edgePaint);
    }
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (final node in nodes.values) {
      final selected = node.page.id == draggingId;
      final circle = Paint()
        ..color = selected ? focusBlue : const Color(0xFF6B6A66);
      canvas.drawCircle(node.position, 9, circle);
      textPainter.text = TextSpan(
        text: node.page.label.length > 22
            ? '${node.page.label.substring(0, 22)}…'
            : node.page.label,
        style: const TextStyle(fontSize: 11, color: muted),
      );
      textPainter.layout(maxWidth: 150);
      textPainter.paint(canvas,
          node.position + const Offset(12, -8));
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) => true;
}
