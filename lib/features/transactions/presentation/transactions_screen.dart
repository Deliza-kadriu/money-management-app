import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:money_manager/app/theme/app_colors.dart';
import 'package:money_manager/core/utils/category_visuals.dart';
import 'package:money_manager/core/utils/date_formatter.dart';
import 'package:money_manager/core/utils/currency_formatter.dart';
import 'package:money_manager/domain/entities/account.dart' as account_domain;
import 'package:money_manager/domain/entities/category.dart' as category_domain;
import 'package:money_manager/domain/entities/money_transaction.dart';
import 'package:money_manager/domain/enums/category_type.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/domain/repositories/transaction_repository.dart';
import 'package:money_manager/shared/providers/app_providers.dart';
import 'package:money_manager/shared/widgets/app_filter_chips.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum TransactionListMode { active, archived }

enum TransactionDateFilter { all, thisMonth, last30Days, custom }

enum TransactionPresentationTab { expense, income, allList }

const String _uncategorizedFilterValue = '__uncategorized__';

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
  String? _accountFilter;
  String? _categoryFilter;
  TransactionDateFilter _dateFilter = TransactionDateFilter.thisMonth;
  TransactionPresentationTab _presentationTab =
      TransactionPresentationTab.expense;
  final Set<String> _hiddenExpenseInsightLabels = <String>{};
  final Set<String> _hiddenIncomeInsightLabels = <String>{};
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
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final transactionsAsync = ref.watch(transactionsProvider(archivedOnly));
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final List<account_domain.Account>? accounts = accountsAsync.valueOrNull;
    final List<category_domain.Category>? categories =
        categoriesAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(archivedOnly ? 'Archived transactions' : 'Transactions'),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              setState(() {
                _mode = archivedOnly
                    ? TransactionListMode.active
                    : TransactionListMode.archived;
              });
            },
            icon: Icon(
              archivedOnly ? Icons.unarchive_outlined : Icons.archive_outlined,
            ),
            tooltip: archivedOnly ? 'Show active' : 'Show archived',
          ),
        ],
      ),
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
          final displayedTransactions = _transactionsForPresentationTab(
            filteredTransactions,
            _presentationTab,
          );
          final categoryGroups = _categoryGroupsForTransactions(
            displayedTransactions,
            categories ?? const <category_domain.Category>[],
          );
          final bool filtersReady = accounts != null && categories != null;

          if (filtersReady) {
            final List<_CategoryPickerOption> categoryOptions =
                _categoryOptionsForFilter(categories, _presentationTab);
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
          }

          Widget buildTransactionEntry(MoneyTransaction transaction) {
            return _TransactionCard(
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
            );
          }

          if (transactions.isEmpty) {
            return _EmptyTransactionsState(
              mode: _mode,
              onCreate: archivedOnly ? null : () => _openCreateSheet(context),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.lightMint,
                    width: 1.3,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.22 : 0.05,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SegmentedButton<TransactionPresentationTab>(
                  style: ButtonStyle(
                    side: WidgetStatePropertyAll(BorderSide.none),
                    backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.selected)) {
                        return isDark
                            ? AppColors.primaryDark.withValues(alpha: 0.48)
                            : AppColors.lightMint;
                      }
                      return Colors.transparent;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.selected)) {
                        return isDark
                            ? AppColors.textLight
                            : AppColors.primaryDark;
                      }
                      return isDark
                          ? AppColors.mutedLight
                          : AppColors.textDark.withValues(alpha: 0.72);
                    }),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                  segments: const <ButtonSegment<TransactionPresentationTab>>[
                    ButtonSegment<TransactionPresentationTab>(
                      value: TransactionPresentationTab.expense,
                      label: Text('Expenses'),
                      icon: Icon(Icons.arrow_upward_rounded),
                    ),
                    ButtonSegment<TransactionPresentationTab>(
                      value: TransactionPresentationTab.income,
                      label: Text('Income'),
                      icon: Icon(Icons.arrow_downward_rounded),
                    ),
                    ButtonSegment<TransactionPresentationTab>(
                      value: TransactionPresentationTab.allList,
                      label: Text('All list'),
                      icon: Icon(Icons.view_list_rounded),
                    ),
                  ],
                  selected: <TransactionPresentationTab>{_presentationTab},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _presentationTab = selection.first;
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: _AppSearchField(
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
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      onPressed: filtersReady
                          ? () =>
                                _openFiltersSheet(context, accounts, categories)
                          : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        side: BorderSide(
                          color: _hasActiveFilters
                              ? AppColors.primary
                              : isDark
                              ? AppColors.darkBorder
                              : AppColors.lightMint,
                          width: 1.3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        backgroundColor: _hasActiveFilters
                            ? AppColors.primary.withValues(
                                alpha: isDark ? 0.22 : 0.10,
                              )
                            : theme.cardColor,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Stack(
                            clipBehavior: Clip.none,
                            children: <Widget>[
                              Icon(
                                Icons.tune_rounded,
                                color: isDark
                                    ? AppColors.textLight
                                    : AppColors.textDark,
                              ),
                              if (_hasActiveFilters)
                                Positioned(
                                  right: -1,
                                  top: -1,
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          const Text('Filter'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _TransactionInsightsCard(
                transactions: filteredTransactions,
                categories: categories ?? const <category_domain.Category>[],
                presentationTab: _presentationTab,
                hiddenExpenseLabels: _hiddenExpenseInsightLabels,
                hiddenIncomeLabels: _hiddenIncomeInsightLabels,
              ),
              const SizedBox(height: 16),
              if (displayedTransactions.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No transactions match the current filters.'),
                  ),
                ),
              if (_presentationTab == TransactionPresentationTab.allList)
                ...displayedTransactions.map(buildTransactionEntry),
              if (_presentationTab != TransactionPresentationTab.allList)
                ...categoryGroups.map(
                  (group) => _TransactionCategorySection(
                    group: group,
                    archivedOnly: archivedOnly,
                    itemBuilder: buildTransactionEntry,
                    hiddenChartLabels:
                        _presentationTab == TransactionPresentationTab.income
                        ? _hiddenIncomeInsightLabels
                        : _hiddenExpenseInsightLabels,
                    onToggleChartLabels: (labels) {
                      setState(() {
                        final Set<String> target =
                            _presentationTab ==
                                TransactionPresentationTab.income
                            ? _hiddenIncomeInsightLabels
                            : _hiddenExpenseInsightLabels;
                        final bool allHidden = labels.every(target.contains);
                        if (allHidden) {
                          target.removeAll(labels);
                        } else {
                          target.addAll(labels);
                        }
                      });
                    },
                  ),
                ),
            ],
          );
        },
        loading: () => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            children: <Widget>[
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

  List<MoneyTransaction> _transactionsForPresentationTab(
    List<MoneyTransaction> transactions,
    TransactionPresentationTab tab,
  ) {
    switch (tab) {
      case TransactionPresentationTab.expense:
        return transactions
            .where((transaction) => transaction.type == TransactionType.expense)
            .toList(growable: false);
      case TransactionPresentationTab.income:
        return transactions
            .where((transaction) => transaction.type == TransactionType.income)
            .toList(growable: false);
      case TransactionPresentationTab.allList:
        return transactions;
    }
  }

  bool get _hasActiveFilters {
    return _accountFilter != null ||
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
    if (categoryId == _uncategorizedFilterValue) {
      return transaction.categoryId == null &&
          transaction.childCategoryId == null;
    }

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

    if (_categoryFilter == _uncategorizedFilterValue) {
      return _categoryFilter;
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

  CategoryType? _categoryTypeForPresentationTab(
    TransactionPresentationTab tab,
  ) {
    switch (tab) {
      case TransactionPresentationTab.expense:
        return CategoryType.expense;
      case TransactionPresentationTab.income:
        return CategoryType.income;
      case TransactionPresentationTab.allList:
        return null;
    }
  }

  List<_CategoryPickerOption> _categoryOptionsForFilter(
    List<category_domain.Category> categories,
    TransactionPresentationTab presentationTab,
  ) {
    final CategoryType? categoryType = _categoryTypeForPresentationTab(
      presentationTab,
    );

    final List<category_domain.Category> filteredCategories = categories
        .where((category) {
          if (categoryType == null) {
            return category.type == CategoryType.expense ||
                category.type == CategoryType.income ||
                category.type == CategoryType.both;
          }

          return category.type == categoryType ||
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
      _accountFilter = null;
      _categoryFilter = null;
      _dateFilter = TransactionDateFilter.thisMonth;
      _customStartDate = null;
      _customEndDate = null;
      _minAmountController.clear();
      _maxAmountController.clear();
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

  Future<void> _openFiltersSheet(
    BuildContext context,
    List<account_domain.Account> accounts,
    List<category_domain.Category> categories,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final List<_CategoryPickerOption> categoryOptions =
                _categoryOptionsForFilter(categories, _presentationTab);
            final String? effectiveAccountFilter = _resolveAccountFilter(
              accounts,
            );
            final String? effectiveCategoryFilter = _resolveCategoryFilter(
              categoryOptions,
            );

            void updateFilters(VoidCallback update) {
              setState(update);
              setSheetState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: _TransactionFilterPanel(
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
                    onAccountChanged: (value) {
                      updateFilters(() {
                        _accountFilter = value;
                      });
                    },
                    onCategoryChanged: (value) {
                      updateFilters(() {
                        _categoryFilter = value;
                      });
                    },
                    onDateFilterChanged: (value) {
                      updateFilters(() {
                        _dateFilter = value;
                      });
                    },
                    onAmountChanged: () {
                      updateFilters(() {});
                    },
                    onPickCustomRange: () async {
                      await _pickCustomDateRange();
                      setSheetState(() {});
                    },
                    onClearCustomRange: () {
                      updateFilters(() {
                        _customStartDate = null;
                        _customEndDate = null;
                        _dateFilter = TransactionDateFilter.all;
                      });
                    },
                    onResetFilters: () {
                      _resetFilters();
                      setSheetState(() {});
                    },
                    onClose: () => Navigator.of(sheetContext).pop(),
                  ),
                ),
              ),
            );
          },
        );
      },
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
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color borderColor = isDark
        ? AppColors.darkBorder
        : AppColors.lightMint;
    final Color fieldColor = isDark ? AppColors.darkCard : Colors.white;
    final Color iconBackground = isDark
        ? AppColors.primaryDark.withValues(alpha: 0.55)
        : AppColors.lightMint;
    final Color textColor = isDark ? AppColors.textLight : AppColors.textDark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: fieldColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 1.4),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            filled: false,
            hintText: hintText,
            hintStyle: TextStyle(
              color: textColor.withValues(alpha: 0.50),
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Container(
              margin: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                Icons.search_rounded,
                color: isDark ? AppColors.textLight : AppColors.primaryDark,
                size: 21,
              ),
            ),
            suffixIcon: hasText
                ? IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                    color: textColor,
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
      ),
    );
  }
}

class _TransactionFilterPanel extends StatelessWidget {
  const _TransactionFilterPanel({
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
    required this.onAccountChanged,
    required this.onCategoryChanged,
    required this.onDateFilterChanged,
    required this.onAmountChanged,
    required this.onPickCustomRange,
    required this.onClearCustomRange,
    required this.onResetFilters,
    required this.onClose,
  });

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
  final ValueChanged<String?> onAccountChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<TransactionDateFilter> onDateFilterChanged;
  final VoidCallback onAmountChanged;
  final Future<void> Function() onPickCustomRange;
  final VoidCallback onClearCustomRange;
  final VoidCallback onResetFilters;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Filters',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (hasActiveFilters)
              TextButton.icon(
                onPressed: onResetFilters,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reset'),
              ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close filters',
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
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
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          key: ValueKey<String>(
            'tx-category-${categoryFilter ?? 'all'}-${categoryOptions.length}',
          ),
          initialValue: categoryFilter,
          decoration: const InputDecoration(
            labelText: 'Category',
            helperText: 'Select a parent or a child category.',
          ),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All categories'),
            ),
            const DropdownMenuItem<String?>(
              value: _uncategorizedFilterValue,
              child: Text('Uncategorized'),
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
          onChanged: onCategoryChanged,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: minAmountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Min amount'),
          onChanged: (_) => onAmountChanged(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: maxAmountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Max amount'),
          onChanged: (_) => onAmountChanged(),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  customStartDate == null || customEndDate == null
                      ? 'Pick a custom date range'
                      : '${_formatDate(customStartDate!)} to ${_formatDate(customEndDate!)}',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
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
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onClose, child: const Text('Done')),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return AppDateFormatter.format(date);
  }
}

class _TransactionInsightsCard extends StatelessWidget {
  const _TransactionInsightsCard({
    required this.transactions,
    required this.categories,
    required this.presentationTab,
    required this.hiddenExpenseLabels,
    required this.hiddenIncomeLabels,
  });

  final List<MoneyTransaction> transactions;
  final List<category_domain.Category> categories;
  final TransactionPresentationTab presentationTab;
  final Set<String> hiddenExpenseLabels;
  final Set<String> hiddenIncomeLabels;

  @override
  Widget build(BuildContext context) {
    final expenseRows = _categoryRowsForTransactions(
      transactions,
      TransactionType.expense,
      categories,
    );
    final incomeRows = _categoryRowsForTransactions(
      transactions,
      TransactionType.income,
      categories,
    );

    final bool showExpense =
        presentationTab == TransactionPresentationTab.expense ||
        presentationTab == TransactionPresentationTab.allList;
    final bool showIncome =
        presentationTab == TransactionPresentationTab.income ||
        presentationTab == TransactionPresentationTab.allList;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (showExpense && expenseRows.isNotEmpty) ...<Widget>[
              _TransactionPieSection(
                title: 'Expense categories',
                rows: expenseRows,
                accentColor: AppColors.negative,
                hiddenLabels: hiddenExpenseLabels,
              ),
            ],
            if (showIncome && incomeRows.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              _TransactionPieSection(
                title: 'Income categories',
                rows: incomeRows,
                accentColor: AppColors.positive,
                hiddenLabels: hiddenIncomeLabels,
              ),
            ],
            if ((showExpense && expenseRows.isEmpty) &&
                (showIncome && incomeRows.isEmpty)) ...<Widget>[
              const SizedBox(height: 12),
              const Text(
                'No category data is available for this filtered view.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransactionCategorySection extends StatelessWidget {
  const _TransactionCategorySection({
    required this.group,
    required this.archivedOnly,
    required this.itemBuilder,
    required this.hiddenChartLabels,
    required this.onToggleChartLabels,
  });

  final _TransactionCategoryGroup group;
  final bool archivedOnly;
  final Widget Function(MoneyTransaction transaction) itemBuilder;
  final Set<String> hiddenChartLabels;
  final ValueChanged<List<String>> onToggleChartLabels;

  @override
  Widget build(BuildContext context) {
    final bool allHidden =
        group.chartLabels.isNotEmpty &&
        group.chartLabels.every(hiddenChartLabels.contains);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: CircleAvatar(
            backgroundColor: group.color.withValues(alpha: 0.16),
            foregroundColor: group.color,
            child: Icon(group.icon, size: 18),
          ),
          title: Text(
            group.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            '${group.totalCount} transaction(s)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                onPressed: group.chartLabels.isEmpty
                    ? null
                    : () => onToggleChartLabels(group.chartLabels),
                icon: Icon(
                  allHidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: group.color,
                ),
                tooltip: allHidden ? 'Show in chart' : 'Hide from chart',
              ),
              Text(
                CurrencyFormatter.formatMinorUnits(group.totalMinor),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: group.type == TransactionType.income
                      ? AppColors.positive
                      : AppColors.negative,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more_rounded),
            ],
          ),
          children: <Widget>[
            if (group.directTransactions.isNotEmpty)
              ...group.directTransactions.map(itemBuilder),
            ...group.childGroups.map(
              (childGroup) => _TransactionChildCategorySection(
                group: childGroup,
                itemBuilder: itemBuilder,
                hiddenChartLabels: hiddenChartLabels,
                onToggleChartLabels: onToggleChartLabels,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionChildCategorySection extends StatelessWidget {
  const _TransactionChildCategorySection({
    required this.group,
    required this.itemBuilder,
    required this.hiddenChartLabels,
    required this.onToggleChartLabels,
  });

  final _TransactionChildGroup group;
  final Widget Function(MoneyTransaction transaction) itemBuilder;
  final Set<String> hiddenChartLabels;
  final ValueChanged<List<String>> onToggleChartLabels;

  @override
  Widget build(BuildContext context) {
    final bool isHidden = hiddenChartLabels.contains(group.chartLabel);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: group.color.withValues(alpha: 0.16),
            foregroundColor: group.color,
            child: Icon(group.icon, size: 16),
          ),
          title: Text(
            group.label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(
            '${group.transactions.length} transaction(s)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                onPressed: () =>
                    onToggleChartLabels(<String>[group.chartLabel]),
                icon: Icon(
                  isHidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: group.color,
                ),
                tooltip: isHidden ? 'Show in chart' : 'Hide from chart',
              ),
              Text(
                CurrencyFormatter.formatMinorUnits(group.totalMinor),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more_rounded),
            ],
          ),
          children: <Widget>[...group.transactions.map(itemBuilder)],
        ),
      ),
    );
  }
}

class _CategoryPickerField extends StatelessWidget {
  const _CategoryPickerField({
    required this.selectedLabel,
    required this.isChild,
    required this.onTap,
  });

  final String? selectedLabel;
  final bool isChild;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Category',
          helperText: 'Pick a parent or child category from a clearer list.',
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selectedLabel == null
                  ? Icons.category_outlined
                  : isChild
                  ? Icons.subdirectory_arrow_right_rounded
                  : Icons.folder_outlined,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selectedLabel ?? 'No category',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more_rounded),
          ],
        ),
      ),
    );
  }
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.options,
    required this.selectedCategoryId,
  });

  final List<_CategoryPickerOption> options;
  final String? selectedCategoryId;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final List<_CategoryPickerParentGroup> groupedOptions =
        _groupCategoryPickerOptions(widget.options, query);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SizedBox(
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Choose category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search category',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: const Text('No category'),
                trailing: widget.selectedCategoryId == null
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop<String?>(null),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Expanded(
                child: groupedOptions.isEmpty
                    ? const Center(child: Text('No matching categories'))
                    : ListView(
                        children: groupedOptions
                            .map(
                              (group) => _CategoryPickerGroupCard(
                                group: group,
                                selectedCategoryId: widget.selectedCategoryId,
                                onPick: (categoryId) => Navigator.of(
                                  context,
                                ).pop<String?>(categoryId),
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPickerGroupCard extends StatelessWidget {
  const _CategoryPickerGroupCard({
    required this.group,
    required this.selectedCategoryId,
    required this.onPick,
  });

  final _CategoryPickerParentGroup group;
  final String? selectedCategoryId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final bool parentSelected = selectedCategoryId == group.parent.category.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onPick(group.parent.category.id),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: group.parent.category.color.withValues(
                    alpha: parentSelected ? 0.18 : 0.10,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: parentSelected
                        ? group.parent.category.color
                        : group.parent.category.color.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: group.parent.category.color.withValues(
                        alpha: 0.18,
                      ),
                      foregroundColor: group.parent.category.color,
                      child: Icon(
                        CategoryVisuals.iconFromKey(
                          group.parent.category.iconKey,
                        ),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        group.parent.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (parentSelected)
                      Icon(
                        Icons.check_circle_rounded,
                        color: group.parent.category.color,
                      ),
                  ],
                ),
              ),
            ),
            if (group.children.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: group.children
                    .map((child) {
                      final bool selected =
                          selectedCategoryId == child.category.id;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => onPick(child.category.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: child.category.color.withValues(
                              alpha: selected ? 0.18 : 0.08,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? child.category.color
                                  : child.category.color.withValues(
                                      alpha: 0.20,
                                    ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                CategoryVisuals.iconFromKey(
                                  child.category.iconKey,
                                ),
                                size: 16,
                                color: child.category.color,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                child.category.name,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              if (selected) ...<Widget>[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: child.category.color,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransactionPieSection extends StatelessWidget {
  const _TransactionPieSection({
    required this.title,
    required this.rows,
    required this.accentColor,
    required this.hiddenLabels,
  });

  final String title;
  final List<_CategoryAmountRow> rows;
  final Color accentColor;
  final Set<String> hiddenLabels;

  @override
  Widget build(BuildContext context) {
    final visibleRows = rows
        .where((row) => !hiddenLabels.contains(row.label))
        .toList(growable: false);
    final int allTotal = rows.fold<int>(0, (sum, row) => sum + row.amountMinor);
    final int visibleTotal = visibleRows.fold<int>(
      0,
      (sum, row) => sum + row.amountMinor,
    );
    final int hiddenTotal = allTotal - visibleTotal;
    final slices = _buildPieSlices(visibleRows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          hiddenLabels.isEmpty
              ? 'Visible total: ${CurrencyFormatter.formatMinorUnits(visibleTotal)}'
              : 'Visible total: ${CurrencyFormatter.formatMinorUnits(visibleTotal)}  •  Hidden: ${CurrencyFormatter.formatMinorUnits(hiddenTotal)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (visibleRows.isEmpty)
          Text(
            'All categories are hidden in this chart.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: CustomPaint(
                painter: _TransactionPiePainter(
                  slices: slices,
                  baseColor: accentColor,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _CategoryAmountRow {
  const _CategoryAmountRow({
    required this.label,
    required this.amountMinor,
    required this.color,
    required this.icon,
  });

  final String label;
  final int amountMinor;
  final Color color;
  final IconData icon;
}

class _CategoryVisualMeta {
  const _CategoryVisualMeta({required this.color, required this.icon});

  final Color color;
  final IconData icon;
}

class _TransactionCategoryGroup {
  const _TransactionCategoryGroup({
    required this.label,
    required this.chartLabels,
    required this.directTransactions,
    required this.childGroups,
    required this.totalMinor,
    required this.type,
    required this.color,
    required this.icon,
  });

  final String label;
  final List<String> chartLabels;
  final List<MoneyTransaction> directTransactions;
  final List<_TransactionChildGroup> childGroups;
  final int totalMinor;
  final TransactionType type;
  final Color color;
  final IconData icon;

  int get totalCount =>
      directTransactions.length +
      childGroups.fold<int>(0, (sum, group) => sum + group.transactions.length);
}

class _TransactionChildGroup {
  const _TransactionChildGroup({
    required this.label,
    required this.chartLabel,
    required this.transactions,
    required this.totalMinor,
    required this.color,
    required this.icon,
  });

  final String label;
  final String chartLabel;
  final List<MoneyTransaction> transactions;
  final int totalMinor;
  final Color color;
  final IconData icon;
}

class _TransactionPieSlice {
  const _TransactionPieSlice({required this.share, required this.color});

  final double share;
  final Color color;
}

class _TransactionPiePainter extends CustomPainter {
  const _TransactionPiePainter({required this.slices, required this.baseColor});

  final List<_TransactionPieSlice> slices;
  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28;
    final Offset center = size.center(Offset.zero);
    final double radius = math.min(size.width, size.height) / 2 - 14;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28
        ..color = baseColor.withValues(alpha: 0.10),
    );

    double startAngle = -math.pi / 2;
    for (final slice in slices) {
      final double sweepAngle = math.pi * 2 * slice.share;
      if (sweepAngle <= 0) {
        continue;
      }
      paint.color = slice.color;
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _TransactionPiePainter oldDelegate) {
    return oldDelegate.slices != slices || oldDelegate.baseColor != baseColor;
  }
}

List<_CategoryAmountRow> _categoryRowsForTransactions(
  List<MoneyTransaction> transactions,
  TransactionType type,
  List<category_domain.Category> categories,
) {
  final Map<String, category_domain.Category> categoryById = {
    for (final category in categories) category.id: category,
  };
  final Map<String, int> totals = <String, int>{};
  final Map<String, _CategoryVisualMeta> visuals =
      <String, _CategoryVisualMeta>{};
  for (final transaction in transactions) {
    if (transaction.type != type) {
      continue;
    }

    final label = _transactionCategoryLabel(transaction);
    final category = transaction.childCategoryId != null
        ? categoryById[transaction.childCategoryId!]
        : transaction.categoryId != null
        ? categoryById[transaction.categoryId!]
        : null;
    totals.update(
      label,
      (value) => value + transaction.amountMinor,
      ifAbsent: () => transaction.amountMinor,
    );
    visuals.putIfAbsent(
      label,
      () => _CategoryVisualMeta(
        color: category?.color ?? AppColors.primary,
        icon: CategoryVisuals.iconFromKey(category?.iconKey ?? 'category'),
      ),
    );
  }

  final rows =
      totals.entries
          .map(
            (entry) => _CategoryAmountRow(
              label: entry.key,
              amountMinor: entry.value,
              color: visuals[entry.key]?.color ?? AppColors.primary,
              icon: visuals[entry.key]?.icon ?? Icons.category_rounded,
            ),
          )
          .toList(growable: false)
        ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
  return rows;
}

List<_TransactionCategoryGroup> _categoryGroupsForTransactions(
  List<MoneyTransaction> transactions,
  List<category_domain.Category> categories,
) {
  final Map<String, category_domain.Category> categoryById = {
    for (final category in categories) category.id: category,
  };
  final Map<String, List<MoneyTransaction>> directByParent =
      <String, List<MoneyTransaction>>{};
  final Map<String, Map<String, List<MoneyTransaction>>> childByParent =
      <String, Map<String, List<MoneyTransaction>>>{};
  for (final transaction in transactions) {
    if (transaction.type == TransactionType.transfer) {
      continue;
    }

    final String parentLabel = transaction.categoryName ?? 'Uncategorized';
    final String? childLabel = transaction.childCategoryName;

    if (childLabel == null) {
      directByParent
          .putIfAbsent(parentLabel, () => <MoneyTransaction>[])
          .add(transaction);
      continue;
    }

    childByParent
        .putIfAbsent(parentLabel, () => <String, List<MoneyTransaction>>{})
        .putIfAbsent(childLabel, () => <MoneyTransaction>[])
        .add(transaction);
  }

  final Set<String> parentLabels = <String>{
    ...directByParent.keys,
    ...childByParent.keys,
  };

  final groups =
      parentLabels
          .map((parentLabel) {
            final List<MoneyTransaction> directItems = [
              ...?directByParent[parentLabel],
            ]..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
            final List<_TransactionChildGroup> childGroups =
                (childByParent[parentLabel] ??
                        <String, List<MoneyTransaction>>{})
                    .entries
                    .map((entry) {
                      final items = [...entry.value]
                        ..sort(
                          (a, b) =>
                              b.transactionDate.compareTo(a.transactionDate),
                        );
                      final total = items.fold<int>(
                        0,
                        (sum, transaction) => sum + transaction.amountMinor,
                      );
                      final category_domain.Category? childCategory =
                          items.first.childCategoryId != null
                          ? categoryById[items.first.childCategoryId!]
                          : null;
                      final category_domain.Category? parentCategory =
                          items.first.categoryId != null
                          ? categoryById[items.first.categoryId!]
                          : null;
                      return _TransactionChildGroup(
                        label: entry.key,
                        chartLabel: '$parentLabel > ${entry.key}',
                        transactions: items,
                        totalMinor: total,
                        color:
                            childCategory?.color ??
                            parentCategory?.color ??
                            AppColors.primary,
                        icon: CategoryVisuals.iconFromKey(
                          childCategory?.iconKey ??
                              parentCategory?.iconKey ??
                              'category',
                        ),
                      );
                    })
                    .toList(growable: false)
                  ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));

            final int totalMinor =
                directItems.fold<int>(
                  0,
                  (sum, transaction) => sum + transaction.amountMinor,
                ) +
                childGroups.fold<int>(
                  0,
                  (sum, group) => sum + group.totalMinor,
                );
            final MoneyTransaction sample = directItems.isNotEmpty
                ? directItems.first
                : childGroups.first.transactions.first;

            category_domain.Category? parentCategory;
            if (directItems.isNotEmpty &&
                directItems.first.categoryId != null) {
              parentCategory = categoryById[directItems.first.categoryId!];
            } else if (childGroups.isNotEmpty) {
              final MoneyTransaction firstChildTransaction =
                  childGroups.first.transactions.first;
              final String? parentCategoryId = firstChildTransaction.categoryId;
              if (parentCategoryId != null) {
                parentCategory = categoryById[parentCategoryId];
              }
            }
            return _TransactionCategoryGroup(
              label: parentLabel,
              chartLabels: <String>[
                if (directItems.isNotEmpty) parentLabel,
                ...childGroups.map((group) => group.chartLabel),
              ],
              directTransactions: directItems,
              childGroups: childGroups,
              totalMinor: totalMinor,
              type: sample.type,
              color: parentCategory?.color ?? AppColors.primary,
              icon: CategoryVisuals.iconFromKey(
                parentCategory?.iconKey ?? 'category',
              ),
            );
          })
          .toList(growable: false)
        ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
  return groups;
}

List<_TransactionPieSlice> _buildPieSlices(List<_CategoryAmountRow> rows) {
  final int total = rows.fold<int>(0, (sum, row) => sum + row.amountMinor);
  final List<_CategoryAmountRow> ranked = [...rows]
    ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
  final List<_CategoryAmountRow> visible = ranked
      .take(5)
      .toList(growable: false);
  final List<_TransactionPieSlice> slices = <_TransactionPieSlice>[];

  for (int index = 0; index < visible.length; index += 1) {
    final _CategoryAmountRow row = visible[index];
    slices.add(
      _TransactionPieSlice(
        share: total == 0 ? 0 : row.amountMinor / total,
        color: row.color,
      ),
    );
  }

  final int remaining = ranked
      .skip(5)
      .fold<int>(0, (sum, row) => sum + row.amountMinor);
  if (remaining > 0) {
    slices.add(
      _TransactionPieSlice(
        share: total == 0 ? 0 : remaining / total,
        color: AppColors.lightMint,
      ),
    );
  }

  return slices;
}

String _transactionCategoryLabel(MoneyTransaction transaction) {
  final String? parentName = transaction.categoryName;
  final String? childName = transaction.childCategoryName;

  if (parentName != null && childName != null) {
    return '$parentName > $childName';
  }

  return childName ?? parentName ?? 'Uncategorized';
}

class _EmptyTransactionsState extends StatelessWidget {
  const _EmptyTransactionsState({required this.mode, required this.onCreate});

  final TransactionListMode mode;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final bool archivedOnly = mode == TransactionListMode.archived;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
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
              archivedOnly ? 'No archived transactions' : 'No transactions yet',
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
                    AppDateFormatter.format(transaction.transactionDate),
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
    return _transactionCategoryLabel(transaction);
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

          final account_domain.Account? defaultAccount = accounts
              .where((account) => account.isDefault)
              .cast<account_domain.Account?>()
              .fold<account_domain.Account?>(
                null,
                (selected, account) => selected ?? account,
              );
          _selectedAccountId ??= defaultAccount?.id ?? accounts.first.id;
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
                        Text(AppDateFormatter.format(_selectedDate)),
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
                      final selectedOption = _findCategoryOption(
                        categoryOptions,
                        selectedCategoryPickerId,
                      );

                      return _CategoryPickerField(
                        selectedLabel: selectedOption?.label,
                        isChild: selectedOption?.isChild ?? false,
                        onTap: () async {
                          final String? pickedId =
                              await showModalBottomSheet<String?>(
                                context: context,
                                isScrollControlled: true,
                                showDragHandle: true,
                                builder: (context) => _CategoryPickerSheet(
                                  options: categoryOptions,
                                  selectedCategoryId: selectedCategoryPickerId,
                                ),
                              );

                          if (!mounted) {
                            return;
                          }

                          final selectedCategory = _findCategoryOption(
                            categoryOptions,
                            pickedId,
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

class _CategoryPickerParentGroup {
  const _CategoryPickerParentGroup({
    required this.parent,
    required this.children,
  });

  final _CategoryPickerOption parent;
  final List<_CategoryPickerOption> children;
}

List<_CategoryPickerParentGroup> _groupCategoryPickerOptions(
  List<_CategoryPickerOption> options,
  String query,
) {
  final List<_CategoryPickerOption> parents = options
      .where((option) => !option.isChild)
      .toList(growable: false);
  final List<_CategoryPickerParentGroup> groups =
      <_CategoryPickerParentGroup>[];

  for (final parent in parents) {
    final List<_CategoryPickerOption> children = options
        .where(
          (option) =>
              option.isChild && option.category.parentId == parent.category.id,
        )
        .toList(growable: false);

    final bool parentMatches =
        query.isEmpty || parent.label.toLowerCase().contains(query);
    final List<_CategoryPickerOption> matchingChildren = children
        .where(
          (child) => query.isEmpty || child.label.toLowerCase().contains(query),
        )
        .toList(growable: false);

    if (!parentMatches && matchingChildren.isEmpty) {
      continue;
    }

    groups.add(
      _CategoryPickerParentGroup(
        parent: parent,
        children: parentMatches ? children : matchingChildren,
      ),
    );
  }

  return groups;
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
