import 'package:drift/drift.dart';

class LoanInstallments extends Table {
  TextColumn get id => text()();

  TextColumn get loanId => text()();

  IntColumn get installmentNumber => integer()();

  DateTimeColumn get dueDate => dateTime()();

  IntColumn get amountMinor => integer()();

  IntColumn get principalAmountMinor => integer()();

  IntColumn get interestAmountMinor => integer()();

  IntColumn get remainingBalanceMinor => integer()();

  TextColumn get status => text()();

  DateTimeColumn get paidDate => dateTime().nullable()();

  TextColumn get transactionId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
