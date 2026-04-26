import 'package:drift/drift.dart';

class RecurringRules extends Table {
  TextColumn get id => text()();

  TextColumn get title => text().withLength(min: 1, max: 160)();

  TextColumn get type => text()();

  TextColumn get frequency => text()();

  IntColumn get intervalCount => integer().withDefault(const Constant(1))();

  TextColumn get accountId => text()();

  TextColumn get destinationAccountId => text().nullable()();

  TextColumn get categoryId => text().nullable()();

  TextColumn get childCategoryId => text().nullable()();

  IntColumn get amountMinor => integer()();

  TextColumn get note => text().withDefault(const Constant(''))();

  DateTimeColumn get startDate => dateTime()();

  DateTimeColumn get endDate => dateTime().nullable()();

  DateTimeColumn get nextDueDate => dateTime()();

  IntColumn get reminderDaysBefore => integer().withDefault(const Constant(0))();

  BoolColumn get autoCreate => boolean().withDefault(const Constant(false))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get lastGeneratedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
