import 'package:money_manager/domain/enums/loan_installment_status.dart';

class LoanInstallment {
  const LoanInstallment({
    required this.id,
    required this.loanId,
    required this.installmentNumber,
    required this.dueDate,
    required this.amountMinor,
    required this.principalAmountMinor,
    required this.interestAmountMinor,
    required this.remainingBalanceMinor,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.paidDate,
    this.transactionId,
  });

  final String id;
  final String loanId;
  final int installmentNumber;
  final DateTime dueDate;
  final int amountMinor;
  final int principalAmountMinor;
  final int interestAmountMinor;
  final int remainingBalanceMinor;
  final LoanInstallmentStatus status;
  final DateTime? paidDate;
  final String? transactionId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPaid => status == LoanInstallmentStatus.paid;
}
