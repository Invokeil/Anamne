/// Portable block model for the Anamne editor.
///
/// Blocks are stored flat with an `indent` level (mirroring how large note
/// editors keep editing reliable). The markdown projection in
/// [blocksToMarkdown] / [markdownToBlocks] is the portable format: the same
/// files stay readable in Obsidian, and `[[wikilinks]]` survive round trips.
class Block {
  const Block({
    required this.id,
    this.type = 'paragraph',
    this.text = '',
    this.indent = 0,
    this.checked = false,
    this.language,
    this.props = const {},
  });

  final String id;
  final String type;
  final String text;
  final int indent;
  final bool checked;
  final String? language;
  final Map<String, Object?> props;

  static const types = [
    'paragraph', 'h1', 'h2', 'h3', 'todo', 'bullet', 'number',
    'quote', 'code', 'divider', 'callout', 'database',
  ];

  bool get isEmptyText => text.trim().isEmpty;

  Block copyWith({
    String? type,
    String? text,
    int? indent,
    bool? checked,
    String? language,
    bool clearLanguage = false,
    Map<String, Object?>? props,
  }) =>
      Block(
        id: id,
        type: type ?? this.type,
        text: text ?? this.text,
        indent: indent ?? this.indent,
        checked: checked ?? this.checked,
        language: clearLanguage ? null : language ?? this.language,
        props: props ?? this.props,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type,
        'text': text,
        'indent': indent,
        if (type == 'todo') 'checked': checked,
        if (language != null) 'language': language,
        if (props.isNotEmpty) 'props': props,
      };

  factory Block.fromJson(Map<String, Object?> json) => Block(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'paragraph',
        text: json['text'] as String? ?? '',
        indent: (json['indent'] as num?)?.toInt() ?? 0,
        checked: json['checked'] as bool? ?? false,
        language: json['language'] as String?,
        props: json['props'] == null
            ? const {}
            : Map<String, Object?>.from(json['props'] as Map),
      );

  /// Prefix inserted when this block type is created from the slash menu.
  static Block empty(String id, String type) => Block(
        id: id,
        type: type,
        text: type == 'divider' ? '' : '',
      );

  /// Blocks the editor treats as "text containers" when merging on Backspace.
  static const mergeableTypes = [
    'paragraph', 'h1', 'h2', 'h3', 'todo', 'bullet', 'number', 'quote', 'callout',
  ];
}

final _wikilinkPattern = RegExp(r'\[\[([^\[\]\n]+)\]\]');

/// All `[[wikilink]]` targets inside [text], in order, deduplicated.
List<String> wikilinkTargets(String text) {
  final targets = <String>[];
  for (final match in _wikilinkPattern.allMatches(text)) {
    final target = match.group(1)?.trim();
    if (target != null && target.isNotEmpty && !targets.contains(target)) {
      targets.add(target);
    }
  }
  return targets;
}

/// True when [offset] sits inside a `[[wikilink]]` span of [text].
bool offsetInsideWikilink(String text, int offset) {
  for (final match in _wikilinkPattern.allMatches(text)) {
    if (offset > match.start && offset <= match.end) return true;
  }
  return false;
}

const _indentUnit = '  ';

/// Serializes blocks to portable Markdown.
String blocksToMarkdown(List<Block> blocks) {
  final lines = <String>[];
  var numberRun = 0;
  var numberRunIndent = -1;
  for (final block in blocks) {
    final pad = _indentUnit * block.indent;
    if (block.type == 'number' && block.indent == numberRunIndent) {
      numberRun += 1;
    } else {
      numberRun = 1;
      numberRunIndent = block.indent;
    }
    switch (block.type) {
      case 'h1':
        lines.add('$pad# ${block.text}');
      case 'h2':
        lines.add('$pad## ${block.text}');
      case 'h3':
        lines.add('$pad### ${block.text}');
      case 'todo':
        lines.add('$pad- [${block.checked ? 'x' : ' '}] ${block.text}');
      case 'bullet':
        lines.add('$pad- ${block.text}');
      case 'number':
        lines.add('$pad$numberRun. ${block.text}');
      case 'quote':
        for (final line in block.text.split('\n')) {
          lines.add('$pad> $line');
        }
      case 'callout':
        lines.add('$pad> [!NOTE] ${block.text}');
      case 'code':
        final fence = '```';
        lines.add('$pad$fence${block.language ?? ''}');
        lines.addAll(block.text.split('\n').map((l) => '$pad$l'));
        lines.add('$pad$fence');
      case 'divider':
        lines.add('$pad---');
      case 'database':
        lines.add('$pad@database:${block.props['databaseId'] ?? ''}');
      default:
        if (block.text.isNotEmpty || blocks.length == 1) lines.add('$pad${block.text}');
    }
  }
  return lines.join('\n');
}

/// Parses portable Markdown back into blocks. Unknown constructs degrade to
/// paragraphs so imported files are never lost.
List<Block> markdownToBlocks(String markdown, {String Function()? newId}) {
  String id() => newId?.call() ?? '';
  final blocks = <Block>[];
  final lines = markdown.split('\n');
  var inFence = false;
  var fenceLanguage = '';
  var fencePad = '';
  final fenceBuffer = <String>[];
  final numberCounters = <int, int>{};

  void flushFence() {
    blocks.add(Block(
      id: id(),
      type: 'code',
      text: fenceBuffer.join('\n'),
      indent: fencePad.length ~/ _indentUnit.length,
      language: fenceLanguage.isEmpty ? null : fenceLanguage,
    ));
    fenceBuffer.clear();
    fenceLanguage = '';
  }

  for (final raw in lines) {
    if (inFence) {
      if (raw.trimRight() == '```') {
        inFence = false;
        flushFence();
      } else {
        final stripped = fencePad.isNotEmpty && raw.startsWith(fencePad)
            ? raw.substring(fencePad.length)
            : raw;
        fenceBuffer.add(stripped);
      }
      continue;
    }
    if (raw.trim().isEmpty) continue;
    final padMatch = RegExp(r'^((?:  |\t)*)').firstMatch(raw)!;
    final pad = padMatch.group(1)!;
    final indent = pad.replaceAll('\t', _indentUnit).length ~/ _indentUnit.length;
    final rest = raw.substring(pad.length);
    if (rest.startsWith('```')) {
      inFence = true;
      fencePad = pad;
      fenceLanguage = rest.substring(3).trim();
      continue;
    }
    if (rest.startsWith('@database:')) {
      blocks.add(Block(
        id: id(), type: 'database', indent: indent,
        props: {'databaseId': rest.substring('@database:'.length).trim()},
      ));
      continue;
    }
    if (rest == '---' || rest == '***') {
      blocks.add(Block(id: id(), type: 'divider', indent: indent));
      continue;
    }
    if (rest.startsWith('#### ')) {
      blocks.add(Block(id: id(), type: 'h3', text: rest.substring(5), indent: indent));
      continue;
    }
    if (rest.startsWith('### ')) {
      blocks.add(Block(id: id(), type: 'h3', text: rest.substring(4), indent: indent));
      continue;
    }
    if (rest.startsWith('## ')) {
      blocks.add(Block(id: id(), type: 'h2', text: rest.substring(3), indent: indent));
      continue;
    }
    if (rest.startsWith('# ')) {
      blocks.add(Block(id: id(), type: 'h1', text: rest.substring(2), indent: indent));
      continue;
    }
    final todo = RegExp(r'^- \[( |x|X)\] (.*)$').firstMatch(rest);
    if (todo != null) {
      blocks.add(Block(
        id: id(), type: 'todo', indent: indent,
        checked: todo.group(1)!.toLowerCase() == 'x', text: todo.group(2)!,
      ));
      continue;
    }
    if (rest.startsWith('- ') || rest.startsWith('* ')) {
      blocks.add(Block(id: id(), type: 'bullet', text: rest.substring(2), indent: indent));
      continue;
    }
    final numbered = RegExp(r'^\d+[.)] (.*)$').firstMatch(rest);
    if (numbered != null) {
      final run = (numberCounters[indent] ?? 0) + 1;
      numberCounters[indent] = run;
      blocks.add(Block(id: id(), type: 'number', text: numbered.group(1)!, indent: indent));
      continue;
    }
    final callout = RegExp(r'^> \[!NOTE\] ?(.*)$').firstMatch(rest);
    if (callout != null) {
      blocks.add(Block(id: id(), type: 'callout', text: callout.group(1)!, indent: indent));
      continue;
    }
    if (rest.startsWith('> ')) {
      blocks.add(Block(id: id(), type: 'quote', text: rest.substring(2), indent: indent));
      continue;
    }
    blocks.add(Block(id: id(), type: 'paragraph', text: rest, indent: indent));
  }
  if (inFence && fenceBuffer.isNotEmpty) flushFence();
  return blocks;
}
