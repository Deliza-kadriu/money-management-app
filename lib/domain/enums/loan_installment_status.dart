enum LoanInstallmentStatus {
  paid,
  unpaid;

  String get label {
    switch (this) {
      case LoanInstallmentStatus.paid:
        return 'Paid';
      case LoanInstallmentStatus.unpaid:
        return 'Unpaid';
    }
  }
}
