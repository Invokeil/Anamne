import 'package:anamne/editor/block.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('block list survives the markdown round trip', () {
    final blocks = [
      const Block(id: '1', type: 'h1', text: 'প্রজেক্ট প্ল্যান'),
      const Block(id: '2', text: 'First paragraph with [[Wiki Link]]'),
      const Block(id: '3', type: 'todo', text: 'Ship sync', checked: true),
      const Block(id: '4', type: 'todo', text: 'Write tests'),
      const Block(id: '5', type: 'bullet', text: 'idea one', indent: 1),
      const Block(id: '6', type: 'number', text: 'step one'),
      const Block(id: '7', type: 'quote', text: 'stay offline-first'),
      const Block(id: '8', type: 'callout', text: 'remember backups'),
      const Block(id: '9', type: 'code', text: 'void main() {}', language: 'dart'),
      const Block(id: '10', type: 'divider'),
    ];
    final markdown = blocksToMarkdown(blocks);
    final parsed = markdownToBlocks(markdown, newId: () => 'x');
    expect(parsed.map((b) => b.type).toList(),
        blocks.map((b) => b.type).toList());
    expect(parsed.map((b) => b.text).toList(),
        blocks.map((b) => b.text).toList());
    expect(parsed[0].text, 'প্রজেক্ট প্ল্যান');
    expect(parsed[2].checked, isTrue);
    expect(parsed[3].checked, isFalse);
    expect(parsed[4].indent, 1);
    expect(parsed[8].language, 'dart');
    // Re-serializing the parsed blocks keeps the same markdown shape.
    expect(blocksToMarkdown(parsed), markdown);
  });

  test('wikilink targets are extracted in order and without duplicates', () {
    const text = 'see [[First]] then [[Second]] and [[First]] again';
    expect(wikilinkTargets(text), ['First', 'Second']);
    expect(wikilinkTargets('no links here'), isEmpty);
    expect(offsetInsideWikilink(text, 6), isTrue);
    expect(offsetInsideWikilink(text, 0), isFalse);
  });

  test('legacy markdown bodies degrade gracefully instead of losing text', () {
    final blocks = markdownToBlocks('# Title\n\nSome plain text.\n\n- item\n',
        newId: () => 'y');
    final text = blocks.map((b) => b.text).join('\n');
    expect(text, contains('Title'));
    expect(text, contains('Some plain text.'));
    expect(text, contains('item'));
  });
}
