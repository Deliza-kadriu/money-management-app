import 'package:money_manager/domain/enums/loan_status.dart';
import 'package:money_manager/domain/enums/loan_type.dart';

class Loan {
  const Loan({
    required this.id,
    required this.loanName,
    required this.loanType,
    required this.bankName,
    required this.accountId,
    required this.categoryId,
    required this.childCategoryId,
    required this.totalAmountMinor,
    required this.interestRate,
    required this.startDate,
    required this.endDate,
    required this.numberOfInstallments,
    required this.monthlyPaymentMinor,
    required this.remainingBalanceMinor,
    required this.paidInstallments,
    required this.status,
    required this.remindersEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String loanName;
  final LoanType loanType;
  final String bankName;
  final String? accountId;
  final String? categoryId;
  final String? childCategoryId;
  final int totalAmountMinor;
  final double interestRate;
  final DateTime startDate;
  final DateTime endDate;
  final int numberOfInstallments;
  final int monthlyPaymentMinor;
  final int remainingBalanceMinor;
  final int paidInstallments;
  final LoanStatus status;
  final bool remindersEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get paidAmountMinor => totalAmountMinor - remainingBalanceMinor;

  int get remainingInstallments => numberOfInstallments - paidInstallments;

  double get progressPercent {
    if (numberOfInstallments <= 0) {
      return 0;
    }
    return (paidInstallments / numberOfInstallments).clamp(0, 1);
  }
}
