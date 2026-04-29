import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:money_manager/app/theme/app_colors.dart';
import 'package:money_manager/core/constants/app_strings.dart';
import 'package:money_manager/core/utils/currency_formatter.dart';
import 'package:money_manager/domain/entities/money_transaction.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/shared/providers/app_providers.dart';
import 'package:money_manager/shared/widgets/summary_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final recentTransactionsAsync = ref.watch(recentTransactionsProvider);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const <Color>[
                    AppColors.darkBackgroundTop,
                    AppColors.darkBackgroundBottom,
                  ]
                : const <Color>[
                    AppColors.dashboardTop,
                    AppColors.dashboardBottom,
                  ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      AppStrings.appName,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: 'Settings',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.appSubtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              summaryAsync.when(
                data: (summary) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Total balance',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          CurrencyFormatter.formatMinorUnits(
                            summary.totalBalanceMinor,
                          ),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Across ${summary.activeAccountsCount} active accounts',
                        ),
                      ],
                    ),
                  ),
                ),
                loading: () => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: LinearProgressIndicator(),
                  ),
                ),
                error: (error, stackTrace) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Dashboard summary unavailable.\n$error'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              summaryAsync.when(
                data: (summary) => Row(
                  children: <Widget>[
                    Expanded(
                      child: SummaryCard(
                        label: 'Income',
                        amountLabel: CurrencyFormatter.formatMinorUnits(
                          summary.monthIncomeMinor,
                        ),
                        accentColor: AppColors.positive,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SummaryCard(
                        label: 'Expenses',
                        amountLabel: CurrencyFormatter.formatMinorUnits(
                          summary.monthExpenseMinor,
                        ),
                        accentColor: AppColors.negative,
                      ),
                    ),
                  ],
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              Text(
                'Quick access',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: const <Widget>[
                  _DashboardShortcutCard(
                    label: 'Accounts',
                    icon: Icons.account_balance_wallet_rounded,
                    route: '/accounts',
                  ),
                  _DashboardShortcutCard(
                    label: 'Categories',
                    icon: Icons.category_rounded,
                    route: '/categories',
                  ),
                  _DashboardShortcutCard(
                    label: 'Recurring',
                    icon: Icons.repeat_rounded,
                    route: '/recurring',
                  ),
                  _DashboardShortcutCard(
                    label: 'Settings',
                    icon: Icons.tune_rounded,
                    route: '/settings',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: const Text('Recurring payments'),
                  subtitle: const Text(
                    'Manage subscriptions, rent, salary, and due reminders.',
                  ),
                  trailing: FilledButton(
                    onPressed: () => context.push('/recurring'),
                    child: const Text('Open'),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Recent transactions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              recentTransactionsAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No recent transactions yet.'),
                      ),
                    );
                  }

                  return Column(
                    children: items
                        .map(
                          (item) => _RecentTransactionTile(transaction: item),
                        )
                        .toList(growable: false),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) =>
                    Text('Could not load recent transactions.\n$error'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardShortcutCard extends StatelessWidget {
  const _DashboardShortcutCard({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;

  @override
  Widget build(BuildContext context) {
    final double width = (MediaQuery.sizeOf(context).width - 44) / 2;

    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: AppColors.lightMint,
                  foregroundColor: AppColors.primaryDark,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentTransactionTile extends StatelessWidget {
  const _RecentTransactionTile({required this.transaction});

  final MoneyTransaction transaction;

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

    final String subtitle = switch (transaction.type) {
      TransactionType.transfer =>
        '${transaction.accountName} -> ${transaction.destinationAccountName ?? 'Unknown'}',
      _ =>
        '${transaction.accountName} • ${transaction.childCategoryName ?? transaction.categoryName ?? 'Uncategorized'}',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          transaction.note.isEmpty
              ? _titleFromType(transaction.type)
              : transaction.note,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: Text(
          amountLabel,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: amountColor),
        ),
      ),
    );
  }

  String _titleFromType(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.income:
        return 'Income';
      case TransactionType.transfer:
        return 'Transfer';
    }
  }
}
