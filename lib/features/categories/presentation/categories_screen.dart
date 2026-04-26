import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/core/utils/category_visuals.dart';
import 'package:money_manager/domain/entities/category.dart' as domain;
import 'package:money_manager/domain/enums/category_type.dart';
import 'package:money_manager/domain/repositories/category_repository.dart';
import 'package:money_manager/shared/providers/app_providers.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: <Widget>[
          IconButton(
            onPressed: () => _showCreateCategorySheet(context, ref),
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Create category',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateCategorySheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add category'),
      ),
      body: categoriesAsync.when(
        data: (categories) {
          if (categories.isEmpty) {
            return _EmptyCategoriesState(
              onCreate: () => _showCreateCategorySheet(context, ref),
            );
          }

          final Map<String, List<domain.Category>> grouped = _groupByParent(
            categories,
          );
          final List<domain.Category> parents = categories
              .where((category) => category.isParent)
              .toList(growable: false);

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: parents.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final parent = parents[index];
              final children = grouped[parent.id] ?? const <domain.Category>[];

              return Card(
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  leading: CircleAvatar(
                    backgroundColor: parent.color.withValues(alpha: 0.16),
                    foregroundColor: parent.color,
                    child: Icon(CategoryVisuals.iconFromKey(parent.iconKey)),
                  ),
                  title: Text(parent.name),
                  subtitle: Text(_categoryTypeLabel(parent.type)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await _showEditCategorySheet(context, ref, parent);
                      } else if (value == 'archive') {
                        await ref
                            .read(categoryRepositoryProvider)
                            .softDeleteCategory(parent.id);
                      }

                      if (value == 'add_child' && context.mounted) {
                        await _showCreateCategorySheet(
                          context,
                          ref,
                          preselectedParent: parent,
                        );
                      }
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
                      PopupMenuItem<String>(
                        value: 'add_child',
                        child: Text('Add child'),
                      ),
                      PopupMenuItem<String>(
                        value: 'archive',
                        child: Text('Archive'),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    if (children.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('No child categories yet'),
                        ),
                      ),
                    ...children.map(
                      (child) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const SizedBox(width: 12),
                        title: Text(child.name),
                        subtitle: Text(_categoryTypeLabel(child.type)),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'edit') {
                              await _showEditCategorySheet(context, ref, child);
                            } else if (value == 'archive') {
                              await ref
                                  .read(categoryRepositoryProvider)
                                  .softDeleteCategory(child.id);
                            }
                          },
                          itemBuilder: (context) =>
                              const <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem<String>(
                                  value: 'archive',
                                  child: Text('Archive'),
                                ),
                              ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load categories.\n$error'),
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateCategorySheet(
    BuildContext context,
    WidgetRef ref, {
    domain.Category? preselectedParent,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateCategorySheet(
        preselectedParent: preselectedParent,
        onCreate: (input) async {
          await ref.read(categoryRepositoryProvider).createCategory(input);
        },
      ),
    );
  }

  Future<void> _showEditCategorySheet(
    BuildContext context,
    WidgetRef ref,
    domain.Category category,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateCategorySheet(
        category: category,
        onCreate: (input) async {
          await ref.read(categoryRepositoryProvider).createCategory(input);
        },
        onUpdate: (input) async {
          await ref
              .read(categoryRepositoryProvider)
              .updateCategory(category.id, input);
        },
      ),
    );
  }

  Map<String, List<domain.Category>> _groupByParent(
    List<domain.Category> categories,
  ) {
    final Map<String, List<domain.Category>> grouped =
        <String, List<domain.Category>>{};

    for (final category in categories) {
      final String? parentId = category.parentId;
      if (parentId == null) continue;

      grouped.putIfAbsent(parentId, () => <domain.Category>[]).add(category);
    }

    return grouped;
  }

  String _categoryTypeLabel(CategoryType type) {
    switch (type) {
      case CategoryType.expense:
        return 'Expense';
      case CategoryType.income:
        return 'Income';
      case CategoryType.both:
        return 'Both';
    }
  }
}

class _EmptyCategoriesState extends StatelessWidget {
  const _EmptyCategoriesState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.category_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'No categories yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create parent and child categories like Food > Groceries or Car > Gas.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create category'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateCategorySheet extends ConsumerStatefulWidget {
  const _CreateCategorySheet({
    required this.onCreate,
    this.onUpdate,
    this.preselectedParent,
    this.category,
  });

  final Future<void> Function(CreateCategoryInput input) onCreate;
  final Future<void> Function(UpdateCategoryInput input)? onUpdate;
  final domain.Category? preselectedParent;
  final domain.Category? category;

  @override
  ConsumerState<_CreateCategorySheet> createState() =>
      _CreateCategorySheetState();
}

class _CreateCategorySheetState extends ConsumerState<_CreateCategorySheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();

  late CategoryType _selectedType;
  late int _selectedColorValue;
  late String _selectedIconKey;
  String? _selectedParentId;
  bool _isSaving = false;
  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();

    final category = widget.category;
    if (category != null) {
      _nameController.text = category.name;
      _selectedType = category.type;
      _selectedParentId = category.parentId;
      _selectedColorValue = category.colorValue;
      _selectedIconKey = category.iconKey;
      return;
    }

    final preselectedParent = widget.preselectedParent;
    _selectedType = preselectedParent?.type ?? CategoryType.expense;
    _selectedParentId = preselectedParent?.id;
    _selectedColorValue =
        preselectedParent?.colorValue ?? CategoryVisuals.palette.first;
    _selectedIconKey = preselectedParent?.iconKey ?? 'shopping';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        mediaQuery.viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Text(
              _isEditing
                  ? 'Edit category'
                  : widget.preselectedParent == null
                  ? 'Create category'
                  : 'Create child category',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Category name'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a category name';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CategoryType>(
              initialValue: _selectedType,
              decoration: const InputDecoration(labelText: 'Category type'),
              items: CategoryType.values
                  .map(
                    (type) => DropdownMenuItem<CategoryType>(
                      value: type,
                      child: Text(_categoryTypeLabel(type)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: widget.preselectedParent != null || _isEditing
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedType = value;
                        _selectedParentId = null;
                      });
                    },
            ),
            const SizedBox(height: 12),
            categoriesAsync.when(
              data: (categories) {
                final parentOptions = categories
                    .where(
                      (category) =>
                          category.isParent &&
                          category.id != widget.category?.id &&
                          category.type == _selectedType,
                    )
                    .toList(growable: false);

                final bool parentLocked =
                    widget.preselectedParent != null ||
                    (widget.category?.isParent ?? false);

                return DropdownButtonFormField<String?>(
                  initialValue: _selectedParentId,
                  decoration: const InputDecoration(
                    labelText: 'Parent category (optional)',
                  ),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None'),
                    ),
                    ...parentOptions.map(
                      (category) => DropdownMenuItem<String?>(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    ),
                  ],
                  onChanged: parentLocked
                      ? null
                      : (value) {
                          setState(() {
                            _selectedParentId = value;
                          });
                        },
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            Text('Color', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: CategoryVisuals.palette
                  .map((colorValue) {
                    final bool selected = colorValue == _selectedColorValue;
                    final Color color = CategoryVisuals.colorFromValue(
                      colorValue,
                    );

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedColorValue = colorValue;
                        });
                      },
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: color,
                        child: selected
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
            const SizedBox(height: 16),
            Text('Icon', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: CategoryVisuals.iconMap.entries
                  .map((entry) {
                    final bool selected = entry.key == _selectedIconKey;

                    return ChoiceChip(
                      label: Icon(entry.value, size: 20),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _selectedIconKey = entry.key;
                        });
                      },
                    );
                  })
                  .toList(growable: false),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _submit,
              child: Text(_isSaving ? 'Saving...' : 'Save category'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      if (_isEditing) {
        await widget.onUpdate!(
          UpdateCategoryInput(
            name: _nameController.text,
            parentId: widget.category!.isParent ? null : _selectedParentId,
            type: _selectedType,
            iconKey: _selectedIconKey,
            colorValue: _selectedColorValue,
            sortOrder: widget.category!.sortOrder,
            isActive: widget.category!.isActive,
          ),
        );
      } else {
        await widget.onCreate(
          CreateCategoryInput(
            name: _nameController.text,
            parentId: _selectedParentId,
            type: _selectedType,
            iconKey: _selectedIconKey,
            colorValue: _selectedColorValue,
          ),
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _categoryTypeLabel(CategoryType type) {
    switch (type) {
      case CategoryType.expense:
        return 'Expense';
      case CategoryType.income:
        return 'Income';
      case CategoryType.both:
        return 'Both';
    }
  }
}
