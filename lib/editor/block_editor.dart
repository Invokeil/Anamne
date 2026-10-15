import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../store/database_doc.dart';
import '../store/page.dart';
import '../store/draft_saver.dart';
import '../ui/theme.dart';
import 'block.dart';
import 'slash_menu.dart';

class _MenuState {
  const _MenuState(this.blockIndex, this.start, this.query);
  final int blockIndex;
  final int start;
  final String query;
}

/// Notion-style block editor: /slash menu, [[wikilink]] autocomplete,
/// Enter/Backspace/Tab block operations, to-dos, toggles, callouts, code and
/// inline database embeds. Content is stored as portable blocks and projected
/// to Markdown by [blocksToMarkdown].
class BlockEditor extends StatefulWidget {
  const BlockEditor({
    super.key,
    required this.page,
    required this.onSave,
    required this.pageTitles,
    required this.databases,
    this.onOpenDatabase,
    this.onOpenPageByTitle,
    this.onCreateDatabase,
  });

  final AnamnePage page;
  final Future<void> Function(AnamnePage) onSave;
  final List<String> pageTitles;
  final List<DbDoc> databases;
  final ValueChanged<String>? onOpenDatabase;
  final ValueChanged<String>? onOpenPageByTitle;
  final Future<DbDoc?> Function()? onCreateDatabase;

  @override
  State<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends State<BlockEditor> with WidgetsBindingObserver {
  static const _uuid = Uuid();

  late List<Block> _blocks;
  late List<TextEditingController?> _controllers;
  late List<FocusNode> _focusNodes;
  late final TextEditingController _title;
  final Set<String> _collapsedToggles = {};
  late final DraftSaver<AnamnePage> _saver;
  _MenuState? _slashMenu;
  _MenuState? _linkMenu;
  String? _linkUnderCaret;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _saver = DraftSaver((page) => widget.onSave(page));
    _title = TextEditingController(text: widget.page.title);
    _blocks = widget.page.blocks.map(Block.fromJson).toList();
    if (_blocks.isEmpty) _blocks = [Block(id: _uuid.v4())];
    _controllers = [];
    _focusNodes = [];
    _rebuildRows();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saver.dispose();
    _title.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    for (final controller in _controllers) {
      controller?.dispose();
    }
    super.dispose();
  }

  bool _isTextType(String type) => type != 'divider' && type != 'database';

  void _rebuildRows() {
    for (final controller in _controllers) {
      controller?.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    _controllers = List<TextEditingController?>.filled(_blocks.length, null,
        growable: true);
    _focusNodes = List<FocusNode>.generate(_blocks.length, (_) => FocusNode());
    for (var i = 0; i < _blocks.length; i++) {
      if (_isTextType(_blocks[i].type)) {
        final controller = TextEditingController(text: _blocks[i].text);
        controller.addListener(() => _onControllerChanged(controller));
        _controllers[i] = controller;
      }
    }
  }

  /// Aligns controller/focus arrays with the current block list.
  void _syncRows() {
    while (_controllers.length < _blocks.length) {
      _controllers.add(null);
      _focusNodes.add(FocusNode());
    }
    while (_controllers.length > _blocks.length) {
      final index = _controllers.length - 1;
      _controllers[index]?.dispose();
      _focusNodes[index].dispose();
      _controllers.removeAt(index);
      _focusNodes.removeAt(index);
    }
    for (var i = 0; i < _blocks.length; i++) {
      final textual = _isTextType(_blocks[i].type);
      if (textual && _controllers[i] == null) {
        final controller = TextEditingController(text: _blocks[i].text);
        controller.addListener(() => _onControllerChanged(controller));
        _controllers[i] = controller;
      } else if (!textual && _controllers[i] != null) {
        _controllers[i]!.dispose();
        _controllers[i] = null;
      }
    }
    // Positional controllers must mirror the reordered block texts.
    for (var i = 0; i < _blocks.length; i++) {
      final controller = _controllers[i];
      if (controller != null && controller.text != _blocks[i].text) {
        controller.value = TextEditingValue(
          text: _blocks[i].text,
          selection: TextSelection.collapsed(offset: _blocks[i].text.length),
        );
      }
    }
  }

  void _onControllerChanged(TextEditingController controller) {
    final i = _controllers.indexOf(controller);
    if (i < 0 || i >= _blocks.length) return;
    final text = controller.text;
    final caret = controller.selection.baseOffset;
    final changed = _blocks[i].text != text;
    if (changed) _blocks[i] = _blocks[i].copyWith(text: text);
    if (text.contains('\n') && _blocks[i].type != 'code') {
      // IME keyboards insert the newline before we can intercept it.
      final splitAt = text.indexOf('\n');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _splitBlock(i, splitAt, imeText: text);
      });
      return;
    }
    if (changed) {
      _updateMenuState(i, text, caret);
      _scheduleSave();
    }
  }

  void _updateMenuState(int i, String text, int? caret) {
    _MenuState? slash;
    _MenuState? link;
    var linkUnderCaret = _linkUnderCaret;
    linkUnderCaret = null;
    if (caret != null && caret >= 0 && caret <= text.length) {
      final before = text.substring(0, caret);
      final linkStart = RegExp(r'\[\[([^\[\]\n]*)$').firstMatch(before);
      if (linkStart != null) {
        link = _MenuState(
            i, caret - (linkStart.group(0)?.length ?? 0), linkStart.group(1) ?? '');
      } else {
        final slashMatch = RegExp(r'(?:^|\s)/([A-Za-z0-9 -]*)$').firstMatch(before);
        if (slashMatch != null) {
          slash = _MenuState(i, before.lastIndexOf('/'), slashMatch.group(1) ?? '');
        } else {
          for (final match
              in RegExp(r'\[\[([^\[\]\n]+)\]\]').allMatches(text)) {
            if (caret > match.start && caret <= match.end) {
              linkUnderCaret = match.group(1);
              break;
            }
          }
        }
      }
    }
    final unchanged = slash == null && _slashMenu == null ||
        (slash != null && _slashMenu != null && slash.query == _slashMenu!.query &&
            slash.blockIndex == _slashMenu!.blockIndex);
    final linkUnchanged = link == null && _linkMenu == null ||
        (link != null && _linkMenu != null && link.query == _linkMenu!.query &&
            link.blockIndex == _linkMenu!.blockIndex);
    if (unchanged && linkUnchanged && linkUnderCaret == _linkUnderCaret) return;
    setState(() {
      _slashMenu = slash;
      _linkMenu = link;
      _linkUnderCaret = linkUnderCaret;
    });
  }

  void _applySlash(SlashCommand command) {
    final menu = _slashMenu;
    if (menu == null) return;
    final i = menu.blockIndex;
    final controller = _controllers[i];
    if (controller == null) return;
    final text = controller.text;
    final caret = controller.selection.baseOffset;
    final end = caret < 0
        ? (menu.start + 1 + menu.query.length).clamp(0, text.length)
        : caret.clamp(0, text.length);
    final kept = text.substring(0, menu.start) + text.substring(end);
    controller.value = TextEditingValue(
      text: kept,
      selection: TextSelection.collapsed(offset: menu.start.clamp(0, kept.length)),
    );
    _blocks[i] = _blocks[i].copyWith(text: kept);
    setState(() => _slashMenu = null);
    if (command.type == 'divider') {
      setState(() {
        _blocks[i] = Block(id: _blocks[i].id, type: 'divider', indent: _blocks[i].indent);
        _blocks.insert(i + 1, Block(id: _uuid.v4()));
        _syncRows();
      });
      _scheduleSave();
      return;
    }
    if (command.type == 'database') {
      setState(() {
        _blocks[i] = Block(
            id: _blocks[i].id, type: 'database', indent: _blocks[i].indent);
        _syncRows();
      });
      _scheduleSave();
      return;
    }
    setState(() {
      _blocks[i] = _blocks[i].copyWith(type: command.type, checked: false);
    });
    _scheduleSave();
    _focusBlock(i, atEnd: true);
  }

  void _insertBlock(int index, Block block) {
    setState(() {
      _blocks.insert(index, block);
      _syncRows();
    });
  }

  void _removeBlock(int index) {
    if (_blocks.length <= 1) return;
    setState(() {
      _blocks.removeAt(index);
      _syncRows();
    });
  }

  void _splitBlock(int index, int offset, {String? imeText}) {
    final controller = _controllers[index];
    if (controller == null) return;
    final current = _blocks[index];
    final text = imeText ?? controller.text;
    final left = offset <= text.length ? text.substring(0, offset) : text;
    var right = offset < text.length ? text.substring(offset) : '';
    if (imeText != null) right = right.replaceFirst('\n', '');
    final continues = ['todo', 'bullet', 'number', 'toggle'];
    final nextType =
        current.type == 'h1' || current.type == 'h2' || current.type == 'h3'
            ? 'paragraph'
            : current.type;
    if (continues.contains(current.type) && current.text.trim().isEmpty ||
        (current.type == 'quote' || current.type == 'callout') &&
            current.text.trim().isEmpty) {
      // Enter on an empty list item exits the list (Notion behaviour).
      setState(() => _blocks[index] = current.copyWith(type: 'paragraph'));
      _scheduleSave();
      return;
    }
    setState(() {
      _blocks[index] = current.copyWith(text: left);
      _blocks.insert(
          index + 1,
          Block(
            id: _uuid.v4(),
            type: nextType,
            text: right,
            indent: current.indent,
          ));
      _syncRows();
    });
    _scheduleSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNodes[index + 1].requestFocus();
      _controllers[index + 1]?.selection = const TextSelection.collapsed(offset: 0);
    });
  }

  void _mergeWithPrevious(int index) {
    if (index == 0) return;
    final current = _blocks[index];
    final previous = _blocks[index - 1];
    if (!_isTextType(previous.type)) {
      setState(() {
        _blocks.removeAt(index - 1);
        _syncRows();
      });
      _scheduleSave();
      return;
    }
    if (!_isTextType(current.type)) return;
    if (current.indent > 0) {
      setState(() {
        _blocks[index] = current.copyWith(indent: current.indent - 1);
      });
      _scheduleSave();
      return;
    }
    if (current.type != 'paragraph') {
      setState(() {
        _blocks[index] = current.copyWith(type: 'paragraph');
      });
      _scheduleSave();
      return;
    }
    final junction = previous.text.length;
    setState(() {
      _blocks[index - 1] = previous.copyWith(text: previous.text + current.text);
      _blocks.removeAt(index);
      _syncRows();
    });
    _scheduleSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1]?.selection =
          TextSelection.collapsed(offset: junction);
    });
  }

  void _indent(int index, int delta) {
    final block = _blocks[index];
    final previous = index > 0 ? _blocks[index - 1] : null;
    final maxIndent = previous == null ? 0 : previous.indent + 1;
    final target = (block.indent + delta).clamp(0, maxIndent.clamp(0, 6));
    if (target == block.indent) return;
    setState(() {
      _blocks[index] = block.copyWith(indent: target);
    });
    _scheduleSave();
  }

  void _moveVisible(int fromVisible, int newVisibleIndex) {
    final from = fromVisible;
    var to = newVisibleIndex >= _blocks.length
        ? _blocks.length
        : newVisibleIndex;
    setState(() {
      final block = _blocks.removeAt(from);
      _blocks.insert(to, block);
      _syncRows();
    });
    _scheduleSave();
  }

  void _toggleCheckbox(int index) {
    setState(() {
      _blocks[index] = _blocks[index].copyWith(checked: !_blocks[index].checked);
    });
    _scheduleSave();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_saver.flush());
  }

  @override
  void didUpdateWidget(covariant BlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id ||
        (!_saver.hasPending && !_saver.isSaving &&
          (widget.page.title != _title.text ||
           jsonEncode(widget.page.blocks) != jsonEncode(_blocks.map((b) => b.toJson()).toList())))) {
      if (oldWidget.page.id != widget.page.id) unawaited(_saver.flush());
      _title.text = widget.page.title;
      _blocks = widget.page.blocks.map(Block.fromJson).toList();
      if (_blocks.isEmpty) _blocks = [Block(id: _uuid.v4())];
      _rebuildRows();
    }
  }

  void _scheduleSave() {
    _saver.schedule(widget.page.copyWith(title: _title.text,
      blocks: _blocks.map((b) => b.toJson()).toList()));
  }

  void _focusBlock(int index, {bool atEnd = false}) {
    if (index < 0 || index >= _blocks.length) return;
    if (!_isTextType(_blocks[index].type)) return;
    _focusNodes[index].requestFocus();
    final length = _controllers[index]?.text.length ?? 0;
    _controllers[index]?.selection =
        TextSelection.collapsed(offset: atEnd ? length : 0);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event, int index) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final controller = _controllers[index];
    if (controller == null) return KeyEventResult.ignored;
    final caret = controller.selection.baseOffset;
    final atStart = caret <= 0;
    final atEnd = caret >= controller.text.length;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed ||
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isAltPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        return KeyEventResult.ignored;
      }
      if (_blocks[index].type == 'code') return KeyEventResult.ignored;
      _splitBlock(index, caret < 0 ? 0 : caret);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _indent(index, HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace && atStart) {
      _mergeWithPrevious(index);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && atStart) {
      _focusBlock(index - 1, atEnd: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && atEnd) {
      _focusBlock(index + 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        (_slashMenu != null || _linkMenu != null)) {
      setState(() {
        _slashMenu = null;
        _linkMenu = null;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  TextStyle _blockStyle(Block block) {
    const base = TextStyle(fontSize: 16, height: 1.62, color: ink);
    switch (block.type) {
      case 'h1':
        return base.copyWith(fontSize: 24, fontWeight: FontWeight.w700, height: 1.3);
      case 'h2':
        return base.copyWith(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3);
      case 'h3':
        return base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35);
      case 'code':
        return base.copyWith(fontFamily: 'monospace', fontSize: 14, height: 1.5);
      case 'quote':
        return base.copyWith(color: muted);
      default:
        return base;
    }
  }

  InputDecoration _decoration(Block block) => InputDecoration(
        hintText:
            block.type == 'paragraph' ? 'Start writing, or press "/" for blocks' : '',
        hintStyle: const TextStyle(color: hintGray),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 5),
      );

  int _numberFor(int index) {
    var count = 1;
    for (var i = index - 1; i >= 0; i--) {
      if (_blocks[i].type == 'number' && _blocks[i].indent == _blocks[index].indent) {
        count++;
      } else if (_blocks[i].indent <= _blocks[index].indent) {
        break;
      }
    }
    return count;
  }

  bool _isHiddenByToggle(int index) {
    for (var i = index - 1; i >= 0; i--) {
      final toggle = _blocks[i];
      if (toggle.type == 'toggle' &&
          _collapsedToggles.contains(toggle.id) &&
          _blocks[index].indent > toggle.indent) {
        var enclosed = true;
        for (var j = i + 1; j < index; j++) {
          if (_blocks[j].indent <= toggle.indent) {
            enclosed = false;
            break;
          }
        }
        if (enclosed) return true;
      }
    }
    return false;
  }

  Widget _leadingFor(Block block, int index) {
    switch (block.type) {
      case 'todo':
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: block.checked,
              onChanged: (_) => _toggleCheckbox(index),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        );
      case 'bullet':
        return const Padding(
          padding: EdgeInsets.only(top: 9, right: 2),
          child: Text('•', style: TextStyle(fontSize: 18, height: 1)),
        );
      case 'number':
        return Padding(
          padding: const EdgeInsets.only(top: 5, right: 2),
          child: SizedBox(
            width: 18,
            child: Text('${_numberFor(index)}.',
                style: const TextStyle(fontSize: 15, height: 1.3)),
          ),
        );
      case 'toggle':
        return IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
            _collapsedToggles.contains(block.id)
                ? Icons.arrow_right
                : Icons.arrow_drop_down,
            size: 20,
            color: muted,
          ),
          onPressed: () => setState(() {
            if (!_collapsedToggles.remove(block.id)) {
              _collapsedToggles.add(block.id);
            }
          }),
        );
      default:
        return const SizedBox(width: 6);
    }
  }

  Widget _blockRow(BuildContext context, int index, int dragIndex) {
    final block = _blocks[index];
    final controller = _controllers[index];
    final pad = EdgeInsets.only(left: block.indent * 22.0);
    Widget content;
    switch (block.type) {
      case 'divider':
        content = Padding(
          padding: pad.add(const EdgeInsets.symmetric(vertical: 10)),
          child: const Divider(color: dividerSand, thickness: 1),
        );
        return _wrapWithHandle(context, index, dragIndex, content, hasField: false);
      case 'database':
        final id = block.props['databaseId'] as String?;
        final doc = id == null
            ? null
            : widget.databases.where((d) => d.id == id).firstOrNull;
        content = Padding(
          padding: pad.add(const EdgeInsets.symmetric(vertical: 6)),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openDatabasePicker(index),
            child: Container(
              decoration: BoxDecoration(
                color: mist,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: dividerSand),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                const Icon(Icons.table_chart_outlined, size: 18, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(doc?.label ?? 'Pick a database',
                      style: const TextStyle(fontSize: 14)),
                ),
                if (doc != null)
                  const Icon(Icons.open_in_new, size: 15, color: muted),
              ]),
            ),
          ),
        );
        return _wrapWithHandle(context, index, dragIndex, content, hasField: false);
      case 'code':
        content = Container(
          margin: pad.add(const EdgeInsets.symmetric(vertical: 6)),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          width: double.infinity,
          decoration: BoxDecoration(
            color: mist,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: _focusNodes[index],
                maxLines: null,
                style: _blockStyle(block),
                decoration: _decoration(block),
              ),
            ),
            if ((block.language ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 6),
                child: Text(block.language!,
                    style: const TextStyle(fontSize: 11, color: muted)),
              ),
          ]),
        );
        return _wrapWithHandle(context, index, dragIndex, content);
      case 'callout':
        content = Container(
          margin: pad.add(const EdgeInsets.symmetric(vertical: 6)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: focusBlue.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Icon(Icons.info_outline, size: 17, color: focusBlue),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: _focusNodes[index],
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: _blockStyle(block),
                decoration: _decoration(block),
              ),
            ),
          ]),
        );
        return _wrapWithHandle(context, index, dragIndex, content);
      case 'quote':
        content = Container(
          margin: pad.add(const EdgeInsets.symmetric(vertical: 2)),
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: ink, width: 2.5)),
          ),
          child: TextField(
            controller: controller,
            focusNode: _focusNodes[index],
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: _blockStyle(block),
            decoration: _decoration(block),
          ),
        );
        return _wrapWithHandle(context, index, dragIndex, content,
            leading: _leadingFor(block, index));
      default:
        content = TextField(
          controller: controller,
          focusNode: _focusNodes[index],
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: _blockStyle(block),
          decoration: _decoration(block),
        );
        return _wrapWithHandle(context, index, dragIndex, content,
            leading: _leadingFor(block, index), pad: pad);
    }
  }

  Widget _wrapWithHandle(
      BuildContext context, int index, int dragIndex, Widget content,
      {bool hasField = true, Widget? leading, EdgeInsets pad = EdgeInsets.zero}) {
    final block = _blocks[index];
    return Padding(
      padding: pad.add(const EdgeInsets.symmetric(vertical: 1)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ?leading,
        Expanded(
          child: hasField
              ? Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: (node, event) => _onKeyEvent(node, event, index),
                  child: content,
                )
              : content,
        ),
        _BlockActions(
          dragIndex: dragIndex,
          onIndent: (delta) => _indent(index, delta),
          onDuplicate: () {
            final copy = _blocks[index];
            _insertBlock(
                index + 1,
                Block(
                  id: _uuid.v4(),
                  type: copy.type,
                  text: copy.text,
                  indent: copy.indent,
                  checked: copy.checked,
                  language: copy.language,
                  props: copy.props,
                ));
            _scheduleSave();
          },
          onDelete: () {
            _removeBlock(index);
            _scheduleSave();
          },
          onTurnInto: (type) {
            setState(() {
              _blocks[index] = _blocks[index].copyWith(type: type);
              _syncRows();
            });
            _scheduleSave();
          },
          currentType: block.type,
        ),
      ]),
    );
  }

  Future<void> _openDatabasePicker(int index) async {
    final block = _blocks[index];
    final currentId = block.props['databaseId'] as String?;
    if (currentId != null) {
      widget.onOpenDatabase?.call(currentId);
      return;
    }
    final selected = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Embed a database',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (final doc in widget.databases.where((d) => !d.isDeleted))
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: Text(doc.label),
              onTap: () => Navigator.pop(context, {'id': doc.id}),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Create new database'),
            onTap: () => Navigator.pop(context, {'create': true}),
          ),
        ]),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected['create'] == true) {
      final created = await widget.onCreateDatabase?.call();
      if (created == null) return;
      setState(() {
        _blocks[index] =
            _blocks[index].copyWith(props: {'databaseId': created.id});
      });
      _scheduleSave();
      return;
    }
    setState(() {
      _blocks[index] =
          _blocks[index].copyWith(props: {'databaseId': selected['id'] as String});
    });
    _scheduleSave();
  }

  void _applyWikilink(String title) {
    final menu = _linkMenu;
    if (menu == null) return;
    final controller = _controllers[menu.blockIndex];
    if (controller == null) return;
    final text = controller.text;
    final caret = controller.selection.baseOffset;
    final end = caret < 0
        ? (menu.start + 2 + menu.query.length).clamp(0, text.length)
        : caret.clamp(0, text.length);
    final replacement = '[[$title]]';
    final kept = text.substring(0, menu.start) +
        replacement +
        text.substring(end);
    final newCaret = menu.start + replacement.length;
    controller.value = TextEditingValue(
      text: kept,
      selection: TextSelection.collapsed(offset: newCaret),
    );
    setState(() {
      _linkMenu = null;
      _blocks[menu.blockIndex] = _blocks[menu.blockIndex].copyWith(text: kept);
    });
    _scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    final visible = <int>[];
    for (var i = 0; i < _blocks.length; i++) {
      if (!_isHiddenByToggle(i)) visible.add(i);
    }
    return Stack(children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 40, 8, 96),
            children: [
              TextField(
                controller: _title,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _scheduleSave(),
                style: const TextStyle(fontSize: 30, height: 1.2,
                    fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.5),
                decoration: const InputDecoration(
                    hintText: 'Untitled', hintStyle: TextStyle(color: hintGray)),
              ),
              DraftSaveStatus(saver: _saver),
              const SizedBox(height: 18),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: visible.length,
                onReorderItem: (oldIndex, newIndex) {
                  final dragIndex = oldIndex.clamp(0, visible.length - 1);
                  _moveVisible(
                      visible[dragIndex],
                      newIndex >= visible.length
                          ? _blocks.length
                          : visible[newIndex.clamp(0, visible.length - 1)]);
                },
                proxyDecorator: (child, index, animation) => Material(
                  color: mist,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(6),
                  child: child,
                ),
                itemBuilder: (context, i) {
                  final index = visible[i];
                  return Container(
                    key: ValueKey(_blocks[index].id),
                    padding: const EdgeInsets.only(right: 4),
                    child: _blockRow(context, index, i),
                  );
                },
              ),
              GestureDetector(
                onTap: () {
                  final last = _blocks.length;
                  _insertBlock(last, Block(id: _uuid.v4()));
                  _scheduleSave();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _focusBlock(last);
                  });
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 44,
                  alignment: Alignment.centerLeft,
                  child: const Icon(Icons.add, size: 18, color: hintGray),
                ),
              ),
            ],
          ),
        ),
      ),
      if (_slashMenu != null || _linkMenu != null || _linkUnderCaret != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_linkMenu != null)
                WikilinkMenu(
                  query: _linkMenu!.query,
                  titles: widget.pageTitles,
                  onSelect: _applyWikilink,
                )
              else if (_slashMenu != null)
                SlashMenu(
                  query: _slashMenu!.query,
                  onSelect: _applySlash,
                  onDismiss: () => setState(() => _slashMenu = null),
                )
              else if (_linkUnderCaret != null)
                Material(
                  color: sheet,
                  borderRadius: BorderRadius.circular(8),
                  elevation: 6,
                  shadowColor: Colors.black26,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        widget.onOpenPageByTitle?.call(_linkUnderCaret!),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: dividerSand),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.open_in_new, size: 15, color: muted),
                        const SizedBox(width: 8),
                        Text('Open [[${_linkUnderCaret!}]]',
                            style: const TextStyle(fontSize: 13)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
    ]);
  }
}

/// Hover-visible drag handle and popup menu for a block row.
class _BlockActions extends StatefulWidget {
  const _BlockActions({
    required this.dragIndex,
    required this.onIndent,
    required this.onDuplicate,
    required this.onDelete,
    required this.onTurnInto,
    required this.currentType,
  });

  final int dragIndex;
  final ValueChanged<int> onIndent;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final ValueChanged<String> onTurnInto;
  final String currentType;

  @override
  State<_BlockActions> createState() => _BlockActionsState();
}

class _BlockActionsState extends State<_BlockActions> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final showControls = _hovering;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        width: 40,
        height: 34,
        // Drag handle plus menu button exceed 40px while hovering; scale down
        // instead of overflowing the fixed-width gutter.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(children: [
            if (showControls)
              ReorderableDragStartListener(
                index: widget.dragIndex,
                child: const Icon(Icons.drag_indicator,
                    size: 18, color: hintGray),
              ),
            PopupMenuButton<String>(
              tooltip: 'Block actions',
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: Icon(Icons.more_vert,
                  size: 18, color: showControls ? muted : hintGray),
              onSelected: (value) {
                if (value == 'duplicate') widget.onDuplicate();
                if (value == 'delete') widget.onDelete();
                if (value == 'indent') widget.onIndent(1);
                if (value == 'dedent') widget.onIndent(-1);
                if (value.startsWith('turn:')) {
                  widget.onTurnInto(value.substring(5));
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                    value: 'duplicate', child: Text('Duplicate')),
                const PopupMenuItem(value: 'indent', child: Text('Indent')),
                const PopupMenuItem(value: 'dedent', child: Text('Dedent')),
                const PopupMenuDivider(),
                for (final type in Block.mergeableTypes)
                  PopupMenuItem(
                    value: 'turn:$type',
                    child: Text('Turn into ${switchTypeLabel(type)}'),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: dangerRed)),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

String switchTypeLabel(String type) => switch (type) {
      'paragraph' => 'Text',
      'h1' => 'Heading 1',
      'h2' => 'Heading 2',
      'h3' => 'Heading 3',
      'todo' => 'To-do',
      'bullet' => 'Bulleted list',
      'number' => 'Numbered list',
      'quote' => 'Quote',
      'callout' => 'Callout',
      _ => type,
    };
