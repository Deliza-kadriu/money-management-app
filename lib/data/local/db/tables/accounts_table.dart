import 'package:drift/drift.dart';

class Accounts extends Table {
  TextColumn get id => text()();

  TextColumn get name => text().withLength(min: 1, max: 120)();

  TextColumn get type => text()();

  IntColumn get openingBalanceMinor => integer().withDefault(const Constant(0))();

  IntColumn get currentBalanceMinor => integer().withDefault(const Constant(0))();

  TextColumn get currencyCode =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('USD'))();

  IntColumn get colorValue => integer()();

  TextColumn get iconKey => text().withDefault(const Constant('account'))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
