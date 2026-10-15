import '../editor/block.dart';
import '../store/page.dart';

/// One resolved connection between two pages.
class PageLink {
  const PageLink({required this.sourceId, required this.targetTitle});
  final String sourceId;
  final String targetTitle;
}

/// Computes `[[wikilink]]` edges across the workspace for the backlinks
/// panel and the graph view. Matching is case-insensitive on page titles,
/// mirroring how file-based note tools resolve links.
class LinkIndex {
  LinkIndex(this.pages);

  final List<AnamnePage> pages;

  Map<String, List<String>> get _targetsByPage {
    final map = <String, List<String>>{};
    for (final page in pages) {
      final targets = <String>[];
      void addTarget(String target) {
        final clean = target.trim();
        if (clean.isNotEmpty && !targets.contains(clean)) targets.add(clean);
      }

      // Blocks are authoritative; the markdown body is the same content
      // projected, so it only serves legacy pages without blocks.
      if (page.blocks.isNotEmpty) {
        for (final block in page.blocks) {
          wikilinkTargets(block['text'] as String? ?? '').forEach(addTarget);
        }
      } else {
        wikilinkTargets(page.body).forEach(addTarget);
      }
      map[page.id] = targets;
    }
    return map;
  }

  String _titleOf(AnamnePage page) => page.label.toLowerCase();

  /// All outgoing links for each page id.
  Map<String, List<String>> outgoingTargets() => _targetsByPage;

  /// Pages whose content links to [page], by title match.
  List<AnamnePage> backlinksTo(AnamnePage page) {
    final title = _titleOf(page);
    final result = <AnamnePage>[];
    for (final source in pages) {
      if (source.id == page.id) continue;
      final targets = _targetsByPage[source.id] ?? const [];
      if (targets.any((t) => t.toLowerCase() == title)) {
        result.add(source);
      }
    }
    return result;
  }

  /// Outgoing links of [page] that resolve to real pages.
  List<AnamnePage> outgoingTo(AnamnePage page) {
    final targets = _targetsByPage[page.id] ?? const [];
    final result = <AnamnePage>[];
    for (final target in targets) {
      final lower = target.toLowerCase();
      for (final candidate in pages) {
        if (candidate.id != page.id && _titleOf(candidate) == lower) {
          result.add(candidate);
          break;
        }
      }
    }
    return result;
  }

  /// Graph edges as (sourceId, targetId) pairs for resolved links.
  List<(String, String)> edges() {
    final result = <(String, String)>[];
    for (final source in pages) {
      for (final target in outgoingTo(source)) {
        result.add((source.id, target.id));
      }
    }
    return result;
  }
}
