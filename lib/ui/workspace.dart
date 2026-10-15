import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../editor/block_editor.dart';
import '../knowledge/link_index.dart';
import '../store/database_doc.dart';
import '../store/markdown_vault.dart';
import '../store/page.dart';
import '../store/page_repository.dart';
import '../sync/sync_engine.dart';
import 'canvas_view.dart';
import 'database_view.dart';
import 'graph_view.dart';
import 'settings_dialog.dart';
import 'theme.dart';

enum _MainView { page, canvas, database, home, search, trash }

class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    required this.repository,
    required this.syncEngine,
    required this.vault,
  });

  final PageRepository repository;
  final SyncEngine syncEngine;
  final MarkdownVault? vault;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  final TextEditingController searchInput = TextEditingController();
  List<AnamnePage> pages = [];
  List<AnamnePage> deleted = [];
  List<DbDoc> databases = [];
  String? selectedId;
  String? selectedDatabaseId;
  String search = '';
  _MainView view = _MainView.home;
  bool loading = true;
  bool showBacklinks = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    widget.syncEngine.changes.addListener(_onSyncChanges);
    unawaited(widget.syncEngine.restoreFromSettings());
  }

  @override
  void dispose() {
    widget.syncEngine.changes.removeListener(_onSyncChanges);
    searchInput.dispose();
    super.dispose();
  }

  void _onSyncChanges() { unawaited(_refresh()); }

  void _clearSearch() {
    searchInput.clear();
    search = '';
  }

  Future<void> _refresh() async {
    final active = await widget.repository.all();
    final trash = await widget.repository.all(deleted: true);
    final docs = await widget.repository.allDatabases();
    if (!mounted) return;
    setState(() {
      pages = active;
      deleted = trash;
      databases = docs;
      if (selectedId != null && !active.any((p) => p.id == selectedId)) {
        selectedId = null;
        view = _MainView.home;
      }
      if (selectedDatabaseId != null &&
          !docs.any((d) => d.id == selectedDatabaseId)) {
        selectedDatabaseId = null;
        view = _MainView.home;
      }
      loading = false;
    });
  }

  AnamnePage? get current =>
      pages.where((p) => p.id == selectedId).firstOrNull;
  DbDoc? get currentDatabase =>
      databases.where((d) => d.id == selectedDatabaseId).firstOrNull;

  Future<void> _create({String? parentId, String type = 'page'}) async {
    final page = await widget.repository.create(parentId: parentId, type: type);
    if (!mounted) return;
    setState(() {
      selectedId = page.id;
      view = _MainView.page;
      _clearSearch();
    });
    await _refresh();
    unawaited(widget.vault?.writePage(page));
    unawaited(widget.syncEngine.runOnce());
    if (mounted && MediaQuery.sizeOf(context).width < 740) {
      Navigator.maybePop(context);
    }
  }

  Future<void> _savePage(AnamnePage page) async {
    await widget.repository.save(page);
    await _refresh();
    unawaited(widget.vault?.writePage(page));
    unawaited(widget.syncEngine.runOnce());
  }

  Future<void> _saveDatabase(DbDoc doc) async {
    await widget.repository.saveDatabase(doc);
    await _refresh();
    unawaited(widget.vault?.writeDatabase(doc));
    unawaited(widget.syncEngine.runOnce());
  }

  Future<DbDoc?> _createDatabaseForEmbed() async {
    final doc = await widget.repository.createDatabase();
    await _refresh();
    return doc;
  }

  Future<void> _createDatabase() async {
    final doc = await _createDatabaseForEmbed();
    if (!mounted || doc == null) return;
    setState(() {
      selectedDatabaseId = doc.id;
      view = _MainView.database;
    });
  }

  Future<void> _openPageByTitle(String title) async {
    final lower = title.toLowerCase();
    final match = pages
        .where((p) => p.label.toLowerCase() == lower)
        .firstOrNull;
    if (match != null) {
      setState(() {
        selectedId = match.id;
        view = _MainView.page;
        _clearSearch();
      });
      return;
    }
    final page = await widget.repository.create();
    final titled = page.copyWith(title: title);
    await widget.repository.save(titled);
    await _refresh();
    if (!mounted) return;
    setState(() {
      selectedId = titled.id;
      view = _MainView.page;
      _clearSearch();
    });
  }

  Future<void> _trash(String id) async {
    await widget.repository.trash(id);
    await _refresh();
    unawaited(widget.syncEngine.runOnce());
  }

  Future<void> _restore(String id) async {
    await widget.repository.restore(id);
    setState(() => view = _MainView.page);
    await _refresh();
    unawaited(widget.syncEngine.runOnce());
  }

  Future<void> _deleteForever(String id) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text('This page and its subpages cannot be recovered.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (accepted != true) return;
    await widget.repository.deleteForever(id);
    await _refresh();
    unawaited(widget.syncEngine.runOnce());
  }

  Future<void> _copyBackup() async {
    final json = await widget.repository.exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workspace JSON copied to clipboard')),
      );
    }
  }

  Future<void> _openGraph() async {
    if (MediaQuery.sizeOf(context).width < 740) Navigator.maybePop(context);
    await Navigator.push(context, MaterialPageRoute<void>(
      builder: (context) => GraphView(
        pages: pages,
        initialPageId: selectedId,
        onOpenPage: (page) {
          Navigator.pop(context);
          setState(() {
            selectedId = page.id;
            view = _MainView.page;
          });
        },
      ),
    ));
  }

  Future<void> _mirrorVault() async {
    final vault = widget.vault;
    if (vault == null) return;
    final written = await vault.mirrorAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(vault.lastError ?? 'Vault mirror wrote $written files'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 740;
    final side = _sidebar(narrow);
    return Scaffold(
      drawer: narrow ? Drawer(width: 300, child: side) : null,
      body: Row(children: [
        if (!narrow) SizedBox(width: 264, child: side),
        Expanded(child: Column(children: [
          _topBar(narrow),
          Expanded(child: loading
              ? const Center(child: Text('Opening workspace…'))
              : _mainArea(narrow)),
          if (narrow) _mobileSyncStrip(),
        ])),
      ]),
      floatingActionButton: narrow && view != _MainView.trash
          ? FloatingActionButton.small(
              onPressed: () => _create(),
              tooltip: 'New page',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _mainArea(bool narrow) {
    switch (view) {
      case _MainView.trash:
        return _trashView();
      case _MainView.search:
        return _searchView();
      case _MainView.database:
        final doc = currentDatabase;
        if (doc == null) return _emptyView();
        return DatabaseView(key: ValueKey(doc.id), doc: doc, onSave: _saveDatabase);
      case _MainView.canvas:
      case _MainView.page:
        final page = current;
        if (page == null) return _emptyView();
        final body = page.isCanvas
            ? CanvasView(key: ValueKey(page.id), page: page, onSave: _savePage)
            : BlockEditor(
                key: ValueKey(page.id),
                page: page,
                onSave: _savePage,
                pageTitles: pages.map((p) => p.label).toList(),
                databases: databases,
                onOpenDatabase: (id) => setState(() {
                  selectedDatabaseId = id;
                  view = _MainView.database;
                }),
                onOpenPageByTitle: _openPageByTitle,
                onCreateDatabase: _createDatabaseForEmbed,
              );
        if (narrow || !showBacklinks) return body;
        return Row(children: [
          Expanded(child: body),
          SizedBox(width: 260, child: _backlinksPanel(page)),
        ]);
      case _MainView.home:
        return _emptyView();
    }
  }

  Widget _backlinksPanel(AnamnePage page) {
    final index = LinkIndex(pages);
    final incoming = index.backlinksTo(page);
    final outgoing = index.outgoingTo(page);
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: dividerSand)),
      ),
      child: ListView(padding: const EdgeInsets.all(12), children: [
        const Padding(padding: EdgeInsets.only(left: 6, bottom: 6),
            child: Text('Backlinks', style: TextStyle(fontSize: 12,
                letterSpacing: 0.6, color: muted))),
        if (incoming.isEmpty)
          const Padding(padding: EdgeInsets.only(left: 6),
              child: Text('No pages link here yet', style: TextStyle(fontSize: 13, color: hintGray))),
        for (final source in incoming)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.link, size: 16, color: muted),
            title: Text(source.label, style: const TextStyle(fontSize: 13.5)),
            onTap: () => setState(() {
              selectedId = source.id;
              view = _MainView.page;
            }),
          ),
        const Padding(padding: EdgeInsets.fromLTRB(6, 16, 0, 6),
            child: Text('Outgoing links', style: TextStyle(fontSize: 12,
                letterSpacing: 0.6, color: muted))),
        if (outgoing.isEmpty)
          const Padding(padding: EdgeInsets.only(left: 6),
              child: Text('No [[links]] on this page yet',
                  style: TextStyle(fontSize: 13, color: hintGray))),
        for (final target in outgoing)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.link_outlined, size: 16, color: muted),
            title: Text(target.label, style: const TextStyle(fontSize: 13.5)),
            onTap: () => setState(() {
              selectedId = target.id;
              view = _MainView.page;
            }),
          ),
      ]),
    );
  }

  Widget _topBar(bool narrow) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE9E9E7)))),
    child: Row(children: [
      if (narrow) Builder(builder: (context) => IconButton(
        tooltip: 'Open navigation',
        onPressed: () => Scaffold.of(context).openDrawer(),
        icon: const Icon(Icons.menu, size: 20),
      )),
      Expanded(child: Text(_topBarTitle(),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
      ValueListenableBuilder<SyncStatus>(
        valueListenable: widget.syncEngine.status,
        builder: (context, status, _) {
          final icon = switch (status.phase) {
            SyncPhase.disabled => Icons.cloud_off_outlined,
            SyncPhase.offline => Icons.cloud_off_outlined,
            SyncPhase.syncing => Icons.sync,
            SyncPhase.idle => Icons.cloud_done_outlined,
            SyncPhase.error => Icons.error_outline,
          };
          final color = switch (status.phase) {
            SyncPhase.error => dangerRed,
            SyncPhase.offline => warningAmber,
            SyncPhase.disabled => muted,
            _ => muted,
          };
          return Tooltip(
            message: status.label,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _openSettings(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 5),
                  Text(status.label,
                      style: const TextStyle(fontSize: 12, color: muted)),
                ]),
              ),
            ),
          );
        },
      ),
      if (view == _MainView.page && current != null && !current!.isCanvas)
        IconButton(
          tooltip: 'Toggle backlinks panel',
          isSelected: showBacklinks,
          onPressed: () => setState(() => showBacklinks = !showBacklinks),
          icon: const Icon(Icons.link_outlined, size: 19),
        ),
      if (view == _MainView.page && current != null)
        _pageMenu(),
    ]),
  );

  String _topBarTitle() {
    switch (view) {
      case _MainView.trash:
        return 'Trash';
      case _MainView.search:
        return 'Search';
      case _MainView.database:
        return currentDatabase?.label ?? 'Home';
      case _MainView.canvas:
      case _MainView.page:
        return current?.label ?? 'Home';
      case _MainView.home:
        return 'Home';
    }
  }

  Widget _pageMenu() => PopupMenuButton<String>(
    tooltip: 'Page actions',
    onSelected: (value) async {
      final page = current!;
      if (value == 'subpage') await _create(parentId: page.id);
      if (value == 'canvas') await _create(parentId: page.id, type: 'canvas');
      if (value == 'trash') await _trash(page.id);
      if (value == 'markdown') {
        await Clipboard.setData(ClipboardData(text: page.body));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Markdown copied to clipboard')));
        }
      }
    },
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'subpage', child: Text('New subpage')),
      PopupMenuItem(value: 'canvas', child: Text('New canvas inside')),
      PopupMenuItem(value: 'markdown', child: Text('Copy Markdown')),
      PopupMenuItem(value: 'trash', child: Text('Move to trash')),
    ],
  );

  Widget _sidebar(bool narrow) {
    final roots = pages.where((p) => p.parentId == null ||
        !pages.any((parent) => parent.id == p.parentId)).toList();
    return Container(
      color: mist,
      child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 12, 12, 12), child: Row(children: [
          SvgPicture.asset('assets/brand/anamne-icon.svg', width: 27, height: 27),
          const SizedBox(width: 9),
          const Expanded(child: Text('Anamne',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          IconButton(tooltip: 'New page', onPressed: () => _create(),
            icon: const Icon(Icons.add, size: 20)),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: searchInput,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Search pages', isDense: true, filled: true,
                fillColor: paper, contentPadding: EdgeInsets.symmetric(vertical: 11)),
            onChanged: (value) => setState(() {
              search = value.trim();
              view = search.isEmpty ? _MainView.home : _MainView.search;
            }),
          )),
        const SizedBox(height: 12),
        _sideAction(Icons.home_outlined, 'Home', () => setState(() {
          view = _MainView.home; _clearSearch();
        })),
        _sideAction(Icons.hub_outlined, 'Graph view', _openGraph),
        const Padding(padding: EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Text('PRIVATE', style: TextStyle(fontSize: 11,
                letterSpacing: 0.7, color: muted))),
        Expanded(child: ListView(children: [
          for (final root in roots) _treeNode(root, 0, <String>{}),
          const Padding(padding: EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Text('DATABASES', style: TextStyle(fontSize: 11,
                  letterSpacing: 0.7, color: muted))),
          for (final doc in databases.where((d) => !d.isDeleted))
            Padding(padding: EdgeInsets.zero, child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              selected: view == _MainView.database &&
                  selectedDatabaseId == doc.id,
              selectedTileColor: const Color(0xFFE7E7E4),
              leading: const Icon(Icons.table_chart_outlined, size: 18, color: muted),
              title: Text(doc.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14)),
              onTap: () {
                setState(() {
                  selectedDatabaseId = doc.id;
                  view = _MainView.database;
                  _clearSearch();
                });
                if (MediaQuery.sizeOf(context).width < 740) {
                  Navigator.maybePop(context);
                }
              },
            )),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.add, size: 18, color: muted),
            title: const Text('New database', style: TextStyle(fontSize: 13.5)),
            onTap: () {
              _createDatabase();
              if (MediaQuery.sizeOf(context).width < 740) {
                Navigator.maybePop(context);
              }
            },
          ),
        ])),
        _sideAction(Icons.delete_outline, 'Trash', () => setState(() {
          view = _MainView.trash; _clearSearch();
        })),
        _sideAction(Icons.archive_outlined, 'Copy workspace backup', _copyBackup),
        if (widget.vault != null)
          _sideAction(Icons.folder_outlined, 'Mirror markdown vault', _mirrorVault),
        _sideAction(Icons.settings_outlined, 'Settings', _openSettings),
        const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Text('Powered by ©Invokeil Tech',
              style: TextStyle(fontSize: 11, color: muted))),
      ])),
    );
  }

  Widget _sideAction(IconData icon, String label, VoidCallback action) =>
      ListTile(dense: true, visualDensity: VisualDensity.compact,
        leading: Icon(icon, size: 19, color: muted),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        onTap: action);

  Widget _treeNode(AnamnePage page, int depth, Set<String> ancestors) {
    if (ancestors.contains(page.id)) return const SizedBox.shrink();
    final children = pages.where((p) => p.parentId == page.id).toList();
    final next = {...ancestors, page.id};
    return Column(children: [
      Padding(padding: EdgeInsets.only(left: (depth * 12).toDouble()), child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        selected: selectedId == page.id &&
            (view == _MainView.page || view == _MainView.canvas),
        selectedTileColor: const Color(0xFFE7E7E4),
        leading: Icon(page.isCanvas ? Icons.dashboard_outlined : Icons.description_outlined,
            size: 18, color: muted),
        title: Text(page.label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14)),
        onTap: () {
          setState(() {
            selectedId = page.id;
            view = page.isCanvas ? _MainView.canvas : _MainView.page;
            _clearSearch();
          });
          if (MediaQuery.sizeOf(context).width < 740) Navigator.maybePop(context);
        },
      )),
      for (final child in children) _treeNode(child, depth + 1, next),
    ]);
  }

  Widget _mobileSyncStrip() => ValueListenableBuilder<SyncStatus>(
    valueListenable: widget.syncEngine.status,
    builder: (context, status, _) => status.phase == SyncPhase.disabled
        ? const SizedBox.shrink()
        : Container(
            height: 24,
            alignment: Alignment.center,
            color: mist,
            child: Text(status.label,
                style: const TextStyle(fontSize: 11, color: muted)),
          ),
  );

  Widget _emptyView() => Center(child: Column(mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.article_outlined, size: 40, color: muted),
      const SizedBox(height: 14),
      Text(pages.isEmpty ? 'Your workspace starts here' : 'Choose a page',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        TextButton.icon(onPressed: () => _create(),
            icon: const Icon(Icons.add), label: const Text('New page')),
        TextButton.icon(onPressed: () => _create(type: 'canvas'),
            icon: const Icon(Icons.dashboard_outlined), label: const Text('New canvas')),
      ]),
    ],
  ));

  Widget _searchView() {
    final term = search.toLowerCase();
    final matches = pages.where((p) => p.title.toLowerCase().contains(term) ||
        p.body.toLowerCase().contains(term)).toList();
    return ListView(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
        child: Text('Search results · ${matches.length}',
            style: const TextStyle(color: muted, fontSize: 13))),
      for (final page in matches) ListTile(
        leading: Icon(page.isCanvas ? Icons.dashboard_outlined : Icons.description_outlined,
            size: 20),
        title: Text(page.label),
        subtitle: Text(page.body.replaceAll('\n', ' '), maxLines: 1,
            overflow: TextOverflow.ellipsis),
        onTap: () => setState(() {
          selectedId = page.id;
          view = page.isCanvas ? _MainView.canvas : _MainView.page;
          _clearSearch();
        }),
      ),
    ]);
  }

  Widget _trashView() => ListView(children: [
    const Padding(padding: EdgeInsets.fromLTRB(20, 26, 20, 10),
      child: Text('Pages in trash', style: TextStyle(fontSize: 21,
          fontWeight: FontWeight.w600))),
    if (deleted.isEmpty) const ListTile(title: Text('Trash is empty')),
    for (final page in deleted) ListTile(
      title: Text(page.label),
      subtitle: Text('Deleted ${page.deletedAt?.toLocal().toString().split('.').first ?? ''}'),
      trailing: Wrap(spacing: 4, children: [
        IconButton(tooltip: 'Restore', onPressed: () => _restore(page.id),
            icon: const Icon(Icons.restore)),
        IconButton(tooltip: 'Delete forever', onPressed: () => _deleteForever(page.id),
            icon: const Icon(Icons.delete_forever_outlined)),
      ]),
    ),
  ]);

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(
        repository: widget.repository,
        syncEngine: widget.syncEngine,
        vault: widget.vault,
      ),
    );
    await _refresh();
  }
}
