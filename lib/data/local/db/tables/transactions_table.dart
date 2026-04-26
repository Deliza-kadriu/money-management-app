import 'package:drift/drift.dart';

class Transactions extends Table {
  TextColumn get id => text()();

  TextColumn get type => text()();

  TextColumn get accountId => text()();

  TextColumn get destinationAccountId => text().nullable()();

  IntColumn get amountMinor => integer()();

  DateTimeColumn get transactionDate => dateTime()();

  TextColumn get categoryId => text().nullable()();

  TextColumn get childCategoryId => text().nullable()();

  TextColumn get note => text().withDefault(const Constant(''))();

  TextColumn get recurringRuleId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
