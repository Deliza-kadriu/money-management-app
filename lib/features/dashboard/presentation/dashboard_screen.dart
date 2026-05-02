import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:money_manager/app/theme/app_colors.dart';
import 'package:money_manager/core/constants/app_strings.dart';
import 'package:money_manager/core/utils/currency_formatter.dart';
import 'package:money_manager/core/utils/date_formatter.dart';
import 'package:money_manager/domain/entities/loan.dart';
import 'package:money_manager/domain/entities/money_transaction.dart';
import 'package:money_manager/domain/enums/loan_status.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/shared/providers/app_providers.dart';
import 'package:money_manager/shared/widgets/summary_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final recentTransactionsAsync = ref.watch(recentTransactionsProvider);
    final loansAsync = ref.watch(loansProvider);
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
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
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).cardColor,
                      foregroundColor: isDark
                          ? AppColors.textLight
                          : AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.appSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.mutedLight
                      : AppColors.textDark.withValues(alpha: 0.68),
                ),
              ),
              const SizedBox(height: 16),
              summaryAsync.when(
                data: (summary) => _BalanceCard(
                  amountLabel: CurrencyFormatter.formatMinorUnits(
                    summary.totalBalanceMinor,
                  ),
                  accountCount: summary.activeAccountsCount,
                ),
                loading: () => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                ),
                error: (error, stackTrace) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Dashboard summary unavailable.\n$error'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
                    const SizedBox(width: 10),
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
              const SizedBox(height: 16),
              loansAsync.when(
                data: (loans) {
                  Loan? activeLoan;
                  for (final loan in loans) {
                    if (loan.status == LoanStatus.active) {
                      activeLoan = loan;
                      break;
                    }
                  }

                  if (activeLoan == null) {
                    return const SizedBox.shrink();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _ActiveLoanCard(loan: activeLoan),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              const _SectionHeader(title: 'Quick access'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
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
                    label: 'Loans',
                    icon: Icons.home_work_rounded,
                    route: '/loans',
                  ),
                  _DashboardShortcutCard(
                    label: 'Settings',
                    icon: Icons.tune_rounded,
                    route: '/settings',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    backgroundColor: isDark
                        ? AppColors.darkElevated
                        : AppColors.lightMint,
                    foregroundColor: isDark
                        ? AppColors.textLight
                        : AppColors.primaryDark,
                    child: const Icon(Icons.event_repeat_rounded),
                  ),
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
              const SizedBox(height: 16),
              const _SectionHeader(title: 'Recent transactions'),
              const SizedBox(height: 10),
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color backgroundColor = isDark
        ? AppColors.darkCard
        : Colors.white.withValues(alpha: 0.78);
    final Color borderColor = isDark
        ? AppColors.darkBorder
        : AppColors.lightMint;

    return SizedBox(
      width: 74,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isDark ? AppColors.textLight : AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.mutedLight
                      : AppColors.textDark.withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveLoanCard extends StatelessWidget {
  const _ActiveLoanCard({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/loans/${loan.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      loan.loanName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () => context.push('/loans/${loan.id}'),
                    child: const Text('Open'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${loan.bankName} • ${loan.loanType.label}'),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: loan.progressPercent,
                minHeight: 10,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 18,
                runSpacing: 10,
                children: <Widget>[
                  _DashboardLoanMetric(
                    label: 'Monthly',
                    value: CurrencyFormatter.formatMinorUnits(
                      loan.monthlyPaymentMinor,
                    ),
                  ),
                  _DashboardLoanMetric(
                    label: 'Remaining',
                    value: CurrencyFormatter.formatMinorUnits(
                      loan.remainingBalanceMinor,
                    ),
                  ),
                  _DashboardLoanMetric(
                    label: 'Progress',
                    value:
                        '${loan.paidInstallments}/${loan.numberOfInstallments}',
                  ),
                  _DashboardLoanMetric(
                    label: 'Started',
                    value: AppDateFormatter.format(loan.startDate),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardLoanMetric extends StatelessWidget {
  const _DashboardLoanMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.amountLabel, required this.accountCount});

  final String amountLabel;
  final int accountCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color iconBackground = isDark
        ? AppColors.darkElevated
        : AppColors.cardMint;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Total balance',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      amountLabel,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Across $accountCount active accounts',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppColors.mutedLight
                          : AppColors.textDark.withValues(alpha: 0.66),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            CircleAvatar(
              radius: 26,
              backgroundColor: iconBackground,
              foregroundColor: isDark
                  ? AppColors.textLight
                  : AppColors.primaryDark,
              child: const Icon(Icons.account_balance_wallet_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
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
    final IconData icon = switch (transaction.type) {
      TransactionType.income => Icons.south_west_rounded,
      TransactionType.expense => Icons.north_east_rounded,
      TransactionType.transfer => Icons.swap_horiz_rounded,
    };
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          backgroundColor: amountColor.withValues(alpha: isDark ? 0.18 : 0.12),
          foregroundColor: amountColor,
          child: Icon(icon, size: 20),
        ),
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
