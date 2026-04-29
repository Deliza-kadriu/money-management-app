import 'package:drift/drift.dart';

class Loans extends Table {
  TextColumn get id => text()();

  TextColumn get loanName => text()();

  TextColumn get loanType => text()();

  TextColumn get bankName => text()();

  TextColumn get accountId => text().nullable()();

  TextColumn get categoryId => text().nullable()();

  TextColumn get childCategoryId => text().nullable()();

  IntColumn get totalAmountMinor => integer()();

  RealColumn get interestRate => real()();

  DateTimeColumn get startDate => dateTime()();

  DateTimeColumn get endDate => dateTime()();

  IntColumn get numberOfInstallments => integer()();

  IntColumn get monthlyPaymentMinor => integer()();

  IntColumn get remainingBalanceMinor => integer()();

  IntColumn get paidInstallments => integer().withDefault(const Constant(0))();

  TextColumn get status => text()();

  BoolColumn get remindersEnabled =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
