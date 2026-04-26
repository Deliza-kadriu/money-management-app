import 'package:drift/drift.dart';

class RecurringRuleRuns extends Table {
  TextColumn get id => text()();

  TextColumn get recurringRuleId => text()();

  DateTimeColumn get scheduledFor => dateTime()();

  TextColumn get transactionId => text().nullable()();

  TextColumn get status => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
