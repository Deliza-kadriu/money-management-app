import 'package:drift/drift.dart';

class TransactionAttachments extends Table {
  TextColumn get id => text()();

  TextColumn get transactionId => text()();

  TextColumn get filePath => text()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
