enum LoanStatus {
  active,
  closed;

  String get label {
    switch (this) {
      case LoanStatus.active:
        return 'Active';
      case LoanStatus.closed:
        return 'Closed';
    }
  }
}
