import 'package:anamne/store/page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom API properties survive local and server round trips', () {
    final page = AnamnePage.fromServerRecord({
      'id': 'server-page', 'title': 'Properties', 'body': '', 'version': 7,
      'properties': {'priority': 3, 'tags': ['বাংলা']},
    });
    final restored = AnamnePage.fromJson(page.copyWith(title: 'Edited').toJson());
    expect(restored.toServerRecord()['properties'], {
      'priority': 3, 'tags': ['বাংলা'],
    });
    expect(restored.serverVersion, 7);
  });

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
