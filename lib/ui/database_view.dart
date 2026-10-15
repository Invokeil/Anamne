import 'dart:async';

import 'package:flutter/material.dart';

import '../store/database_doc.dart';
import '../store/draft_saver.dart';
import 'theme.dart';

/// Notion-lite structured database views: a primary table plus a board
/// grouped by a select property, with bounded sort/filter support.
class DatabaseView extends StatefulWidget {
  const DatabaseView({
    super.key,
    required this.doc,
    required this.onSave,
  });

  final DbDoc doc;
  final Future<void> Function(DbDoc) onSave;

  @override
  State<DatabaseView> createState() => _DatabaseViewState();
}

class _DatabaseViewState extends State<DatabaseView> with WidgetsBindingObserver {
  late TextEditingController _title;
  late DbDoc _doc;
  late final DraftSaver<DbDoc> _saver;
  bool _boardMode = false;
  String? _sortBy;
  bool _sortAscending = true;
  String? _filterProp;
  Object? _filterValue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _saver = DraftSaver((doc) => widget.onSave(doc));
    _doc = widget.doc;
    _title = TextEditingController(text: widget.doc.title);
  }

  @override
  void didUpdateWidget(covariant DatabaseView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc.id != widget.doc.id || (!_saver.hasPending && !_saver.isSaving)) {
      _doc = widget.doc;
      _title.text = widget.doc.title;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _saver.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_saver.flush());
  }

  void _scheduleSave(DbDoc doc) {
    _doc = doc;
    _saver.schedule(doc);
  }

  List<DbRecord> get _visibleRecords {
    var records = _doc.records;
    if (_filterProp != null) {
      records = records.where((r) {
        final value = r.values[_filterProp];
        if (_filterValue == null) return value == null || value == false;
        if (_filterValue is List) {
          return value is List &&
              (value as List<Object?>).any((v) => (_filterValue as List).contains(v));
        }
        return value == _filterValue;
      }).toList();
    }
    if (_sortBy != null) {
      final prop = _doc.schema.where((p) => p.id == _sortBy).firstOrNull;
      int compare(DbRecord a, DbRecord b) {
        final av = a.values[_sortBy!];
        final bv = b.values[_sortBy!];
        if (av == null && bv == null) return 0;
        if (av == null) return 1;
        if (bv == null) return -1;
        if (prop?.type == 'number') {
          return ((av as num).toDouble()).compareTo((bv as num).toDouble());
        }
        return av.toString().toLowerCase().compareTo(bv.toString().toLowerCase());
      }
      records = [...records]..sort(compare);
      if (!_sortAscending) records = records.reversed.toList();
    }
    return records;
  }

  Future<void> _addProperty() async {
    final created = await showDialog<DbProp>(
      context: context,
      builder: (context) {
        var name = '';
        var type = 'text';
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Add property'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Property name'),
                onChanged: (v) => name = v,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('Text')),
                  DropdownMenuItem(value: 'number', child: Text('Number')),
                  DropdownMenuItem(value: 'select', child: Text('Select')),
                  DropdownMenuItem(value: 'multiSelect', child: Text('Multi-select')),
                  DropdownMenuItem(value: 'checkbox', child: Text('Checkbox')),
                  DropdownMenuItem(value: 'date', child: Text('Date')),
                ],
                onChanged: (v) => setState(() => type = v ?? 'text'),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: name.trim().isEmpty
                    ? null
                    : () => Navigator.pop(context, DbProp(
                        id: 'p${DateTime.now().millisecondsSinceEpoch}',
                        name: name.trim(), type: type)),
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );
    if (created == null) return;
    _scheduleSave(_doc.copyWith(schema: [..._doc.schema, created]));
    setState(() {});
  }

  Future<void> _editCell(DbRecord record, DbProp prop) async {
    final current = record.values[prop.id];
    switch (prop.type) {
      case 'checkbox':
        _commitValue(record, prop, !(current == true));
        return;
      case 'number':
        final controller = TextEditingController(text: current?.toString() ?? '');
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(prop.name),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Number'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
            ],
          ),
        );
        if (result == null) return;
        final parsed = num.tryParse(result.replaceAll(',', ''));
        _commitValue(record, prop, parsed);
        return;
      case 'select':
        final options = prop.options;
        final chosen = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(child: ListView(shrinkWrap: true, children: [
            for (final option in options)
              ListTile(title: Text(option), onTap: () => Navigator.pop(context, option)),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text('New option for ${prop.name}'),
              onTap: () async {
                final controller = TextEditingController();
                final created = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('New ${prop.name} option'),
                    content: TextField(controller: controller, autofocus: true),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Add')),
                    ],
                  ),
                );
                if (created != null && created.trim().isNotEmpty && context.mounted) {
                  Navigator.pop(context, created.trim());
                }
              },
            ),
          ])),
        );
        if (chosen == null) return;
        if (!options.contains(chosen)) {
          final updated = prop.copyWith(options: [...options, chosen]);
          _scheduleSave(_doc.copyWith(schema: _doc.schema
              .map((p) => p.id == prop.id ? updated : p).toList()));
        }
        _commitValue(record, prop, chosen);
        return;
      case 'multiSelect':
        final options = prop.options;
        final chosenList = (current as List<Object?>?)?.cast<String>() ?? <String>[];
        final result = await showModalBottomSheet<List<String>>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(child: ListView(shrinkWrap: true, children: [
              for (final option in options)
                CheckboxListTile(
                  value: chosenList.contains(option),
                  title: Text(option),
                  onChanged: (checked) => setSheetState(() {
                    checked == true
                        ? chosenList.add(option)
                        : chosenList.remove(option);
                  }),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, chosenList),
                  child: const Text('Done'),
                ),
              ),
            ])),
          ),
        );
        if (result == null) return;
        _commitValue(record, prop, result);
        return;
      case 'date':
        final initial = DateTime.tryParse(current?.toString() ?? '') ?? DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked == null) return;
        _commitValue(record, prop,
            '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
        return;
      default:
        final controller = TextEditingController(text: current?.toString() ?? '');
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(prop.name),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: null,
              decoration: const InputDecoration(hintText: 'Text'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
            ],
          ),
        );
        if (result == null) return;
        _commitValue(record, prop, result.trim().isEmpty ? null : result);
    }
  }

  void _commitValue(DbRecord record, DbProp prop, Object? value) {
    final updatedRecords = _doc.records.map((r) {
      if (r.id != record.id) return r;
      final values = {...r.values};
      if (value == null) {
        values.remove(prop.id);
      } else {
        values[prop.id] = value;
      }
      return DbRecord(id: r.id, values: values);
    }).toList();
    _scheduleSave(_doc.copyWith(records: updatedRecords));
    setState(() {});
  }

  void _addRecord({String? selectProp, String? group}) {
    final values = <String, Object?>{};
    if (selectProp != null && group != null) values[selectProp] = group;
    final record = DbRecord(
      id: 'r${DateTime.now().microsecondsSinceEpoch}',
      values: values,
    );
    _scheduleSave(_doc.copyWith(records: [..._doc.records, record]));
    setState(() {});
  }

  Future<void> _editRecordSheet(DbRecord record) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Edit record', style: TextStyle(fontWeight: FontWeight.w600))),
              IconButton(
                tooltip: 'Delete record',
                icon: const Icon(Icons.delete_outline, size: 19, color: dangerRed),
                onPressed: () {
                  Navigator.pop(context);
                  _scheduleSave(_doc.copyWith(records:
                      _doc.records.where((r) => r.id != record.id).toList()));
                  setState(() {});
                },
              ),
            ]),
            const SizedBox(height: 6),
            for (final prop in _doc.schema)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(prop.name, style: const TextStyle(fontSize: 13, color: muted)),
                subtitle: Text(_displayValue(record.values[prop.id], prop),
                    style: const TextStyle(fontSize: 14)),
                trailing: prop.type == 'checkbox'
                    ? Checkbox(
                        value: record.values[prop.id] == true,
                        onChanged: (_) {
                          Navigator.pop(context);
                          _editCell(record, prop);
                        })
                    : const Icon(Icons.edit_outlined, size: 16, color: hintGray),
                onTap: () {
                  Navigator.pop(context);
                  _editCell(record, prop);
                },
              ),
          ]),
        ),
      ),
    );
    setState(() {});
  }

  String _displayValue(Object? value, DbProp prop) {
    if (value == null) return 'Empty';
    switch (prop.type) {
      case 'checkbox':
        return value == true ? 'Done' : 'Not done';
      case 'multiSelect':
        return (value as List<Object?>).cast<String>().join(', ');
      default:
        return value.toString();
    }
  }

  Widget _cell(DbRecord record, DbProp prop) {
    final value = record.values[prop.id];
    final text = _displayValue(value, prop);
    final isEmpty = value == null;
    return InkWell(
      onTap: () => _editCell(record, prop),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Text(
          prop.type == 'checkbox'
              ? (value == true ? '☑' : '☐')
              : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13.5,
              color: isEmpty ? hintGray : ink),
        ),
      ),
    );
  }

  Widget _table() {
    final schema = _doc.schema;
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: SingleChildScrollView(
            child: DataTable(
              headingRowHeight: 42,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 48,
              columns: [
                for (final prop in schema)
                  DataColumn(
                    label: PopupMenuButton<String>(
                      tooltip: 'Property options',
                      padding: EdgeInsets.zero,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(child: Text(prop.name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        const SizedBox(width: 4),
                        Icon(_sortBy == prop.id
                            ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                            : Icons.unfold_more,
                            size: 13, color: muted),
                      ]),
                      onSelected: (value) {
                        if (value == 'sort') {
                          setState(() {
                            if (_sortBy == prop.id && _sortAscending) {
                              _sortAscending = false;
                            } else if (_sortBy == prop.id) {
                              _sortBy = null;
                              _sortAscending = true;
                            } else {
                              _sortBy = prop.id;
                              _sortAscending = true;
                            }
                          });
                        }
                        if (value == 'filter') {
                          setState(() {
                            _filterProp = prop.id;
                            _filterValue = null;
                          });
                        }
                        if (value == 'clearFilter') {
                          setState(() => _filterProp = null);
                        }
                        if (value == 'delete') {
                          _scheduleSave(_doc.copyWith(schema:
                              _doc.schema.where((p) => p.id != prop.id).toList()));
                          setState(() {});
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'sort', child: Text('Sort by this')),
                        if (_filterProp != prop.id)
                          const PopupMenuItem(value: 'filter', child: Text('Show empty only'))
                        else
                          const PopupMenuItem(value: 'clearFilter', child: Text('Clear filter')),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete property', style: TextStyle(color: dangerRed)),
                        ),
                      ],
                    ),
                  ),
                const DataColumn(label: SizedBox(width: 40)),
              ],
              rows: [
                for (final record in _visibleRecords)
                  DataRow(cells: [
                    for (final prop in schema) DataCell(_cell(record, prop)),
                    DataCell(PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 16, color: hintGray),
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit record')),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete record',
                              style: TextStyle(color: dangerRed)),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'edit') _editRecordSheet(record);
                        if (value == 'delete') {
                          _scheduleSave(_doc.copyWith(records:
                              _doc.records.where((r) => r.id != record.id).toList()));
                          setState(() {});
                        }
                      },
                    )),
                  ]),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _board() {
    final groupProp = _doc.schema
        .where((p) => p.type == 'select')
        .firstOrNull;
    if (groupProp == null) {
      return const Center(child: Text(
          'Board view needs a Select property. Add one from the table view.',
          style: TextStyle(color: muted)));
    }
    final groups = groupProp.options;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final group in groups)
          DragTarget<String>(
            key: ValueKey(group),
            onAcceptWithDetails: (details) {
              final recordId = details.data;
              final updated = _doc.records.map((r) {
                if (r.id != recordId) return r;
                return DbRecord(id: r.id, values: {...r.values, groupProp.id: group});
              }).toList();
              _scheduleSave(_doc.copyWith(records: updated));
              setState(() {});
            },
            builder: (context, candidates, rejected) => Container(
              width: 250,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: candidates.isNotEmpty ? mist : paper,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(group,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add, size: 16),
                    onPressed: () => _addRecord(selectProp: groupProp.id, group: group),
                  ),
                ]),
                for (final record in _visibleRecords
                    .where((r) => r.values[groupProp.id] == group))
                  LongPressDraggable<String>(
                    data: record.id,
                    feedback: Material(
                      color: Colors.transparent,
                      child: _boardCard(record),
                    ),
                    child: _boardCard(record),
                  ),
              ]),
            ),
          ),
        DragTarget<String>(
          onAcceptWithDetails: (details) {
            final recordId = details.data;
            final updated = _doc.records.map((r) {
              if (r.id != recordId) return r;
              final values = {...r.values};
              values.remove(groupProp.id);
              return DbRecord(id: r.id, values: values);
            }).toList();
            _scheduleSave(_doc.copyWith(records: updated));
            setState(() {});
          },
          builder: (context, candidates, _) => Container(
            width: 220,
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: candidates.isNotEmpty ? mist : paper,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('No ${groupProp.name}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: muted))),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add, size: 16),
                  onPressed: _addRecord,
                ),
              ]),
              for (final record in _visibleRecords
                  .where((r) => r.values[groupProp.id] == null ||
                      !groups.contains(r.values[groupProp.id])))
                LongPressDraggable<String>(
                  data: record.id,
                  feedback: Material(
                    color: Colors.transparent,
                    child: _boardCard(record),
                  ),
                  child: _boardCard(record),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _boardCard(DbRecord record) {
    final titleProp = _doc.schema.where((p) => p.type == 'text').firstOrNull;
    final title = titleProp == null
        ? record.id
        : record.values[titleProp.id]?.toString() ?? 'Untitled';
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _editRecordSheet(record),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: sheet,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: dividerSand),
        ),
        child: Text(title, style: const TextStyle(fontSize: 13.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(left: 16, top: 8),
        child: DraftSaveStatus(saver: _saver)),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        child: Row(children: [
          Expanded(child: TextField(
            controller: _title,
            onChanged: (v) => _scheduleSave(_doc.copyWith(title: v)),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: ink),
            decoration: const InputDecoration(hintText: 'Untitled database',
                hintStyle: TextStyle(color: hintGray)),
          )),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.table_rows_outlined, size: 17), label: Text('Table')),
              ButtonSegment(value: true, icon: Icon(Icons.view_column_outlined, size: 17), label: Text('Board')),
            ],
            selected: {_boardMode},
            onSelectionChanged: (selection) => setState(() => _boardMode = selection.first),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
        child: Wrap(spacing: 8, children: [
          TextButton.icon(
            onPressed: _addProperty,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Property'),
          ),
          TextButton.icon(
            onPressed: _addRecord,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Record'),
          ),
          if (_filterProp != null)
            Chip(
              label: Text('Filtered: ${_doc.schema
                  .where((p) => p.id == _filterProp)
                  .firstOrNull?.name ?? _filterProp}',
                  style: const TextStyle(fontSize: 12)),
              onDeleted: () => setState(() => _filterProp = null),
            ),
          if (_sortBy != null)
            Chip(
              label: Text('Sorted by ${_doc.schema
                  .where((p) => p.id == _sortBy)
                  .firstOrNull?.name ?? ''}',
                  style: const TextStyle(fontSize: 12)),
              onDeleted: () => setState(() => _sortBy = null),
            ),
        ]),
      ),
      Expanded(child: _boardMode ? _board() : _table()),
    ]);
  }
}
