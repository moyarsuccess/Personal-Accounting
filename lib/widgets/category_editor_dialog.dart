import 'package:flutter/material.dart';
import 'package:personal_accounting/models/category.dart';
import 'package:personal_accounting/utils/category_icons.dart';
import 'package:uuid/uuid.dart';

/// Returned by [showCategoryEditorDialog]. Carries all three fields the
/// caller needs to persist; null = user dismissed.
typedef CategoryEditorResult = Category;

Future<Category?> showCategoryEditorDialog(
  BuildContext context, {
  Category? existing,
}) {
  return showDialog<Category>(
    context: context,
    builder: (_) => _CategoryEditorDialog(existing: existing),
  );
}

class _CategoryEditorDialog extends StatefulWidget {
  final Category? existing;
  const _CategoryEditorDialog({this.existing});

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _searchController;
  late String _iconCode;
  late Color _color;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _searchController = TextEditingController();
    _iconCode = widget.existing?.iconCode ?? 'shopping_bag';
    _color = widget.existing != null
        ? Color(widget.existing!.colorCode)
        : categoryColorPalette.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name is required.')));
      return;
    }
    final result = Category(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: name,
      iconCode: _iconCode,
      colorCode: _color.toARGB32(),
    );
    Navigator.of(context).pop(result);
  }

  /// Returns the filtered icon list as section-of-codes pairs, dropping
  /// sections whose every icon was filtered out so the empty-state reads
  /// cleanly.
  List<MapEntry<String, List<String>>> _filteredSections() {
    if (_query.isEmpty) {
      return iconSections.entries.toList();
    }
    final q = _query.toLowerCase().trim();
    final out = <MapEntry<String, List<String>>>[];
    for (final entry in iconSections.entries) {
      final hits = entry.value
          .where((code) => code.contains(q) || entry.key.toLowerCase().contains(q))
          .toList();
      if (hits.isNotEmpty) {
        out.add(MapEntry(entry.key, hits));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filteredSections();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                children: [
                  // Live preview of the chosen icon + colour.
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _color,
                    child: Icon(
                      iconForCode(_iconCode),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.existing != null
                          ? 'Edit category'
                          : 'New category',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Name ───────────────────────────────────────────────────
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              // ── Colour palette ─────────────────────────────────────────
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categoryColorPalette.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final c = categoryColorPalette[i];
                    final selected = c.toARGB32() == _color.toARGB32();
                    return GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  width: 3,
                                )
                              : null,
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ── Search ─────────────────────────────────────────────────
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search icons',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),

              // ── Icon grid ──────────────────────────────────────────────
              Expanded(
                child: sections.isEmpty
                    ? Center(
                        child: Text(
                          'No icons match "$_query"',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        itemCount: sections.length,
                        itemBuilder: (context, i) {
                          final section = sections[i];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  section.key,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: section.value
                                    .map(_buildIconTile)
                                    .toList(),
                              ),
                            ],
                          );
                        },
                      ),
              ),

              // ── Actions ────────────────────────────────────────────────
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconTile(String code) {
    final selected = code == _iconCode;
    return GestureDetector(
      onTap: () => setState(() => _iconCode = code),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: selected
              ? _color
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 2,
                )
              : null,
        ),
        child: Icon(
          iconForCode(code),
          color: selected
              ? Colors.white
              : Theme.of(context).colorScheme.onSurfaceVariant,
          size: 24,
        ),
      ),
    );
  }
}
