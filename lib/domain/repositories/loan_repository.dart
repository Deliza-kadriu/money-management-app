import 'package:money_manager/domain/entities/loan.dart';
import 'package:money_manager/domain/entities/loan_details.dart';
import 'package:money_manager/domain/enums/loan_type.dart';

abstract class LoanRepository {
  Stream<List<Loan>> watchLoans();

  Stream<LoanDetails?> watchLoanDetails(String loanId);

  Future<void> createLoan(CreateLoanInput input);

  Future<void> updateLoan(String loanId, CreateLoanInput input);

  Future<void> deleteLoan(String loanId);

  Future<void> markInstallmentPaid(
    String installmentId, {
    String? accountId,
    required DateTime paidDate,
    bool createExpenseTransaction = true,
    String? note,
  });

  Future<void> undoInstallmentPayment(String installmentId);

  Future<int> processDueInstallments();
}

class CreateLoanInput {
  const CreateLoanInput({
    required this.loanName,
    required this.loanType,
    required this.bankName,
    required this.accountId,
    required this.categoryId,
    required this.childCategoryId,
    required this.totalAmountMinor,
    required this.interestRate,
    required this.startDate,
    required this.numberOfInstallments,
    this.remindersEnabled = false,
  });

  final String loanName;
  final LoanType loanType;
  final String bankName;
  final String accountId;
  final String? categoryId;
  final String? childCategoryId;
  final int totalAmountMinor;
  final double interestRate;
  final DateTime startDate;
  final int numberOfInstallments;
  final bool remindersEnabled;
}
