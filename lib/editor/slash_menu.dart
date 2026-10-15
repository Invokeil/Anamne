import 'package:flutter/material.dart';

import '../ui/theme.dart';

class SlashCommand {
  const SlashCommand(this.label, this.type, {this.icon, this.hint});
  final String label;
  final String type;
  final IconData? icon;
  final String? hint;
}

const slashCommands = <SlashCommand>[
  SlashCommand('Text', 'paragraph', icon: Icons.notes_outlined, hint: 'Plain paragraph'),
  SlashCommand('Heading 1', 'h1', icon: Icons.format_size_outlined, hint: 'Large section heading'),
  SlashCommand('Heading 2', 'h2', icon: Icons.format_size, hint: 'Medium section heading'),
  SlashCommand('Heading 3', 'h3', icon: Icons.format_size_sharp, hint: 'Small section heading'),
  SlashCommand('To-do list', 'todo', icon: Icons.check_box_outlined, hint: 'Track tasks with checkboxes'),
  SlashCommand('Bulleted list', 'bullet', icon: Icons.list, hint: 'Simple bullet list'),
  SlashCommand('Numbered list', 'number', icon: Icons.format_list_numbered, hint: 'Ordered list'),
  SlashCommand('Toggle list', 'toggle', icon: Icons.arrow_right, hint: 'Collapsible list section'),
  SlashCommand('Quote', 'quote', icon: Icons.format_quote_outlined, hint: 'Capture a quotation'),
  SlashCommand('Callout', 'callout', icon: Icons.info_outline, hint: 'Highlighted note box'),
  SlashCommand('Code', 'code', icon: Icons.code_outlined, hint: 'Code with monospace font'),
  SlashCommand('Divider', 'divider', icon: Icons.horizontal_rule, hint: 'Visual separator'),
  SlashCommand('Database', 'database', icon: Icons.table_chart_outlined, hint: 'Embed a structured database'),
];

/// Compact, searchable slash command menu (docs/DESIGN.md editor rules).
class SlashMenu extends StatelessWidget {
  const SlashMenu({
    super.key,
    required this.query,
    required this.onSelect,
    required this.onDismiss,
  });

  final String query;
  final ValueChanged<SlashCommand> onSelect;
  final VoidCallback onDismiss;

  List<SlashCommand> get _filtered => slashCommands
      .where((c) => c.label.toLowerCase().contains(query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Material(
      color: sheet,
      borderRadius: BorderRadius.circular(8),
      elevation: 6,
      shadowColor: Colors.black26,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: dividerSand),
        ),
        constraints: const BoxConstraints(maxHeight: 320, maxWidth: 280),
        child: items.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(14),
                child: Text('No block matches "/$query"',
                    style: const TextStyle(color: muted, fontSize: 13)),
              )
            : ListView(shrinkWrap: true, padding: const EdgeInsets.all(8), children: [
                for (final command in items)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    leading: Icon(command.icon, size: 19, color: muted),
                    title: Text(command.label, style: const TextStyle(fontSize: 14)),
                    subtitle: command.hint == null
                        ? null
                        : Text(command.hint!,
                            style: const TextStyle(fontSize: 11, color: muted)),
                    onTap: () => onSelect(command),
                  ),
              ]),
      ),
    );
  }
}

/// Page-name autocomplete for `[[wikilinks]]`.
class WikilinkMenu extends StatelessWidget {
  const WikilinkMenu({
    super.key,
    required this.query,
    required this.titles,
    required this.onSelect,
  });

  final String query;
  final List<String> titles;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final lower = query.toLowerCase();
    final matches = titles
        .where((t) => t.toLowerCase().contains(lower) && t.trim().isNotEmpty)
        .take(8)
        .toList();
    if (matches.isEmpty) {
      return Material(
        color: sheet,
        borderRadius: BorderRadius.circular(8),
        elevation: 6,
        shadowColor: Colors.black26,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: dividerSand),
          ),
          padding: const EdgeInsets.all(14),
          child: Text(
            query.trim().isEmpty
                ? 'Type to link a page…'
                : 'Create or match "[[$query]]"',
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        ),
      );
    }
    return Material(
      color: sheet,
      borderRadius: BorderRadius.circular(8),
      elevation: 6,
      shadowColor: Colors.black26,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: dividerSand),
        ),
        constraints: const BoxConstraints(maxHeight: 260, maxWidth: 280),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(8), children: [
          for (final title in matches)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              leading: const Icon(Icons.link_outlined, size: 18, color: muted),
              title: Text(title, style: const TextStyle(fontSize: 14)),
              onTap: () => onSelect(title),
            ),
        ]),
      ),
    );
  }
}
