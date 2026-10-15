import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'store/page.dart';
import 'store/page_repository.dart';

const _paper = Color(0xFFFBFBFA);
const _mist = Color(0xFFF1F1EF);
const _ink = Color(0xFF37352F);
const _muted = Color(0xFF787774);
const _blue = Color(0xFF2F6FEB);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AnamneApp(repository: PageRepository.open()));
}

class AnamneApp extends StatelessWidget {
  const AnamneApp({super.key, required this.repository});
  final Future<PageRepository> repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Anamne',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _paper,
      colorScheme: ColorScheme.fromSeed(seedColor: _blue, surface: _paper),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(bodyMedium: TextStyle(color: _ink, fontSize: 15)),
      dividerColor: const Color(0xFFE9E9E7),
      inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none),
    ),
    home: FutureBuilder<PageRepository>(
      future: repository,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText('Could not open local workspace: ${snapshot.error}'),
          )));
        }
        if (!snapshot.hasData) return const _BrandLoading();
        return Workspace(repository: snapshot.data!);
      },
    ),
  );
}

class _BrandLoading extends StatefulWidget {
  const _BrandLoading();
  @override
  State<_BrandLoading> createState() => _BrandLoadingState();
}

class _BrandLoadingState extends State<_BrandLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(animation: controller, builder: (context, _) {
          final reduceMotion = MediaQuery.disableAnimationsOf(context);
          final progress = reduceMotion ? 0.5 : controller.value;
          final breathing = 1 - (2 * progress - 1).abs();
          const size = 92.0;
          const dot = size * 52 / 512;
          return SizedBox(width: size, height: size, child: Stack(children: [
            Positioned.fill(child: Opacity(
              opacity: reduceMotion ? 1 : 0.55 + 0.45 * breathing,
              child: Transform.scale(scale: 0.98 + 0.02 * breathing,
                child: SvgPicture.asset('assets/brand/anamne-loading-mark.svg',
                  semanticsLabel: 'Anamne loading')),
            )),
            Positioned(left: size / 2 - dot / 2, top: size * 356 / 512 - dot / 2,
              width: dot, height: dot, child: Stack(alignment: Alignment.center, children: [
                if (!reduceMotion) Transform.scale(scale: 1 + 2.2 * progress,
                  child: Container(decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: _ink.withValues(alpha: 0.6 * (1 - progress))))),
                ),
                Transform.scale(scale: reduceMotion ? 1 : 1 + 0.25 * breathing,
                  child: const DecoratedBox(decoration: BoxDecoration(color: Color(0xFF0B0B0F),
                    shape: BoxShape.circle), child: SizedBox.expand())),
              ])),
          ]));
        }),
        const SizedBox(height: 12),
        const Text('Anamne', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      ],
    )),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.repository});
  final PageRepository repository;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  final TextEditingController searchInput = TextEditingController();
  List<AnamnePage> pages = [];
  List<AnamnePage> deleted = [];
  String? selectedId;
  String search = '';
  bool showTrash = false;
  bool loading = true;

  @override
  void dispose() {
    searchInput.dispose();
    super.dispose();
  }

  void _clearSearch() {
    searchInput.clear();
    search = '';
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final active = await widget.repository.all();
    final trash = await widget.repository.all(deleted: true);
    if (!mounted) return;
    setState(() {
      pages = active;
      deleted = trash;
      if (selectedId != null && !active.any((p) => p.id == selectedId)) {
        selectedId = null;
      }
      loading = false;
    });
  }

  Future<void> _create({String? parentId}) async {
    final page = await widget.repository.create(parentId: parentId);
    if (!mounted) return;
    setState(() {
      selectedId = page.id;
      showTrash = false;
      _clearSearch();
    });
    await _refresh();
    if (mounted && MediaQuery.sizeOf(context).width < 740) {
      Navigator.maybePop(context);
    }
  }

  Future<void> _save(AnamnePage page) async {
    await widget.repository.save(page);
    await _refresh();
  }

  Future<void> _trash(String id) async {
    await widget.repository.trash(id);
    await _refresh();
  }

  Future<void> _restore(String id) async {
    await widget.repository.restore(id);
    setState(() => showTrash = false);
    await _refresh();
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
  }

  Future<void> _copyBackup() async {
    final json = await widget.repository.exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Workspace JSON copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 740;
    final current = pages.where((p) => p.id == selectedId).firstOrNull;
    final side = _sidebar(narrow);
    return Scaffold(
      drawer: narrow ? Drawer(width: 296, child: side) : null,
      body: Row(children: [
        if (!narrow) SizedBox(width: 264, child: side),
        Expanded(child: Column(children: [
          _topBar(narrow, current),
          Expanded(child: loading
              ? const Center(child: Text('Opening workspace…'))
              : showTrash
                  ? _trashView()
                  : search.isNotEmpty
                      ? _searchView()
                      : current == null
                          ? _emptyView()
                          : PageEditor(key: ValueKey(current.id), page: current,
                              onSave: _save, onNewChild: () => _create(parentId: current.id))),
        ])),
      ]),
      floatingActionButton: narrow && !showTrash
          ? FloatingActionButton.small(
              onPressed: () => _create(),
              tooltip: 'New page',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _topBar(bool narrow, AnamnePage? current) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9E9E7)))),
    child: Row(children: [
      if (narrow) Builder(builder: (context) => IconButton(
        tooltip: 'Open navigation',
        onPressed: () => Scaffold.of(context).openDrawer(),
        icon: const Icon(Icons.menu, size: 20),
      )),
      Expanded(child: Text(showTrash ? 'Trash' : search.isNotEmpty ? 'Search' : current?.label ?? 'Home',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
      const Tooltip(message: 'Saved locally • sync coming later',
        child: Row(children: [Icon(Icons.cloud_off_outlined, size: 17, color: _muted),
          SizedBox(width: 5), Text('Local', style: TextStyle(fontSize: 12, color: _muted))])),
      if (current != null) PopupMenuButton<String>(
        tooltip: 'Page actions',
        onSelected: (value) {
          if (value == 'subpage') _create(parentId: current.id);
          if (value == 'trash') _trash(current.id);
          if (value == 'markdown') {
            Clipboard.setData(ClipboardData(text: '# ${current.label}\n\n${current.body}\n'));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Markdown copied to clipboard')));
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'subpage', child: Text('New subpage')),
          PopupMenuItem(value: 'markdown', child: Text('Copy Markdown')),
          PopupMenuItem(value: 'trash', child: Text('Move to trash')),
        ],
      ),
    ]),
  );

  Widget _sidebar(bool narrow) {
    final roots = pages.where((p) => p.parentId == null ||
        !pages.any((parent) => parent.id == p.parentId)).toList();
    return Container(
      color: _mist,
      child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 12, 12, 12), child: Row(children: [
          SvgPicture.asset('assets/brand/anamne-icon.svg', width: 27, height: 27),
          const SizedBox(width: 9),
          const Expanded(child: Text('Anamne', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          IconButton(tooltip: 'New page', onPressed: () => _create(),
            icon: const Icon(Icons.add, size: 20)),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: searchInput,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Search pages', isDense: true, filled: true,
                fillColor: _paper, contentPadding: EdgeInsets.symmetric(vertical: 11)),
            onChanged: (value) => setState(() { search = value.trim(); showTrash = false; }),
          )),
        const SizedBox(height: 14),
        _sideAction(Icons.home_outlined, 'Home', () => setState(() {
          selectedId = null; showTrash = false; _clearSearch();
        })),
        const Padding(padding: EdgeInsets.fromLTRB(16, 18, 8, 8),
            child: Text('PRIVATE', style: TextStyle(fontSize: 11, letterSpacing: 0.7, color: _muted))),
        Expanded(child: ListView(children: roots.map((root) => _treeNode(root, 0, <String>{})).toList())),
        _sideAction(Icons.delete_outline, 'Trash', () => setState(() {
          showTrash = true; _clearSearch();
        })),
        _sideAction(Icons.archive_outlined, 'Copy workspace backup', _copyBackup),
        const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Text('Powered by ©Invokeil Tech',
              style: TextStyle(fontSize: 11, color: _muted))),
      ])),
    );
  }

  Widget _sideAction(IconData icon, String label, VoidCallback action) =>
      ListTile(dense: true, visualDensity: VisualDensity.compact,
        leading: Icon(icon, size: 19, color: _muted),
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
        selected: selectedId == page.id && !showTrash,
        selectedTileColor: const Color(0xFFE7E7E4),
        leading: const Icon(Icons.description_outlined, size: 18, color: _muted),
        title: Text(page.label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14)),
        onTap: () {
          setState(() { selectedId = page.id; showTrash = false; _clearSearch(); });
          if (MediaQuery.sizeOf(context).width < 740) Navigator.maybePop(context);
        },
      )),
      for (final child in children) _treeNode(child, depth + 1, next),
    ]);
  }

  Widget _emptyView() => Center(child: Column(mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.article_outlined, size: 40, color: _muted),
      const SizedBox(height: 14),
      Text(pages.isEmpty ? 'Your workspace starts here' : 'Choose a page',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      TextButton.icon(onPressed: () => _create(),
          icon: const Icon(Icons.add), label: const Text('New page')),
    ],
  ));

  Widget _searchView() {
    final term = search.toLowerCase();
    final matches = pages.where((p) => p.title.toLowerCase().contains(term) ||
        p.body.toLowerCase().contains(term)).toList();
    return ListView(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
        child: Text('Search results · ${matches.length}',
            style: const TextStyle(color: _muted, fontSize: 13))),
      for (final page in matches) ListTile(
        leading: const Icon(Icons.description_outlined, size: 20),
        title: Text(page.label),
        subtitle: Text(page.body.replaceAll('\n', ' '), maxLines: 1,
            overflow: TextOverflow.ellipsis),
        onTap: () => setState(() { selectedId = page.id; _clearSearch(); }),
      ),
    ]);
  }

  Widget _trashView() => ListView(children: [
    const Padding(padding: EdgeInsets.fromLTRB(20, 26, 20, 10),
      child: Text('Pages in trash', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600))),
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
}

class PageEditor extends StatefulWidget {
  const PageEditor({super.key, required this.page, required this.onSave,
    required this.onNewChild});
  final AnamnePage page;
  final Future<void> Function(AnamnePage) onSave;
  final VoidCallback onNewChild;

  @override
  State<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  late final TextEditingController title = TextEditingController(text: widget.page.title);
  late final TextEditingController body = TextEditingController(text: widget.page.body);
  Timer? debounce;

  void _schedule() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 450), _save);
  }

  void _save() {
    widget.onSave(widget.page.copyWith(title: title.text, body: body.text));
  }

  @override
  void dispose() {
    if (debounce?.isActive ?? false) {
      debounce?.cancel();
      _save();
    }
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 760),
    child: ListView(padding: const EdgeInsets.fromLTRB(24, 56, 24, 80), children: [
      TextField(
        controller: title,
        onChanged: (_) => _schedule(),
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 34, height: 1.18, fontWeight: FontWeight.w700,
            color: _ink),
        decoration: const InputDecoration(hintText: 'Untitled',
            hintStyle: TextStyle(color: Color(0xFFB5B4B0))),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: body,
        onChanged: (_) => _schedule(),
        maxLines: null,
        minLines: 12,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 16, height: 1.62, color: _ink),
        decoration: const InputDecoration(hintText: 'Start writing…',
            hintStyle: TextStyle(color: Color(0xFFB5B4B0))),
      ),
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: widget.onNewChild,
            icon: const Icon(Icons.add, size: 18), label: const Text('Add subpage'))),
    ]),
  ));
}
