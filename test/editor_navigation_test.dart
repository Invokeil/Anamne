import 'package:anamne/editor/block_editor.dart';
import 'package:anamne/store/page.dart';
import 'package:anamne/store/database_doc.dart';
import 'package:anamne/ui/database_view.dart';
import 'package:anamne/ui/canvas_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('switching pages saves A under A and displays B text', (tester) async {
    final saved = <AnamnePage>[];
    AnamnePage page(String id, String title) => AnamnePage(
      id: id, title: title, body: '', updatedAt: DateTime.utc(2026),
      blocks: [{'id': '$id-block', 'type': 'paragraph', 'text': '$title body'}],
    );
    Widget editor(AnamnePage doc) => MaterialApp(home: Scaffold(body: BlockEditor(
      key: ValueKey(doc.id), page: doc, pageTitles: const [], databases: const [],
      onSave: (snapshot) async { saved.add(snapshot); },
    )));
    await tester.pumpWidget(editor(page('A', 'Alpha')));
    await tester.enterText(find.byType(TextField).first, 'Alpha edited');
    await tester.pumpWidget(editor(page('B', 'Beta')));
    await tester.pump();
    expect(saved.single.id, 'A');
    expect(saved.single.title, 'Alpha edited');
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Beta body'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Beta edited');
    await tester.pump(const Duration(milliseconds: 450));
    expect(saved.last.id, 'B');
    expect(saved.last.title, 'Beta edited');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leaving a database before debounce preserves its latest title', (tester) async {
    final saved = <DbDoc>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DatabaseView(
      doc: DbDoc(id: 'db-A', title: 'Tasks', updatedAt: DateTime.utc(2026)),
      onSave: (snapshot) async { saved.add(snapshot); },
    ))));
    await tester.enterText(find.byType(TextField).first, 'Tasks edited');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(saved.single.id, 'db-A');
    expect(saved.single.title, 'Tasks edited');
  });

  testWidgets('leaving a canvas before debounce preserves a new node', (tester) async {
    final saved = <AnamnePage>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CanvasView(
      page: AnamnePage(id: 'canvas-A', title: 'Ideas', body: '',
          type: 'canvas', updatedAt: DateTime.utc(2026)),
      onSave: (snapshot) async { saved.add(snapshot); },
    ))));
    final point = tester.getCenter(find.byType(CanvasView));
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(point);
    // Let the double-tap recognizer's timers expire before the tree is disposed.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(saved.single.id, 'canvas-A');
    expect(saved.single.data!['nodes'] as List<Object?>, hasLength(1));
  });
}
