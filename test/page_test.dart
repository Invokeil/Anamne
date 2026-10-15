import 'package:anamne/store/page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a Bangla nested page survives the portable JSON round trip', () {
    final page = AnamnePage(
      id: 'test-id',
      title: 'বাংলা নোট',
      body: 'প্রথম লেখা',
      parentId: 'parent-id',
      updatedAt: DateTime.utc(2026, 10, 15),
    );
    final restored = AnamnePage.fromJson(page.toJson());
    expect(restored.title, page.title);
    expect(restored.body, page.body);
    expect(restored.parentId, page.parentId);
    expect(restored.isDeleted, isFalse);
  });
}
