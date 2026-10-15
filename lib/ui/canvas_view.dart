import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../store/page.dart';
import '../store/draft_saver.dart';
import 'theme.dart';

class CanvasNode {
  CanvasNode({
    required this.id,
    required this.x,
    required this.y,
    this.width = 180,
    this.height = 90,
    this.text = '',
    this.color = 0xFFFDF3C7,
  });

  final String id;
  double x;
  double y;
  double width;
  double height;
  String text;
  int color;

  Offset get center => Offset(x + width / 2, y + height / 2);

  Map<String, Object?> toJson() => {
        'id': id, 'x': x, 'y': y, 'width': width, 'height': height,
        'text': text, 'color': color,
      };

  factory CanvasNode.fromJson(Map<String, Object?> json) => CanvasNode(
        id: json['id'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: ((json['width'] as num?) ?? 180).toDouble(),
        height: ((json['height'] as num?) ?? 90).toDouble(),
        text: json['text'] as String? ?? '',
        color: ((json['color'] as num?) ?? 0xFFFDF3C7).toInt(),
      );
}

class CanvasEdge {
  CanvasEdge({required this.id, required this.from, required this.to});
  final String id;
  final String from;
  final String to;

  Map<String, Object?> toJson() => {'id': id, 'from': from, 'to': to};

  factory CanvasEdge.fromJson(Map<String, Object?> json) => CanvasEdge(
        id: json['id'] as String,
        from: json['from'] as String,
        to: json['to'] as String,
      );
}

const _palette = [
  0xFFFDF3C7, 0xFFDCEBDD, 0xFFDBE7F5, 0xFFF7E0DC, 0xFFEFE9F6,
];

/// Obsidian-style canvas: draggable sticky notes, connectors, pan and zoom.
/// Stored as page.data JSON so it syncs with the rest of the workspace.
class CanvasView extends StatefulWidget {
  const CanvasView({super.key, required this.page, required this.onSave});

  final AnamnePage page;
  final Future<void> Function(AnamnePage) onSave;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> with WidgetsBindingObserver {
  final TransformationController _transform = TransformationController();
  List<CanvasNode> _nodes = [];
  List<CanvasEdge> _edges = [];
  String? _selectedId;
  String? _connectFrom;
  late final DraftSaver<AnamnePage> _saver;

  // Gesture bookkeeping.
  String? _dragNodeId;
  Offset? _dragNodeStart;
  Offset? _dragSceneStart;
  Matrix4? _gestureStartMatrix;
  Offset? _gestureStartFocal;
  double _gestureStartScale = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _saver = DraftSaver((page) => widget.onSave(page));
    _load();
  }

  @override
  void didUpdateWidget(covariant CanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id || (!_saver.hasPending && !_saver.isSaving)) _load();
  }

  void _load() {
    final data = widget.page.data ?? const {};
    _nodes = ((data['nodes'] as List<Object?>?) ?? const [])
        .whereType<Map<String, Object?>>()
        .map(CanvasNode.fromJson)
        .toList();
    _edges = ((data['edges'] as List<Object?>?) ?? const [])
        .whereType<Map<String, Object?>>()
        .map(CanvasEdge.fromJson)
        .toList();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saver.dispose();
    _transform.dispose();
    super.dispose();
  }

  Map<String, Object?> _payload() => {
        'nodes': _nodes.map((n) => n.toJson()).toList(),
        'edges': _edges.map((e) => e.toJson()).toList(),
      };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_saver.flush());
  }

  void _scheduleSave() {
    _saver.schedule(widget.page.copyWith(data: _payload()));
  }

  CanvasNode? _nodeWithId(String? id) =>
      id == null ? null : _nodes.where((n) => n.id == id).firstOrNull;

  CanvasNode? _hitTest(Offset scene) {
    for (final node in _nodes.reversed) {
      if (scene.dx >= node.x &&
          scene.dx <= node.x + node.width &&
          scene.dy >= node.y &&
          scene.dy <= node.y + node.height) {
        return node;
      }
    }
    return null;
  }

  void _addNode(Offset scenePoint) {
    final node = CanvasNode(
      id: 'n${DateTime.now().microsecondsSinceEpoch}',
      x: scenePoint.dx - 90,
      y: scenePoint.dy - 45,
      color: _palette[_nodes.length % _palette.length],
    );
    setState(() {
      _nodes.add(node);
      _selectedId = node.id;
    });
    _scheduleSave();
  }

  void _toggleConnect(CanvasNode node) {
    if (_connectFrom == null) {
      setState(() {
        _selectedId = node.id;
        _connectFrom = node.id;
      });
      return;
    }
    if (_connectFrom == node.id) {
      setState(() => _connectFrom = null);
      return;
    }
    final exists = _edges.any((e) =>
        (e.from == _connectFrom && e.to == node.id) ||
        (e.to == _connectFrom && e.from == node.id));
    if (!exists) {
      setState(() {
        _edges.add(CanvasEdge(
          id: 'e${DateTime.now().microsecondsSinceEpoch}',
          from: _connectFrom!,
          to: node.id,
        ));
        _connectFrom = null;
      });
      _scheduleSave();
    } else {
      setState(() => _connectFrom = null);
    }
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _nodes.removeWhere((n) => n.id == id);
      _edges.removeWhere((e) => e.from == id || e.to == id);
      _selectedId = null;
      _connectFrom = null;
    });
    _scheduleSave();
  }

  Future<void> _editNodeText(CanvasNode node) async {
    final controller = TextEditingController(text: node.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    setState(() => node.text = result);
    _scheduleSave();
  }

  Offset _toScene(Offset screenPoint) => MatrixUtils.transformPoint(
        Matrix4.inverted(_transform.value),
        screenPoint,
      );

  void _onScaleStart(ScaleStartDetails details) {
    final scene = _toScene(details.localFocalPoint);
    _gestureStartMatrix = _transform.value.clone();
    _gestureStartFocal = details.localFocalPoint;
    _gestureStartScale = 1.0;
    if (details.pointerCount == 1) {
      final hit = _hitTest(scene);
      if (hit != null) {
        _dragNodeId = hit.id;
        _dragNodeStart = Offset(hit.x, hit.y);
        _dragSceneStart = scene;
        setState(() => _selectedId = hit.id);
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_dragNodeId != null && details.pointerCount == 1) {
      final scene = _toScene(details.localFocalPoint);
      final node = _nodeWithId(_dragNodeId);
      final start = _dragNodeStart;
      final startScene = _dragSceneStart;
      if (node == null || start == null || startScene == null) return;
      final delta = scene - startScene;
      setState(() {
        node.x = start.dx + delta.dx;
        node.y = start.dy + delta.dy;
      });
      return;
    }
    final startMatrix = _gestureStartMatrix;
    final startFocal = _gestureStartFocal;
    if (startMatrix == null || startFocal == null) return;
    final focalDelta = details.localFocalPoint - startFocal;
    final scaleDelta =
        (details.scale / (_gestureStartScale == 0 ? 1.0 : _gestureStartScale))
            .clamp(0.25, 4.0);
    final matrix = Matrix4.identity()
      ..translateByDouble(startFocal.dx, startFocal.dy, 0, 1)
      ..scaleByDouble(scaleDelta, scaleDelta, 1, 1)
      ..translateByDouble(-startFocal.dx, -startFocal.dy, 0, 1)
      ..multiply(startMatrix);
    matrix.translateByDouble(focalDelta.dx, focalDelta.dy, 0, 1);
    _transform.value = matrix;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_dragNodeId != null) _scheduleSave();
    _dragNodeId = null;
    _dragNodeStart = null;
    _dragSceneStart = null;
    _gestureStartMatrix = null;
    _gestureStartFocal = null;
    _gestureStartScale = 1.0;
  }

  void _onWheel(PointerScrollEvent event) {
    final scale = event.scrollDelta.dy > 0 ? 0.92 : 1.08;
    final point = event.localPosition;
    final matrix = Matrix4.identity()
      ..translateByDouble(point.dx, point.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-point.dx, -point.dy, 0, 1);
    _transform.value = matrix.multiplied(_transform.value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _nodeWithId(_selectedId);
    return Stack(children: [
      Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) _onWheel(event);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          onTapUp: (details) {
            final scene = _toScene(details.localPosition);
            final hit = _hitTest(scene);
            setState(() => _selectedId = hit?.id);
          },
          onDoubleTapDown: (details) {
            final scene = _toScene(details.localPosition);
            final hit = _hitTest(scene);
            if (hit != null) {
              _editNodeText(hit);
            } else {
              _addNode(scene);
            }
          },
          onDoubleTap: () {},
          child: ClipRect(
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Transform(
                transform: _transform.value,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _CanvasPainter(
                    nodes: _nodes,
                    edges: _edges,
                    selectedId: _selectedId,
                    connectFrom: _connectFrom,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 10,
        right: 14,
        child: Row(children: [
          if (_connectFrom != null)
            Chip(
              avatar: const Icon(Icons.timeline, size: 15),
              label: const Text('Pick a target node',
                  style: TextStyle(fontSize: 12)),
              onDeleted: () => setState(() => _connectFrom = null),
            ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Connect selected',
            onPressed: selected == null ? null : () => _toggleConnect(selected),
            icon: const Icon(Icons.route_outlined, size: 19),
          ),
          IconButton.filledTonal(
            tooltip: 'Edit text',
            onPressed: selected == null ? null : () => _editNodeText(selected),
            icon: const Icon(Icons.edit_note_outlined, size: 19),
          ),
          IconButton.filledTonal(
            tooltip: 'Delete selected',
            onPressed: selected == null ? null : _deleteSelected,
            icon: const Icon(Icons.delete_outline, size: 19),
          ),
        ]),
      ),
      Positioned(left: 16, bottom: 54, child: DraftSaveStatus(saver: _saver)),
      Positioned(
        bottom: 10,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sheet,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: dividerSand),
            ),
            child: const Text(
                'Double-tap empty space: new note · drag: move · select + tools: connect/edit/delete',
                style: TextStyle(fontSize: 11.5, color: muted)),
          ),
        ),
      ),
    ]);
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.nodes,
    required this.edges,
    required this.selectedId,
    required this.connectFrom,
  });

  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final String? selectedId;
  final String? connectFrom;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    final dotPaint = Paint()
      ..color = hintGray
      ..strokeWidth = 1;
    const grid = 28.0;
    for (var x = 0.0; x < size.width; x += grid) {
      for (var y = 0.0; y < size.height; y += grid) {
        canvas.drawCircle(Offset(x, y), 0.7, dotPaint);
      }
    }
    final edgePaint = Paint()
      ..color = muted
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final nodeById = {for (final n in nodes) n.id: n};
    for (final edge in edges) {
      final a = nodeById[edge.from];
      final b = nodeById[edge.to];
      if (a == null || b == null) continue;
      final start = a.center;
      final end = b.center;
      final control = Offset(
          (start.dx + end.dx) / 2, math.min(start.dy, end.dy) - 44);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      canvas.drawPath(path, edgePaint);
    }
    for (final node in nodes) {
      final rect = Rect.fromLTWH(node.x, node.y, node.width, node.height);
      final paint = Paint()..color = Color(node.color);
      final isSelected = node.id == selectedId || node.id == connectFrom;
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      canvas.drawRRect(rrect, paint);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isSelected ? focusBlue : dividerSand
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.2 : 1,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: node.text.isEmpty ? 'Empty note' : node.text,
          style: TextStyle(
            fontSize: 13,
            color: node.text.isEmpty ? muted : ink,
            fontStyle: node.text.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 5,
        ellipsis: '…',
      );
      textPainter.layout(maxWidth: node.width - 20);
      textPainter.paint(canvas, rect.topLeft + const Offset(10, 10));
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}
