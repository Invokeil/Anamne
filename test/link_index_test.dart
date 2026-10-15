import 'package:anamne/knowledge/link_index.dart';
import 'package:anamne/store/page.dart';
import 'package:flutter_test/flutter_test.dart';

AnamnePage page(String id, String title, String body) => AnamnePage(
      id: id,
      title: title,
      body: body,
      updatedAt: DateTime.utc(2026, 10, 15),
      blocks: [
        {'id': 'b1', 'type': 'paragraph', 'text': body, 'indent': 0},
      ],
    );

void main() {
  test('backlinks resolve by case-insensitive title match', () {
    final pages = [
      page('a', 'Zettel Box', 'an inbox for [[ডিজিটাল বাগান]] notes'),
      page('b', 'ডিজিটাল বাগান', 'roots in [[zettel box]]'),
      page('c', 'Island', 'no links'),
    ];
    final index = LinkIndex(pages);
    final garden = pages[1];
    final backlinks = index.backlinksTo(garden);
    expect(backlinks.map((p) => p.id), ['a']);
    // The garden links to [[zettel box]], which resolves to page a.
    expect(index.outgoingTo(garden).map((p) => p.id), ['a']);
    expect(index.edges(), contains(('b', 'a')));
    // Self links do not create edges.
    final selfIndex = LinkIndex([page('d', 'Solo', 'talks about [[Solo]]')]);
    expect(selfIndex.edges(), isEmpty);
  });
}
