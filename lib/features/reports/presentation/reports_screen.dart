import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/core/services/excel_export_service.dart';
import 'package:money_manager/core/utils/currency_formatter.dart';
import 'package:money_manager/domain/entities/account.dart';
import 'package:money_manager/domain/entities/money_transaction.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/shared/providers/app_providers.dart';
import 'package:money_manager/shared/widgets/summary_card.dart';
import 'package:share_plus/share_plus.dart';

enum ReportPeriod { thisMonth, last30Days, allTime }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.thisMonth;
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsProvider(false));
    final accountsAsync = ref.watch(accountsProvider);

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
      body: switch ((transactionsAsync, accountsAsync)) {
        (
          AsyncData(value: final transactions),
          AsyncData(value: final accounts),
        ) =>
          _ReportBody(
            transactions: transactions,
            accounts: accounts,
            period: _period,
            onPeriodChanged: (period) {
              setState(() {
                _period = period;
              });
            },
          ),
        (AsyncError(:final error), _) => _ReportError(error: error),
        (_, AsyncError(:final error)) => _ReportError(error: error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _exportCurrentReport(
    BuildContext context,
    AsyncValue<List<MoneyTransaction>> transactionsAsync,
    AsyncValue<List<Account>> accountsAsync,
  ) async {
    final List<MoneyTransaction>? transactions = transactionsAsync.valueOrNull;
    final List<Account>? accounts = accountsAsync.valueOrNull;
    if (transactions == null || accounts == null) {
      return;
    }

    final _ReportSnapshot snapshot = _buildSnapshot(
      transactions: transactions,
      accounts: accounts,
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
    required ReportPeriod period,
  }) {
    final DateTime now = DateTime.now();
    final List<MoneyTransaction> filteredTransactions = transactions
        .where((tx) {
          switch (period) {
            case ReportPeriod.thisMonth:
              return tx.transactionDate.year == now.year &&
                  tx.transactionDate.month == now.month;
            case ReportPeriod.last30Days:
              return !tx.transactionDate.isBefore(
                now.subtract(const Duration(days: 30)),
              );
            case ReportPeriod.allTime:
              return true;
          }
        })
        .toList(growable: false);

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
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.transactions,
    required this.accounts,
    required this.period,
    required this.onPeriodChanged,
  });

  final List<MoneyTransaction> transactions;
  final List<Account> accounts;
  final ReportPeriod period;
  final ValueChanged<ReportPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final List<MoneyTransaction> filteredTransactions = transactions
        .where((tx) {
          switch (period) {
            case ReportPeriod.thisMonth:
              return tx.transactionDate.year == now.year &&
                  tx.transactionDate.month == now.month;
            case ReportPeriod.last30Days:
              return !tx.transactionDate.isBefore(
                now.subtract(const Duration(days: 30)),
              );
            case ReportPeriod.allTime:
              return true;
          }
        })
        .toList(growable: false);

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

    final int netMinor = incomeMinor - expenseMinor;
    final List<MapEntry<String, int>> categoryRows =
        categorySpendMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final List<Account> sortedAccounts = [...accounts]
      ..sort((a, b) => b.currentBalanceMinor.compareTo(a.currentBalanceMinor));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        SegmentedButton<ReportPeriod>(
          segments: const <ButtonSegment<ReportPeriod>>[
            ButtonSegment<ReportPeriod>(
              value: ReportPeriod.thisMonth,
              label: Text('This month'),
            ),
            ButtonSegment<ReportPeriod>(
              value: ReportPeriod.last30Days,
              label: Text('30 days'),
            ),
            ButtonSegment<ReportPeriod>(
              value: ReportPeriod.allTime,
              label: Text('All time'),
            ),
          ],
          selected: <ReportPeriod>{period},
          onSelectionChanged: (selection) {
            onPeriodChanged(selection.first);
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: SummaryCard(
                label: 'Income',
                amountLabel: CurrencyFormatter.formatMinorUnits(incomeMinor),
                accentColor: Colors.green.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                label: 'Expense',
                amountLabel: CurrencyFormatter.formatMinorUnits(expenseMinor),
                accentColor: Colors.red.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SummaryCard(
          label: 'Net',
          amountLabel: CurrencyFormatter.formatMinorUnits(netMinor),
          accentColor: netMinor >= 0
              ? Colors.teal.shade700
              : Colors.red.shade700,
        ),
        const SizedBox(height: 20),
        Text(
          'Category breakdown',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (categoryRows.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No expense categories in this period yet.'),
            ),
          ),
        ...categoryRows
            .take(8)
            .map(
              (entry) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(entry.key),
                  trailing: Text(
                    CurrencyFormatter.formatMinorUnits(entry.value),
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
        const SizedBox(height: 20),
        Text(
          'Transactions in period',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: const Text('Count'),
            trailing: Text('${filteredTransactions.length}'),
          ),
        ),
      ],
    );
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
  });

  final List<MoneyTransaction> transactions;
  final int incomeMinor;
  final int expenseMinor;
  final int netMinor;
  final List<_CategoryRow> categoryRows;
  final List<_AccountBalanceRow> accountRows;
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
