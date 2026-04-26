class DashboardSummary {
  const DashboardSummary({
    required this.totalBalanceMinor,
    required this.monthIncomeMinor,
    required this.monthExpenseMinor,
    required this.activeAccountsCount,
  });

  final int totalBalanceMinor;
  final int monthIncomeMinor;
  final int monthExpenseMinor;
  final int activeAccountsCount;
}
