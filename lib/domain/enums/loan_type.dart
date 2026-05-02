enum LoanType {
  housing,
  personal,
  car,
  other;

  String get label {
    switch (this) {
      case LoanType.housing:
        return 'Housing loan';
      case LoanType.personal:
        return 'Personal loan';
      case LoanType.car:
        return 'Car loan';
      case LoanType.other:
        return 'Other loan';
    }
  }
}
