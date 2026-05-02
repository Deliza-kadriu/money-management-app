import 'package:money_manager/domain/entities/loan.dart';
import 'package:money_manager/domain/entities/loan_installment.dart';

class LoanDetails {
  const LoanDetails({required this.loan, required this.installments});

  final Loan loan;
  final List<LoanInstallment> installments;

  LoanInstallment? get nextUnpaidInstallment {
    for (final installment in installments) {
      if (!installment.isPaid) {
        return installment;
      }
    }
    return null;
  }
}
