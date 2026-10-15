import 'package:anamne/main.dart';
import 'package:anamne/store/page_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reports local store initialization errors', (tester) async {
    final failing =
        Future<PageRepository>.error(StateError('test storage error'));
    failing.ignore(); // handled by the FutureBuilder in AnamneApp
    await tester.pumpWidget(AnamneApp(repository: failing));
    await tester.pump();
    expect(find.textContaining('Could not open local workspace'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
