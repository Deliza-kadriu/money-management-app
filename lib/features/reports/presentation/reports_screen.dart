import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/core/services/excel_export_service.dart';
import 'package:money_manager/core/utils/currency_formatter.dart';
import 'package:money_manager/domain/entities/account.dart';
import 'package:money_manager/domain/entities/category.dart' as category_domain;
import 'package:money_manager/domain/entities/money_transaction.dart';
import 'package:money_manager/domain/enums/category_type.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/shared/providers/app_providers.dart';
import 'package:money_manager/shared/widgets/summary_card.dart';
import 'package:money_manager/app/theme/app_colors.dart';
import 'package:money_manager/shared/widgets/app_filter_chips.dart';
import 'package:share_plus/share_plus.dart';

enum ReportPeriod { thisMonth, last30Days, allTime, custom }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final TextEditingController _minAmountController = TextEditingController();
  final TextEditingController _maxAmountController = TextEditingController();
  bool _showFilters = false;
  ReportPeriod _period = ReportPeriod.thisMonth;
  TransactionType? _typeFilter;
  String? _accountFilter;
  String? _categoryFilter;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _isExporting = false;

  @override
  void dispose() {
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsProvider(false));
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final List<MoneyTransaction>? transactions = transactionsAsync.valueOrNull;
    final List<Account>? accounts = accountsAsync.valueOrNull;
    final List<category_domain.Category>? categories =
        categoriesAsync.valueOrNull;
    final Widget body;

    if (transactions != null && accounts != null && categories != null) {
      final List<_CategoryPickerOption> categoryOptions =
          _categoryOptionsForFilter(categories);
      final String? effectiveAccountFilter = _resolveAccountFilter(accounts);
      final String? effectiveCategoryFilter = _resolveCategoryFilter(
        categoryOptions,
      );

      _syncFilterSelections(
        effectiveAccountFilter: effectiveAccountFilter,
        effectiveCategoryFilter: effectiveCategoryFilter,
      );

      body = _ReportBody(
        snapshot: _buildSnapshot(
          transactions: transactions,
          accounts: accounts,
          categories: categories,
          period: _period,
        ),
        accounts: accounts,
        categories: categories,
        period: _period,
        onPeriodChanged: (period) {
          setState(() {
            _period = period;
          });
        },
        typeFilter: _typeFilter,
        accountFilter: effectiveAccountFilter,
        categoryFilter: effectiveCategoryFilter,
        minAmountController: _minAmountController,
        maxAmountController: _maxAmountController,
        customStartDate: _customStartDate,
        customEndDate: _customEndDate,
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
        onAmountChanged: () {
          setState(() {});
        },
        onPickCustomRange: _pickCustomDateRange,
        onClearCustomRange: () {
          setState(() {
            _customStartDate = null;
            _customEndDate = null;
            _period = ReportPeriod.allTime;
          });
        },
        onResetFilters: _resetFilters,
        hasActiveFilters: _hasActiveFilters,
        categoryOptions: categoryOptions,
        showFilters: _showFilters,
        onToggleFilters: () {
          setState(() {
            _showFilters = !_showFilters;
          });
        },
      );
    } else if (transactionsAsync case AsyncError(:final error)) {
      body = _ReportError(error: error);
    } else if (accountsAsync case AsyncError(:final error)) {
      body = _ReportError(error: error);
    } else if (categoriesAsync case AsyncError(:final error)) {
      body = _ReportError(error: error);
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: <Widget>[
          IconButton(
            onPressed: _isExporting
                ? null
                : () => _exportCurrentReport(
                    context,
                    transactionsAsync,
                    accountsAsync,
                    categoriesAsync,
                  ),
            icon: Icon(
              _isExporting
                  ? Icons.hourglass_top_rounded
                  : Icons.ios_share_rounded,
            ),
            tooltip: 'Export report',
          ),
        ],
      ),
      body: body,
    );
  }

  Future<void> _exportCurrentReport(
    BuildContext context,
    AsyncValue<List<MoneyTransaction>> transactionsAsync,
    AsyncValue<List<Account>> accountsAsync,
    AsyncValue<List<category_domain.Category>> categoriesAsync,
  ) async {
    final List<MoneyTransaction>? transactions = transactionsAsync.valueOrNull;
    final List<Account>? accounts = accountsAsync.valueOrNull;
    final List<category_domain.Category>? categories =
        categoriesAsync.valueOrNull;
    if (transactions == null || accounts == null || categories == null) {
      return;
    }

    final _ReportSnapshot snapshot = _buildSnapshot(
      transactions: transactions,
      accounts: accounts,
      categories: categories,
      period: _period,
    );

    setState(() {
      _isExporting = true;
    });

    try {
      final exportService = ref.read(excelExportServiceProvider);
      final String filePath = await exportService.exportReport(
        periodLabel: _periodLabel(_period),
        incomeMinor: snapshot.incomeMinor,
        expenseMinor: snapshot.expenseMinor,
        netMinor: snapshot.netMinor,
        categoryRows: snapshot.categoryRows
            .map(
              (row) => ExportCategoryRow(
                label: row.label,
                amountMinor: row.amountMinor,
              ),
            )
            .toList(growable: false),
        accountRows: snapshot.accountRows
            .map(
              (row) => ExportAccountRow(
                name: row.name,
                balanceMinor: row.balanceMinor,
              ),
            )
            .toList(growable: false),
        transactionRows: snapshot.transactions
            .map(
              (transaction) => ExportTransactionRow(
                dateLabel: _dateLabel(transaction.transactionDate),
                typeLabel: _typeLabel(transaction.type),
                accountName: transaction.accountName,
                destinationAccountName: transaction.destinationAccountName,
                categoryName: transaction.categoryName,
                childCategoryName: transaction.childCategoryName,
                amountMinor: transaction.amountMinor,
                note: transaction.note,
              ),
            )
            .toList(growable: false),
      );

      if (context.mounted) {
        await SharePlus.instance.share(
          ShareParams(
            text: 'Money Manager report: ${_periodLabel(_period)}',
            files: <XFile>[XFile(filePath)],
          ),
        );

        if (!context.mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel report is ready to share.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  _ReportSnapshot _buildSnapshot({
    required List<MoneyTransaction> transactions,
    required List<Account> accounts,
    required List<category_domain.Category> categories,
    required ReportPeriod period,
  }) {
    final List<MoneyTransaction> filteredTransactions = _filterTransactions(
      transactions: transactions,
      period: period,
    );

    int incomeMinor = 0;
    int expenseMinor = 0;
    final Map<String, int> categorySpendMap = <String, int>{};

    for (final tx in filteredTransactions) {
      switch (tx.type) {
        case TransactionType.income:
          incomeMinor += tx.amountMinor;
          break;
        case TransactionType.expense:
          expenseMinor += tx.amountMinor;
          final String label = _transactionCategoryLabel(tx);
          categorySpendMap.update(
            label,
            (value) => value + tx.amountMinor,
            ifAbsent: () => tx.amountMinor,
          );
          break;
        case TransactionType.transfer:
          break;
      }
    }

    final categoryRows =
        categorySpendMap.entries
            .map(
              (entry) =>
                  _CategoryRow(label: entry.key, amountMinor: entry.value),
            )
            .toList(growable: false)
          ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

    final accountRows =
        accounts
            .map(
              (account) => _AccountBalanceRow(
                name: account.name,
                balanceMinor: account.currentBalanceMinor,
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.balanceMinor.compareTo(a.balanceMinor));

    return _ReportSnapshot(
      transactions: filteredTransactions,
      incomeMinor: incomeMinor,
      expenseMinor: expenseMinor,
      netMinor: incomeMinor - expenseMinor,
      categoryRows: categoryRows,
      accountRows: accountRows,
      categoryOptions: _categoryOptionsForFilter(categories),
    );
  }

  String _periodLabel(ReportPeriod period) {
    switch (period) {
      case ReportPeriod.thisMonth:
        return 'This month';
      case ReportPeriod.last30Days:
        return 'Last 30 days';
      case ReportPeriod.allTime:
        return 'All time';
      case ReportPeriod.custom:
        return 'Custom range';
    }
  }

  String _typeLabel(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.income:
        return 'Income';
      case TransactionType.transfer:
        return 'Transfer';
    }
  }

  String _dateLabel(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  List<MoneyTransaction> _filterTransactions({
    required List<MoneyTransaction> transactions,
    required ReportPeriod period,
  }) {
    final DateTime now = DateTime.now();
    final int? minAmountMinor = _parseAmountFilter(_minAmountController.text);
    final int? maxAmountMinor = _parseAmountFilter(_maxAmountController.text);

    return transactions
        .where((tx) {
          switch (period) {
            case ReportPeriod.thisMonth:
              final bool sameMonth =
                  tx.transactionDate.year == now.year &&
                  tx.transactionDate.month == now.month;
              if (!sameMonth) {
                return false;
              }
              break;
            case ReportPeriod.last30Days:
              if (tx.transactionDate.isBefore(
                now.subtract(const Duration(days: 30)),
              )) {
                return false;
              }
              break;
            case ReportPeriod.allTime:
              break;
            case ReportPeriod.custom:
              if (_customStartDate != null &&
                  tx.transactionDate.isBefore(_startOfDay(_customStartDate!))) {
                return false;
              }
              if (_customEndDate != null &&
                  tx.transactionDate.isAfter(_endOfDay(_customEndDate!))) {
                return false;
              }
              break;
          }

          if (_typeFilter != null && tx.type != _typeFilter) {
            return false;
          }

          if (_accountFilter != null &&
              tx.accountId != _accountFilter &&
              tx.destinationAccountId != _accountFilter) {
            return false;
          }

          if (_categoryFilter != null &&
              !_matchesCategoryFilter(tx, _categoryFilter!)) {
            return false;
          }

          if (minAmountMinor != null && tx.amountMinor < minAmountMinor) {
            return false;
          }

          if (maxAmountMinor != null && tx.amountMinor > maxAmountMinor) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  bool get _hasActiveFilters {
    return _period != ReportPeriod.thisMonth ||
        _typeFilter != null ||
        _accountFilter != null ||
        _categoryFilter != null ||
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

  String? _resolveAccountFilter(List<Account> accounts) {
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
            return true;
          }

          return category.type == _categoryTypeForTransaction(_typeFilter!) ||
              category.type == CategoryType.both;
        })
        .toList(growable: false);

    final parents =
        filteredCategories
            .where((category) => category.isParent)
            .toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name));

    final List<_CategoryPickerOption> options = <_CategoryPickerOption>[];
    for (final parent in parents) {
      options.add(
        _CategoryPickerOption(
          category: parent,
          label: parent.name,
          isChild: false,
        ),
      );

      final children =
          filteredCategories
              .where((category) => category.parentId == parent.id)
              .toList(growable: false)
            ..sort((a, b) => a.name.compareTo(b.name));

      for (final child in children) {
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
      _period = ReportPeriod.custom;
    });
  }

  void _resetFilters() {
    setState(() {
      _showFilters = false;
      _period = ReportPeriod.thisMonth;
      _typeFilter = null;
      _accountFilter = null;
      _categoryFilter = null;
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
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.snapshot,
    required this.accounts,
    required this.categories,
    required this.period,
    required this.onPeriodChanged,
    required this.typeFilter,
    required this.accountFilter,
    required this.categoryFilter,
    required this.minAmountController,
    required this.maxAmountController,
    required this.customStartDate,
    required this.customEndDate,
    required this.onTypeChanged,
    required this.onAccountChanged,
    required this.onCategoryChanged,
    required this.onAmountChanged,
    required this.onPickCustomRange,
    required this.onClearCustomRange,
    required this.onResetFilters,
    required this.hasActiveFilters,
    required this.categoryOptions,
    required this.showFilters,
    required this.onToggleFilters,
  });

  final _ReportSnapshot snapshot;
  final List<Account> accounts;
  final List<category_domain.Category> categories;
  final ReportPeriod period;
  final ValueChanged<ReportPeriod> onPeriodChanged;
  final TransactionType? typeFilter;
  final String? accountFilter;
  final String? categoryFilter;
  final TextEditingController minAmountController;
  final TextEditingController maxAmountController;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final ValueChanged<TransactionType?> onTypeChanged;
  final ValueChanged<String?> onAccountChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onAmountChanged;
  final Future<void> Function() onPickCustomRange;
  final VoidCallback onClearCustomRange;
  final VoidCallback onResetFilters;
  final bool hasActiveFilters;
  final List<_CategoryPickerOption> categoryOptions;
  final bool showFilters;
  final VoidCallback onToggleFilters;

  @override
  Widget build(BuildContext context) {
    final List<Account> sortedAccounts = [...accounts]
      ..sort((a, b) => b.currentBalanceMinor.compareTo(a.currentBalanceMinor));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: AppFilterChips<ReportPeriod>(
                selected: period,
                onChanged: onPeriodChanged,
                items: const <AppFilterChipItem<ReportPeriod>>[
                  AppFilterChipItem<ReportPeriod>(
                    value: ReportPeriod.thisMonth,
                    label: 'This month',
                  ),
                  AppFilterChipItem<ReportPeriod>(
                    value: ReportPeriod.last30Days,
                    label: 'Last 30 days',
                  ),
                  AppFilterChipItem<ReportPeriod>(
                    value: ReportPeriod.allTime,
                    label: 'All time',
                  ),
                  AppFilterChipItem<ReportPeriod>(
                    value: ReportPeriod.custom,
                    label: 'Custom',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onToggleFilters,
              icon: Icon(
                showFilters
                    ? Icons.filter_alt_off_rounded
                    : Icons.filter_alt_rounded,
              ),
              label: Text(showFilters ? 'Hide filters' : 'Filters'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (showFilters)
          Card(
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
                          key: ValueKey<String>('report-type-$typeFilter'),
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
                            'report-account-${accountFilter ?? 'all'}-${accounts.length}',
                          ),
                          initialValue: accountFilter,
                          decoration: const InputDecoration(
                            labelText: 'Account',
                          ),
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
                      'report-category-${categoryFilter ?? 'all'}-${categoryOptions.length}-$typeFilter',
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
                          decoration: const InputDecoration(
                            labelText: 'Min amount',
                          ),
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
                          decoration: const InputDecoration(
                            labelText: 'Max amount',
                          ),
                          onChanged: (_) => onAmountChanged(),
                        ),
                      ),
                    ],
                  ),
                  if (period == ReportPeriod.custom) ...<Widget>[
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
          ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Overview',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: SummaryCard(
                        label: 'Income',
                        amountLabel: CurrencyFormatter.formatMinorUnits(
                          snapshot.incomeMinor,
                        ),
                        accentColor: AppColors.positive,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SummaryCard(
                        label: 'Expense',
                        amountLabel: CurrencyFormatter.formatMinorUnits(
                          snapshot.expenseMinor,
                        ),
                        accentColor: AppColors.negative,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SummaryCard(
                  label: 'Net',
                  amountLabel: CurrencyFormatter.formatMinorUnits(
                    snapshot.netMinor,
                  ),
                  accentColor: snapshot.netMinor >= 0
                      ? AppColors.primary
                      : AppColors.negative,
                ),
                const SizedBox(height: 12),
                Text(
                  '${snapshot.transactions.length} transaction(s) in this view',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Category breakdown',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (snapshot.categoryRows.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No expense categories in this period yet.'),
            ),
          ),
        ...snapshot.categoryRows
            .take(8)
            .map(
              (entry) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(entry.label),
                  trailing: Text(
                    CurrencyFormatter.formatMinorUnits(entry.amountMinor),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
        const SizedBox(height: 20),
        Text('Account balances', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ...sortedAccounts.map(
          (account) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(account.name),
              subtitle: Text(account.type.name),
              trailing: Text(
                CurrencyFormatter.formatMinorUnits(account.currentBalanceMinor),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _ReportError extends StatelessWidget {
  const _ReportError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Failed to load reports.\n$error'),
      ),
    );
  }
}

class _ReportSnapshot {
  const _ReportSnapshot({
    required this.transactions,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.netMinor,
    required this.categoryRows,
    required this.accountRows,
    required this.categoryOptions,
  });

  final List<MoneyTransaction> transactions;
  final int incomeMinor;
  final int expenseMinor;
  final int netMinor;
  final List<_CategoryRow> categoryRows;
  final List<_AccountBalanceRow> accountRows;
  final List<_CategoryPickerOption> categoryOptions;
}

class _CategoryRow {
  const _CategoryRow({required this.label, required this.amountMinor});

  final String label;
  final int amountMinor;
}

String _transactionCategoryLabel(MoneyTransaction transaction) {
  final String? parentName = transaction.categoryName;
  final String? childName = transaction.childCategoryName;

  if (parentName != null && childName != null) {
    return '$parentName > $childName';
  }

  return childName ?? parentName ?? 'Uncategorized';
}

class _AccountBalanceRow {
  const _AccountBalanceRow({required this.name, required this.balanceMinor});

  final String name;
  final int balanceMinor;
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
