import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:money_manager/app/theme/app_colors.dart';
import 'package:money_manager/core/utils/currency_formatter.dart';
import 'package:money_manager/domain/entities/account.dart' as account_domain;
import 'package:money_manager/domain/entities/category.dart' as category_domain;
import 'package:money_manager/domain/entities/money_transaction.dart';
import 'package:money_manager/domain/enums/category_type.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/domain/repositories/transaction_repository.dart';
import 'package:money_manager/shared/providers/app_providers.dart';
import 'package:money_manager/shared/widgets/app_mode_tabs.dart';
import 'package:money_manager/shared/widgets/app_filter_chips.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum TransactionListMode { active, archived }

enum TransactionDateFilter { all, thisMonth, last30Days, custom }

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _minAmountController = TextEditingController();
  final TextEditingController _maxAmountController = TextEditingController();
  TransactionListMode _mode = TransactionListMode.active;
  bool _showFilters = false;
  TransactionType? _typeFilter;
  String? _accountFilter;
  String? _categoryFilter;
  TransactionDateFilter _dateFilter = TransactionDateFilter.thisMonth;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void dispose() {
    _searchController.dispose();
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool archivedOnly = _mode == TransactionListMode.archived;
    final transactionsAsync = ref.watch(transactionsProvider(archivedOnly));
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final List<account_domain.Account>? accounts = accountsAsync.valueOrNull;
    final List<category_domain.Category>? categories =
        categoriesAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      floatingActionButton: archivedOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openCreateSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            ),
      body: transactionsAsync.when(
        data: (transactions) {
          final filteredTransactions = _applyFilters(transactions);
          final Widget filterPanel;

          if (accounts != null && categories != null) {
            final List<_CategoryPickerOption> categoryOptions =
                _categoryOptionsForFilter(categories);
            final String? effectiveAccountFilter = _resolveAccountFilter(
              accounts,
            );
            final String? effectiveCategoryFilter = _resolveCategoryFilter(
              categoryOptions,
            );

            _syncFilterSelections(
              effectiveAccountFilter: effectiveAccountFilter,
              effectiveCategoryFilter: effectiveCategoryFilter,
            );

            filterPanel = _TransactionFilterPanel(
              typeFilter: _typeFilter,
              accountFilter: effectiveAccountFilter,
              categoryFilter: effectiveCategoryFilter,
              dateFilter: _dateFilter,
              minAmountController: _minAmountController,
              maxAmountController: _maxAmountController,
              customStartDate: _customStartDate,
              customEndDate: _customEndDate,
              accounts: accounts,
              categoryOptions: categoryOptions,
              hasActiveFilters: _hasActiveFilters,
              onTypeChanged: (value) {
                setState(() {
                  _typeFilter = value;
                  if (value == TransactionType.transfer) {
                    _categoryFilter = null;
                  }
                });
              },
              onAccountChanged: (value) {
                setState(() {
                  _accountFilter = value;
                });
              },
              onCategoryChanged: (value) {
                setState(() {
                  _categoryFilter = value;
                });
              },
              onDateFilterChanged: (value) {
                setState(() {
                  _dateFilter = value;
                });
              },
              onAmountChanged: () {
                setState(() {});
              },
              onPickCustomRange: _pickCustomDateRange,
              onClearCustomRange: () {
                setState(() {
                  _customStartDate = null;
                  _customEndDate = null;
                  _dateFilter = TransactionDateFilter.all;
                });
              },
              onResetFilters: _resetFilters,
            );
          } else {
            filterPanel = const LinearProgressIndicator();
          }

          if (transactions.isEmpty) {
            return _EmptyTransactionsState(
              mode: _mode,
              onModeChanged: (mode) {
                setState(() {
                  _mode = mode;
                });
              },
              onCreate: archivedOnly ? null : () => _openCreateSheet(context),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TransactionToolbar(
                      mode: _mode,
                      onModeChanged: (mode) {
                        setState(() {
                          _mode = mode;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showFilters = !_showFilters;
                      });
                    },
                    icon: Icon(
                      _showFilters
                          ? Icons.filter_alt_off_rounded
                          : Icons.filter_alt_rounded,
                    ),
                    label: Text(_showFilters ? 'Hide filters' : 'Filters'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _AppSearchField(
                controller: _searchController,
                hintText: 'Search transactions',
                onChanged: (_) {
                  setState(() {});
                },
                onClear: () {
                  setState(() {
                    _searchController.clear();
                  });
                },
              ),
              if (_showFilters) ...<Widget>[
                const SizedBox(height: 16),
                filterPanel,
              ],
              const SizedBox(height: 16),
              if (filteredTransactions.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No transactions match the current filters.'),
                  ),
                ),
              ...filteredTransactions.map(
                (transaction) => _TransactionCard(
                  transaction: transaction,
                  archivedOnly: archivedOnly,
                  onEdit: archivedOnly
                      ? null
                      : () => _openEditSheet(context, transaction),
                  onArchive: archivedOnly
                      ? null
                      : () => ref
                            .read(transactionRepositoryProvider)
                            .softDeleteTransaction(transaction.id),
                  onRestore: archivedOnly
                      ? () => ref
                            .read(transactionRepositoryProvider)
                            .restoreTransaction(transaction.id)
                      : null,
                ),
              ),
            ],
          );
        },
        loading: () => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            children: <Widget>[
              AppModeTabs<TransactionListMode>(
                selected: _mode,
                onChanged: (mode) {
                  setState(() {
                    _mode = mode;
                  });
                },
                items: const <AppModeTabItem<TransactionListMode>>[
                  AppModeTabItem<TransactionListMode>(
                    value: TransactionListMode.active,
                    label: 'Active',
                    icon: Icons.receipt_long_outlined,
                  ),
                  AppModeTabItem<TransactionListMode>(
                    value: TransactionListMode.archived,
                    label: 'Archived',
                    icon: Icons.archive_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load transactions.\n$error'),
          ),
        ),
      ),
    );
  }

  List<MoneyTransaction> _applyFilters(List<MoneyTransaction> transactions) {
    final String query = _searchController.text.trim().toLowerCase();
    final DateTime now = DateTime.now();
    final int? minAmountMinor = _parseAmountFilter(_minAmountController.text);
    final int? maxAmountMinor = _parseAmountFilter(_maxAmountController.text);

    return transactions
        .where((transaction) {
          if (_typeFilter != null && transaction.type != _typeFilter) {
            return false;
          }

          if (_accountFilter != null &&
              transaction.accountId != _accountFilter &&
              transaction.destinationAccountId != _accountFilter) {
            return false;
          }

          if (_categoryFilter != null &&
              !_matchesCategoryFilter(transaction, _categoryFilter!)) {
            return false;
          }

          switch (_dateFilter) {
            case TransactionDateFilter.all:
              break;
            case TransactionDateFilter.thisMonth:
              final bool sameMonth =
                  transaction.transactionDate.year == now.year &&
                  transaction.transactionDate.month == now.month;
              if (!sameMonth) {
                return false;
              }
              break;
            case TransactionDateFilter.last30Days:
              final DateTime cutoff = now.subtract(const Duration(days: 30));
              if (transaction.transactionDate.isBefore(cutoff)) {
                return false;
              }
              break;
            case TransactionDateFilter.custom:
              if (_customStartDate != null &&
                  transaction.transactionDate.isBefore(
                    _startOfDay(_customStartDate!),
                  )) {
                return false;
              }

              if (_customEndDate != null &&
                  transaction.transactionDate.isAfter(
                    _endOfDay(_customEndDate!),
                  )) {
                return false;
              }
              break;
          }

          if (minAmountMinor != null &&
              transaction.amountMinor < minAmountMinor) {
            return false;
          }

          if (maxAmountMinor != null &&
              transaction.amountMinor > maxAmountMinor) {
            return false;
          }

          if (query.isEmpty) {
            return true;
          }

          final searchableText = <String>[
            transaction.note,
            transaction.accountName,
            transaction.destinationAccountName ?? '',
            transaction.categoryName ?? '',
            transaction.childCategoryName ?? '',
            _transactionTitle(transaction.type),
          ].join(' ').toLowerCase();

          return searchableText.contains(query);
        })
        .toList(growable: false);
  }

  String _transactionTitle(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.income:
        return 'Income';
      case TransactionType.transfer:
        return 'Transfer';
    }
  }

  bool get _hasActiveFilters {
    return _typeFilter != null ||
        _accountFilter != null ||
        _categoryFilter != null ||
        _dateFilter != TransactionDateFilter.thisMonth ||
        _minAmountController.text.trim().isNotEmpty ||
        _maxAmountController.text.trim().isNotEmpty ||
        _customStartDate != null ||
        _customEndDate != null;
  }

  int? _parseAmountFilter(String rawValue) {
    final String value = rawValue.trim();
    if (value.isEmpty) {
      return null;
    }

    final double? parsed = double.tryParse(value);
    if (parsed == null || parsed < 0) {
      return null;
    }

    return (parsed * 100).round();
  }

  bool _matchesCategoryFilter(MoneyTransaction transaction, String categoryId) {
    if (transaction.childCategoryId == categoryId) {
      return true;
    }

    return transaction.categoryId == categoryId;
  }

  String? _resolveAccountFilter(List<dynamic> accounts) {
    if (_accountFilter == null) {
      return null;
    }

    final bool exists = accounts.any((account) => account.id == _accountFilter);
    return exists ? _accountFilter : null;
  }

  String? _resolveCategoryFilter(List<_CategoryPickerOption> categoryOptions) {
    if (_categoryFilter == null) {
      return null;
    }

    final bool exists = categoryOptions.any(
      (option) => option.category.id == _categoryFilter,
    );
    return exists ? _categoryFilter : null;
  }

  void _syncFilterSelections({
    required String? effectiveAccountFilter,
    required String? effectiveCategoryFilter,
  }) {
    if (_accountFilter == effectiveAccountFilter &&
        _categoryFilter == effectiveCategoryFilter) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _accountFilter = effectiveAccountFilter;
        _categoryFilter = effectiveCategoryFilter;
      });
    });
  }

  CategoryType _categoryTypeForTransaction(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return CategoryType.expense;
      case TransactionType.income:
        return CategoryType.income;
      case TransactionType.transfer:
        return CategoryType.expense;
    }
  }

  List<_CategoryPickerOption> _categoryOptionsForFilter(
    List<category_domain.Category> categories,
  ) {
    if (_typeFilter == TransactionType.transfer) {
      return const <_CategoryPickerOption>[];
    }

    final List<category_domain.Category> filteredCategories = categories
        .where((category) {
          if (_typeFilter == null) {
            return category.type == CategoryType.expense ||
                category.type == CategoryType.income ||
                category.type == CategoryType.both;
          }

          return category.type == _categoryTypeForTransaction(_typeFilter!) ||
              category.type == CategoryType.both;
        })
        .toList(growable: false);

    return _categoryOptionsForCategories(filteredCategories);
  }

  List<_CategoryPickerOption> _categoryOptionsForCategories(
    List<category_domain.Category> categories,
  ) {
    final parentCategories =
        categories
            .where((category) => category.isParent)
            .toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name));

    final List<_CategoryPickerOption> options = <_CategoryPickerOption>[];
    for (final parent in parentCategories) {
      options.add(
        _CategoryPickerOption(
          category: parent,
          label: parent.name,
          isChild: false,
        ),
      );

      final childCategories =
          categories
              .where((category) => category.parentId == parent.id)
              .toList(growable: false)
            ..sort((a, b) => a.name.compareTo(b.name));

      for (final child in childCategories) {
        options.add(
          _CategoryPickerOption(
            category: child,
            label: '${parent.name} > ${child.name}',
            isChild: true,
          ),
        );
      }
    }

    return options;
  }

  Future<void> _pickCustomDateRange() async {
    final DateTime now = DateTime.now();
    final DateTime initialStart = _customStartDate ?? now;
    final DateTime? start = await showDatePicker(
      context: context,
      initialDate: initialStart,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
    );

    if (start == null || !mounted) {
      return;
    }

    final DateTime initialEnd =
        _customEndDate != null && !_customEndDate!.isBefore(start)
        ? _customEndDate!
        : start;
    final DateTime? end = await showDatePicker(
      context: context,
      initialDate: initialEnd,
      firstDate: start,
      lastDate: DateTime(now.year + 5),
    );

    if (end == null || !mounted) {
      return;
    }

    setState(() {
      _customStartDate = start;
      _customEndDate = end;
      _dateFilter = TransactionDateFilter.custom;
    });
  }

  void _resetFilters() {
    setState(() {
      _showFilters = false;
      _typeFilter = null;
      _accountFilter = null;
      _categoryFilter = null;
      _dateFilter = TransactionDateFilter.thisMonth;
      _customStartDate = null;
      _customEndDate = null;
      _minAmountController.clear();
      _maxAmountController.clear();
      _searchController.clear();
    });
  }

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  Future<void> _openCreateSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateTransactionSheet(
        onSubmit: (input) async {
          await ref
              .read(transactionRepositoryProvider)
              .createTransaction(input);
        },
      ),
    );
  }

  Future<void> _openEditSheet(
    BuildContext context,
    MoneyTransaction transaction,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateTransactionSheet(
        initialTransaction: transaction,
        onSubmit: (input) async {
          await ref
              .read(transactionRepositoryProvider)
              .updateTransaction(transaction.id, input);
        },
      ),
    );
  }
}

class _AppSearchField extends StatelessWidget {
  const _AppSearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final bool hasText = controller.text.trim().isNotEmpty;

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.lightMint, width: 1.4),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          color: AppColors.textDark,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: AppColors.textDark.withValues(alpha: 0.40),
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.lightMint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: AppColors.primaryDark,
              size: 21,
            ),
          ),
          suffixIcon: hasText
              ? IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.textDark,
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 15,
          ),
        ),
      ),
    );
  }
}

class _TransactionFilterPanel extends StatelessWidget {
  const _TransactionFilterPanel({
    required this.typeFilter,
    required this.accountFilter,
    required this.categoryFilter,
    required this.dateFilter,
    required this.minAmountController,
    required this.maxAmountController,
    required this.customStartDate,
    required this.customEndDate,
    required this.accounts,
    required this.categoryOptions,
    required this.hasActiveFilters,
    required this.onTypeChanged,
    required this.onAccountChanged,
    required this.onCategoryChanged,
    required this.onDateFilterChanged,
    required this.onAmountChanged,
    required this.onPickCustomRange,
    required this.onClearCustomRange,
    required this.onResetFilters,
  });

  final TransactionType? typeFilter;
  final String? accountFilter;
  final String? categoryFilter;
  final TransactionDateFilter dateFilter;
  final TextEditingController minAmountController;
  final TextEditingController maxAmountController;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final List<account_domain.Account> accounts;
  final List<_CategoryPickerOption> categoryOptions;
  final bool hasActiveFilters;
  final ValueChanged<TransactionType?> onTypeChanged;
  final ValueChanged<String?> onAccountChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<TransactionDateFilter> onDateFilterChanged;
  final VoidCallback onAmountChanged;
  final Future<void> Function() onPickCustomRange;
  final VoidCallback onClearCustomRange;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Filters',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (hasActiveFilters)
                  TextButton.icon(
                    onPressed: onResetFilters,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reset'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<TransactionType?>(
                    key: ValueKey<String>('tx-type-$typeFilter'),
                    initialValue: typeFilter,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const <DropdownMenuItem<TransactionType?>>[
                      DropdownMenuItem<TransactionType?>(
                        value: null,
                        child: Text('All types'),
                      ),
                      DropdownMenuItem<TransactionType?>(
                        value: TransactionType.expense,
                        child: Text('Expense'),
                      ),
                      DropdownMenuItem<TransactionType?>(
                        value: TransactionType.income,
                        child: Text('Income'),
                      ),
                      DropdownMenuItem<TransactionType?>(
                        value: TransactionType.transfer,
                        child: Text('Transfer'),
                      ),
                    ],
                    onChanged: onTypeChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey<String>(
                      'tx-account-${accountFilter ?? 'all'}-${accounts.length}',
                    ),
                    initialValue: accountFilter,
                    decoration: const InputDecoration(labelText: 'Account'),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All accounts'),
                      ),
                      ...accounts.map(
                        (account) => DropdownMenuItem<String?>(
                          value: account.id,
                          child: Text(account.name),
                        ),
                      ),
                    ],
                    onChanged: onAccountChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey<String>(
                'tx-category-${categoryFilter ?? 'all'}-${categoryOptions.length}-$typeFilter',
              ),
              initialValue: categoryFilter,
              decoration: InputDecoration(
                labelText: 'Category',
                helperText: typeFilter == TransactionType.transfer
                    ? 'Transfers do not use categories.'
                    : 'Select a parent or a child category.',
              ),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All categories'),
                ),
                ...categoryOptions.map(
                  (option) => DropdownMenuItem<String?>(
                    value: option.category.id,
                    child: Text(
                      option.isChild ? '↳ ${option.label}' : option.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: typeFilter == TransactionType.transfer
                  ? null
                  : onCategoryChanged,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: minAmountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Min amount'),
                    onChanged: (_) => onAmountChanged(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: maxAmountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Max amount'),
                    onChanged: (_) => onAmountChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppFilterChips<TransactionDateFilter>(
              selected: dateFilter,
              onChanged: onDateFilterChanged,
              items: const <AppFilterChipItem<TransactionDateFilter>>[
                AppFilterChipItem<TransactionDateFilter>(
                  value: TransactionDateFilter.thisMonth,
                  label: 'This month',
                ),
                AppFilterChipItem<TransactionDateFilter>(
                  value: TransactionDateFilter.last30Days,
                  label: 'Last 30 days',
                ),
                AppFilterChipItem<TransactionDateFilter>(
                  value: TransactionDateFilter.all,
                  label: 'All time',
                ),
                AppFilterChipItem<TransactionDateFilter>(
                  value: TransactionDateFilter.custom,
                  label: 'Custom',
                ),
              ],
            ),
            if (dateFilter == TransactionDateFilter.custom) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.lightMint.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        customStartDate == null || customEndDate == null
                            ? 'Pick a custom date range'
                            : '${_formatDate(customStartDate!)} to ${_formatDate(customEndDate!)}',
                      ),
                    ),
                    TextButton(
                      onPressed: onPickCustomRange,
                      child: const Text('Choose'),
                    ),
                    if (customStartDate != null || customEndDate != null)
                      TextButton(
                        onPressed: onClearCustomRange,
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _TransactionToolbar extends StatelessWidget {
  const _TransactionToolbar({required this.mode, required this.onModeChanged});

  final TransactionListMode mode;
  final ValueChanged<TransactionListMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return AppModeTabs<TransactionListMode>(
      selected: mode,
      onChanged: onModeChanged,
      items: const <AppModeTabItem<TransactionListMode>>[
        AppModeTabItem<TransactionListMode>(
          value: TransactionListMode.active,
          label: 'Active',
          icon: Icons.receipt_long_outlined,
        ),
        AppModeTabItem<TransactionListMode>(
          value: TransactionListMode.archived,
          label: 'Archived',
          icon: Icons.archive_outlined,
        ),
      ],
    );
  }
}

class _EmptyTransactionsState extends StatelessWidget {
  const _EmptyTransactionsState({
    required this.mode,
    required this.onModeChanged,
    required this.onCreate,
  });

  final TransactionListMode mode;
  final ValueChanged<TransactionListMode> onModeChanged;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final bool archivedOnly = mode == TransactionListMode.archived;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: <Widget>[
          AppModeTabs<TransactionListMode>(
            selected: mode,
            onChanged: onModeChanged,
            items: const <AppModeTabItem<TransactionListMode>>[
              AppModeTabItem<TransactionListMode>(
                value: TransactionListMode.active,
                label: 'Active',
                icon: Icons.receipt_long_outlined,
              ),
              AppModeTabItem<TransactionListMode>(
                value: TransactionListMode.archived,
                label: 'Archived',
                icon: Icons.archive_outlined,
              ),
            ],
          ),
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
                          : Icons.receipt_long_outlined,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      archivedOnly
                          ? 'No archived transactions'
                          : 'No transactions yet',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      archivedOnly
                          ? 'Archived transactions will appear here and can be restored.'
                          : 'Create your first income, expense, or transfer to start tracking balances.',
                      textAlign: TextAlign.center,
                    ),
                    if (!archivedOnly) ...<Widget>[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: onCreate,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add transaction'),
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

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.transaction,
    required this.archivedOnly,
    this.onEdit,
    this.onArchive,
    this.onRestore,
  });

  final MoneyTransaction transaction;
  final bool archivedOnly;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onArchive;
  final Future<void> Function()? onRestore;

  @override
  Widget build(BuildContext context) {
    final bool isIncome = transaction.type == TransactionType.income;
    final bool isExpense = transaction.type == TransactionType.expense;
    final Color amountColor = isIncome
        ? AppColors.positive
        : isExpense
        ? AppColors.negative
        : AppColors.primary;

    final String amountLabel = switch (transaction.type) {
      TransactionType.income =>
        '+ ${CurrencyFormatter.formatMinorUnits(transaction.amountMinor)}',
      TransactionType.expense =>
        '- ${CurrencyFormatter.formatMinorUnits(transaction.amountMinor)}',
      TransactionType.transfer => CurrencyFormatter.formatMinorUnits(
        transaction.amountMinor,
      ),
    };

    final String categoryLabel = _categoryLabel(transaction);
    final String subtitle = switch (transaction.type) {
      TransactionType.transfer =>
        '${transaction.accountName} -> ${transaction.destinationAccountName ?? 'Unknown'}',
      _ => '${transaction.accountName} • $categoryLabel',
    };
    final int attachmentCount = transaction.attachmentFilePaths.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    transaction.note.isEmpty
                        ? _transactionTitle(transaction.type)
                        : transaction.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  amountLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: amountColor),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${transaction.transactionDate.year}-${transaction.transactionDate.month.toString().padLeft(2, '0')}-${transaction.transactionDate.day.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (attachmentCount > 0)
                  Text(
                    '$attachmentCount receipt${attachmentCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    switch (value) {
                      case 'edit':
                        await onEdit?.call();
                        break;
                      case 'archive':
                        await onArchive?.call();
                        break;
                      case 'restore':
                        await onRestore?.call();
                        break;
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _transactionTitle(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.income:
        return 'Income';
      case TransactionType.transfer:
        return 'Transfer';
    }
  }

  String _categoryLabel(MoneyTransaction transaction) {
    final String? parentName = transaction.categoryName;
    final String? childName = transaction.childCategoryName;

    if (parentName != null && childName != null) {
      return '$parentName > $childName';
    }

    return childName ?? parentName ?? 'Uncategorized';
  }
}

class _CreateTransactionSheet extends ConsumerStatefulWidget {
  const _CreateTransactionSheet({
    required this.onSubmit,
    this.initialTransaction,
  });

  final Future<void> Function(CreateTransactionInput input) onSubmit;
  final MoneyTransaction? initialTransaction;

  @override
  ConsumerState<_CreateTransactionSheet> createState() =>
      _CreateTransactionSheetState();
}

class _CreateTransactionSheetState
    extends ConsumerState<_CreateTransactionSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  late TransactionType _selectedType;
  String? _selectedAccountId;
  String? _selectedDestinationAccountId;
  String? _selectedCategoryId;
  String? _selectedChildCategoryId;
  late DateTime _selectedDate;
  final ImagePicker _imagePicker = ImagePicker();
  late List<String> _attachmentFilePaths;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final transaction = widget.initialTransaction;
    _selectedType = transaction?.type ?? TransactionType.expense;
    _selectedAccountId = transaction?.accountId;
    _selectedDestinationAccountId = transaction?.destinationAccountId;
    _selectedCategoryId = transaction?.categoryId;
    _selectedChildCategoryId = transaction?.childCategoryId;
    _selectedDate = transaction?.transactionDate ?? DateTime.now();
    _amountController = TextEditingController(
      text: transaction == null
          ? '0.00'
          : (transaction.amountMinor / 100).toStringAsFixed(2),
    );
    _noteController = TextEditingController(text: transaction?.note ?? '');
    _attachmentFilePaths = List<String>.of(
      transaction?.attachmentFilePaths ?? const <String>[],
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final MediaQueryData mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        mediaQuery.viewInsets.bottom + 24,
      ),
      child: accountsAsync.when(
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Create at least one account before adding transactions.',
              ),
            );
          }

          _selectedAccountId ??= accounts.first.id;
          if (_selectedType == TransactionType.transfer) {
            _selectedDestinationAccountId ??=
                accounts
                    .where((item) => item.id != _selectedAccountId)
                    .isNotEmpty
                ? accounts
                      .firstWhere((item) => item.id != _selectedAccountId)
                      .id
                : null;
          }

          return Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                Text(
                  widget.initialTransaction == null
                      ? 'Add transaction'
                      : 'Edit transaction',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                SegmentedButton<TransactionType>(
                  segments: const <ButtonSegment<TransactionType>>[
                    ButtonSegment<TransactionType>(
                      value: TransactionType.expense,
                      label: Text('Expense'),
                    ),
                    ButtonSegment<TransactionType>(
                      value: TransactionType.income,
                      label: Text('Income'),
                    ),
                    ButtonSegment<TransactionType>(
                      value: TransactionType.transfer,
                      label: Text('Transfer'),
                    ),
                  ],
                  selected: <TransactionType>{_selectedType},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _selectedType = selection.first;
                      if (_selectedType == TransactionType.transfer) {
                        _selectedCategoryId = null;
                        _selectedChildCategoryId = null;
                      } else {
                        _selectedDestinationAccountId = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount'),
                  validator: (value) {
                    final parsed = double.tryParse((value ?? '').trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a positive amount';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Transaction date',
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                        ),
                        const Icon(Icons.calendar_today_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedAccountId,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: accounts
                      .map(
                        (account) => DropdownMenuItem<String>(
                          value: account.id,
                          child: Text(account.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    setState(() {
                      _selectedAccountId = value;
                      if (_selectedDestinationAccountId == value) {
                        _selectedDestinationAccountId = null;
                      }
                    });
                  },
                ),
                if (_selectedType == TransactionType.transfer) ...<Widget>[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDestinationAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Destination account',
                    ),
                    items: accounts
                        .where((account) => account.id != _selectedAccountId)
                        .map(
                          (account) => DropdownMenuItem<String>(
                            value: account.id,
                            child: Text(account.name),
                          ),
                        )
                        .toList(growable: false),
                    validator: (value) {
                      if (_selectedType == TransactionType.transfer &&
                          (value == null || value == _selectedAccountId)) {
                        return 'Choose a different destination account';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      setState(() {
                        _selectedDestinationAccountId = value;
                      });
                    },
                  ),
                ],
                if (_selectedType != TransactionType.transfer) ...<Widget>[
                  const SizedBox(height: 12),
                  categoriesAsync.when(
                    data: (categories) {
                      final categoryOptions = _categoryOptionsForTransaction(
                        categories,
                        _selectedType,
                      );
                      final selectedCategoryPickerId =
                          _selectedChildCategoryId ?? _selectedCategoryId;

                      return DropdownButtonFormField<String?>(
                        initialValue: selectedCategoryPickerId,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          helperText:
                              'Choose either a parent category or a child category.',
                        ),
                        items: <DropdownMenuItem<String?>>[
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('None'),
                          ),
                          ...categoryOptions.map(
                            (option) => DropdownMenuItem<String?>(
                              value: option.category.id,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    option.isChild
                                        ? Icons.subdirectory_arrow_right_rounded
                                        : Icons.folder_outlined,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: Text(
                                      option.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          final selectedCategory = _findCategoryOption(
                            categoryOptions,
                            value,
                          )?.category;

                          setState(() {
                            if (selectedCategory == null) {
                              _selectedCategoryId = null;
                              _selectedChildCategoryId = null;
                            } else if (selectedCategory.isParent) {
                              _selectedCategoryId = selectedCategory.id;
                              _selectedChildCategoryId = null;
                            } else {
                              _selectedCategoryId = selectedCategory.parentId;
                              _selectedChildCategoryId = selectedCategory.id;
                            }
                          });
                        },
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    ),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: _selectedType == TransactionType.transfer
                        ? 'Note'
                        : 'Note / description',
                  ),
                ),
                const SizedBox(height: 16),
                _ReceiptPicker(
                  attachmentFilePaths: _attachmentFilePaths,
                  onAddFromGallery: _attachmentFilePaths.length >= 4
                      ? null
                      : _pickReceiptsFromGallery,
                  onAddFromCamera: _attachmentFilePaths.length >= 4
                      ? null
                      : _pickReceiptFromCamera,
                  onRemove: (path) {
                    setState(() {
                      _attachmentFilePaths.remove(path);
                    });
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSaving ? null : _submit,
                  child: Text(
                    _isSaving
                        ? 'Saving...'
                        : widget.initialTransaction == null
                        ? 'Save transaction'
                        : 'Update transaction',
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load transaction form.\n$error'),
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
      await widget.onSubmit(
        CreateTransactionInput(
          type: _selectedType,
          accountId: _selectedAccountId!,
          destinationAccountId: _selectedType == TransactionType.transfer
              ? _selectedDestinationAccountId
              : null,
          amountMinor: _parseMinorUnits(_amountController.text),
          transactionDate: _selectedDate,
          note: _noteController.text,
          categoryId: _selectedType == TransactionType.transfer
              ? null
              : _selectedCategoryId,
          childCategoryId: _selectedType == TransactionType.transfer
              ? null
              : _selectedChildCategoryId,
          attachmentFilePaths: _attachmentFilePaths,
        ),
      );

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

  int _parseMinorUnits(String value) {
    final double parsed = double.parse(value.trim());
    return (parsed * 100).round();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickReceiptsFromGallery() async {
    final int remainingSlots = 4 - _attachmentFilePaths.length;
    if (remainingSlots <= 0) {
      return;
    }

    final images = await _imagePicker.pickMultiImage();
    final selectedImages = images.take(remainingSlots).toList(growable: false);

    await _copyPickedImages(selectedImages);
  }

  Future<void> _pickReceiptFromCamera() async {
    if (_attachmentFilePaths.length >= 4) {
      return;
    }

    final image = await _imagePicker.pickImage(source: ImageSource.camera);
    if (image == null) {
      return;
    }

    await _copyPickedImages(<XFile>[image]);
  }

  Future<void> _copyPickedImages(List<XFile> images) async {
    if (images.isEmpty) {
      return;
    }

    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final Directory receiptsDirectory = Directory(
      p.join(documentsDirectory.path, 'receipts'),
    );
    await receiptsDirectory.create(recursive: true);

    final List<String> copiedPaths = <String>[];
    for (int index = 0; index < images.length; index += 1) {
      final XFile image = images[index];
      final String extension = p.extension(image.path).isEmpty
          ? '.jpg'
          : p.extension(image.path);
      final String fileName =
          'receipt_${DateTime.now().microsecondsSinceEpoch}_$index$extension';
      final String destinationPath = p.join(receiptsDirectory.path, fileName);

      await File(image.path).copy(destinationPath);
      copiedPaths.add(destinationPath);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _attachmentFilePaths = <String>[
        ..._attachmentFilePaths,
        ...copiedPaths,
      ].take(4).toList(growable: false);
    });
  }

  CategoryType _categoryTypeForTransaction(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return CategoryType.expense;
      case TransactionType.income:
        return CategoryType.income;
      case TransactionType.transfer:
        return CategoryType.expense;
    }
  }

  List<_CategoryPickerOption> _categoryOptionsForTransaction(
    List<category_domain.Category> categories,
    TransactionType type,
  ) {
    final categoryType = _categoryTypeForTransaction(type);
    final parentCategories =
        categories
            .where(
              (category) =>
                  category.isParent &&
                  (category.type == categoryType ||
                      category.type == CategoryType.both),
            )
            .toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name));

    final List<_CategoryPickerOption> options = <_CategoryPickerOption>[];
    for (final parent in parentCategories) {
      options.add(
        _CategoryPickerOption(
          category: parent,
          label: parent.name,
          isChild: false,
        ),
      );

      final childCategories =
          categories
              .where((category) => category.parentId == parent.id)
              .toList(growable: false)
            ..sort((a, b) => a.name.compareTo(b.name));

      for (final child in childCategories) {
        options.add(
          _CategoryPickerOption(
            category: child,
            label: '${parent.name} > ${child.name}',
            isChild: true,
          ),
        );
      }
    }

    return options;
  }

  _CategoryPickerOption? _findCategoryOption(
    List<_CategoryPickerOption> options,
    String? categoryId,
  ) {
    if (categoryId == null) {
      return null;
    }

    for (final option in options) {
      if (option.category.id == categoryId) {
        return option;
      }
    }

    return null;
  }
}

class _CategoryPickerOption {
  const _CategoryPickerOption({
    required this.category,
    required this.label,
    required this.isChild,
  });

  final category_domain.Category category;
  final String label;
  final bool isChild;
}

class _ReceiptPicker extends StatelessWidget {
  const _ReceiptPicker({
    required this.attachmentFilePaths,
    required this.onRemove,
    this.onAddFromGallery,
    this.onAddFromCamera,
  });

  final List<String> attachmentFilePaths;
  final VoidCallback? onAddFromGallery;
  final VoidCallback? onAddFromCamera;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Receipts', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: onAddFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Gallery'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onAddFromCamera,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Camera'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${attachmentFilePaths.length}/4 images',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (attachmentFilePaths.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: attachmentFilePaths
                .map((filePath) {
                  return Stack(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(filePath),
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 76,
                              height: 76,
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image_outlined),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: () => onRemove(filePath),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ],
                  );
                })
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}
