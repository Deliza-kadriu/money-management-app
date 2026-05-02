import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/core/utils/category_visuals.dart';
import 'package:money_manager/domain/entities/category.dart' as domain;
import 'package:money_manager/domain/enums/category_type.dart';
import 'package:money_manager/domain/repositories/category_repository.dart';
import 'package:money_manager/shared/providers/app_providers.dart';
import 'package:money_manager/shared/widgets/app_mode_tabs.dart';

enum CategoryListMode { active, archived }

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  CategoryListMode _mode = CategoryListMode.active;

  @override
  Widget build(BuildContext context) {
    final bool archivedOnly = _mode == CategoryListMode.archived;
    final categoriesAsync = ref.watch(categoriesByModeProvider(archivedOnly));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: <Widget>[
          if (!archivedOnly)
            IconButton(
              onPressed: () => _showCreateCategorySheet(context, ref),
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: 'Create category',
            ),
        ],
      ),
      floatingActionButton: archivedOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showCreateCategorySheet(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add category'),
            ),
      body: categoriesAsync.when(
        data: (categories) {
          if (categories.isEmpty) {
            return _EmptyCategoriesState(
              mode: _mode,
              onModeChanged: (mode) {
                setState(() {
                  _mode = mode;
                });
              },
              onCreate: archivedOnly
                  ? null
                  : () => _showCreateCategorySheet(context, ref),
            );
          }

          final Map<String, List<domain.Category>> grouped = _groupByParent(
            categories,
          );
          final List<domain.Category> parents = categories
              .where((category) => category.isParent)
              .toList(growable: false);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: <Widget>[
              _CategoryToolbar(
                mode: _mode,
                onModeChanged: (mode) {
                  setState(() {
                    _mode = mode;
                  });
                },
              ),
              const SizedBox(height: 16),
              ...parents.map((parent) {
                final children =
                    grouped[parent.id] ?? const <domain.Category>[];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
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
                        } else if (value == 'restore') {
                          await ref
                              .read(categoryRepositoryProvider)
                              .restoreCategory(parent.id);
                        } else if (value == 'add_child' && context.mounted) {
                          await _showCreateCategorySheet(
                            context,
                            ref,
                            preselectedParent: parent,
                          );
                        }
                      },
                      itemBuilder: (context) => archivedOnly
                          ? const <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'restore',
                                child: Text('Restore'),
                              ),
                            ]
                          : const <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
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
                                await _showEditCategorySheet(
                                  context,
                                  ref,
                                  child,
                                );
                              } else if (value == 'archive') {
                                await ref
                                    .read(categoryRepositoryProvider)
                                    .softDeleteCategory(child.id);
                              } else if (value == 'restore') {
                                await ref
                                    .read(categoryRepositoryProvider)
                                    .restoreCategory(child.id);
                              }
                            },
                            itemBuilder: (context) => archivedOnly
                                ? const <PopupMenuEntry<String>>[
                                    PopupMenuItem<String>(
                                      value: 'restore',
                                      child: Text('Restore'),
                                    ),
                                  ]
                                : const <PopupMenuEntry<String>>[
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
              }),
            ],
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
      if (parentId == null) {
        continue;
      }

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

class _CategoryToolbar extends StatelessWidget {
  const _CategoryToolbar({required this.mode, required this.onModeChanged});

  final CategoryListMode mode;
  final ValueChanged<CategoryListMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return AppModeTabs<CategoryListMode>(
      selected: mode,
      onChanged: onModeChanged,
      items: const <AppModeTabItem<CategoryListMode>>[
        AppModeTabItem<CategoryListMode>(
          value: CategoryListMode.active,
          label: 'Active',
          icon: Icons.category_outlined,
        ),
        AppModeTabItem<CategoryListMode>(
          value: CategoryListMode.archived,
          label: 'Archived',
          icon: Icons.archive_outlined,
        ),
      ],
    );
  }
}

class _EmptyCategoriesState extends StatelessWidget {
  const _EmptyCategoriesState({
    required this.mode,
    required this.onModeChanged,
    required this.onCreate,
  });

  final CategoryListMode mode;
  final ValueChanged<CategoryListMode> onModeChanged;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final bool archivedOnly = mode == CategoryListMode.archived;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: <Widget>[
          _CategoryToolbar(mode: mode, onModeChanged: onModeChanged),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      archivedOnly
                          ? Icons.archive_outlined
                          : Icons.category_outlined,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      archivedOnly
                          ? 'No archived categories'
                          : 'No categories yet',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      archivedOnly
                          ? 'Archived categories will appear here and can be restored.'
                          : 'Create parent and child categories like Food > Groceries or Car > Gas.',
                      textAlign: TextAlign.center,
                    ),
                    if (!archivedOnly) ...<Widget>[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: onCreate,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create category'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
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
  String? _selectedParentId;
  late int _selectedColorValue;
  late String _selectedIconKey;
  bool _isSaving = false;
  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();

    final category = widget.category;
    final preselectedParent = widget.preselectedParent;
    _nameController.text = category?.name ?? '';
    _selectedParentId = category?.parentId ?? preselectedParent?.id;
    _selectedType =
        category?.type ?? preselectedParent?.type ?? CategoryType.expense;
    _selectedColorValue =
        category?.colorValue ??
        preselectedParent?.colorValue ??
        CategoryVisuals.palette.first;
    _selectedIconKey =
        category?.iconKey ??
        preselectedParent?.iconKey ??
        CategoryVisuals.iconMap.keys.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final MediaQueryData mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        mediaQuery.viewInsets.bottom + 24,
      ),
      child: categoriesAsync.when(
        data: (categories) {
          final parentCategories = categories
              .where((category) => category.isParent)
              .toList(growable: false);

          return SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _isEditing ? 'Edit category' : 'Add category',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Category name',
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Enter a category name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedParentId,
                    decoration: const InputDecoration(
                      labelText: 'Parent category',
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None (parent category)'),
                      ),
                      ...parentCategories.map(
                        (category) => DropdownMenuItem<String?>(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedParentId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<CategoryType>(
                    initialValue: _selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Category type',
                    ),
                    items: CategoryType.values
                        .map(
                          (type) => DropdownMenuItem<CategoryType>(
                            value: type,
                            child: Text(_categoryTypeLabel(type)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _selectedType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Color', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                    ),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: CategoryVisuals.palette
                          .map((value) {
                            final Color color = CategoryVisuals.colorFromValue(
                              value,
                            );
                            final bool isSelected =
                                _selectedColorValue == value;

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedColorValue = value;
                                });
                              },
                              child: CircleAvatar(
                                radius: isSelected ? 22 : 20,
                                backgroundColor: color,
                                child: isSelected
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
                  ),
                  const SizedBox(height: 16),
                  Text('Icon', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Choose from a larger icon set for better category recognition.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 280,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                    ),
                    child: GridView.builder(
                      itemCount: CategoryVisuals.iconMap.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemBuilder: (context, index) {
                        final MapEntry<String, IconData> entry = CategoryVisuals
                            .iconMap
                            .entries
                            .elementAt(index);
                        final bool isSelected = _selectedIconKey == entry.key;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedIconKey = entry.key;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: isSelected
                                  ? CategoryVisuals.colorFromValue(
                                      _selectedColorValue,
                                    )
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              border: Border.all(
                                color: isSelected
                                    ? CategoryVisuals.colorFromValue(
                                        _selectedColorValue,
                                      )
                                    : Colors.transparent,
                                width: 1.4,
                              ),
                            ),
                            child: Icon(
                              entry.value,
                              color: isSelected
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isSaving ? null : _submit,
                    child: Text(
                      _isSaving
                          ? 'Saving...'
                          : _isEditing
                          ? 'Update category'
                          : 'Save category',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load category form.\n$error'),
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
        await widget.onUpdate?.call(
          UpdateCategoryInput(
            name: _nameController.text,
            parentId: _selectedParentId,
            type: _selectedType,
            iconKey: _selectedIconKey,
            colorValue: _selectedColorValue,
            sortOrder: 0,
            isActive: true,
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
