import 'package:drift/drift.dart';
import 'package:money_manager/data/local/db/app_database.dart' as db;
import 'package:money_manager/domain/entities/recurring_rule.dart' as domain;
import 'package:money_manager/domain/enums/recurring_frequency.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/domain/repositories/recurring_rule_repository.dart';
import 'package:uuid/uuid.dart';

class RecurringRuleRepositoryImpl implements RecurringRuleRepository {
  RecurringRuleRepositoryImpl(this._database);

  final db.AppDatabase _database;
  final Uuid _uuid = const Uuid();

  @override
  Stream<List<domain.RecurringRule>> watchRecurringRules({
    bool archivedOnly = false,
  }) {
    final query = _database.select(_database.recurringRules)
      ..where(
        (tbl) =>
            archivedOnly ? tbl.deletedAt.isNotNull() : tbl.deletedAt.isNull(),
      )
      ..orderBy(<OrderingTerm Function(db.$RecurringRulesTable)>[
        (tbl) => OrderingTerm.asc(tbl.nextDueDate),
        (tbl) => OrderingTerm.asc(tbl.title),
      ]);

    return query.watch().asyncMap(_mapRuleRows);
  }

  @override
  Future<List<domain.RecurringRule>> getRecurringRules({
    bool archivedOnly = false,
  }) async {
    final query = _database.select(_database.recurringRules)
      ..where(
        (tbl) =>
            archivedOnly ? tbl.deletedAt.isNotNull() : tbl.deletedAt.isNull(),
      )
      ..orderBy(<OrderingTerm Function(db.$RecurringRulesTable)>[
        (tbl) => OrderingTerm.asc(tbl.nextDueDate),
        (tbl) => OrderingTerm.asc(tbl.title),
      ]);
    final rows = await query.get();
    return _mapRuleRows(rows);
  }

  @override
  Future<String> createRecurringRule(CreateRecurringRuleInput input) async {
    final DateTime now = DateTime.now();
    final String id = _uuid.v4();

    await _database
        .into(_database.recurringRules)
        .insert(
          db.RecurringRulesCompanion.insert(
            id: id,
            title: input.title.trim(),
            type: input.type.name,
            frequency: input.frequency.name,
            intervalCount: Value(input.intervalCount),
            accountId: input.accountId,
            destinationAccountId: Value(input.destinationAccountId),
            categoryId: Value(input.categoryId),
            childCategoryId: Value(input.childCategoryId),
            amountMinor: input.amountMinor,
            note: Value(input.note.trim()),
            startDate: input.startDate,
            endDate: Value(input.endDate),
            nextDueDate: input.nextDueDate,
            reminderDaysBefore: Value(input.reminderDaysBefore),
            autoCreate: Value(input.autoCreate),
            isActive: const Value(true),
            lastGeneratedAt: const Value.absent(),
            createdAt: now,
            updatedAt: now,
          ),
        );

    return id;
  }

  @override
  Future<void> updateRecurringRule(
    String id,
    UpdateRecurringRuleInput input,
  ) async {
    final DateTime now = DateTime.now();

    await (_database.update(
      _database.recurringRules,
    )..where((tbl) => tbl.id.equals(id))).write(
      db.RecurringRulesCompanion(
        title: Value(input.title.trim()),
        type: Value(input.type.name),
        frequency: Value(input.frequency.name),
        intervalCount: Value(input.intervalCount),
        accountId: Value(input.accountId),
        destinationAccountId: Value(input.destinationAccountId),
        categoryId: Value(input.categoryId),
        childCategoryId: Value(input.childCategoryId),
        amountMinor: Value(input.amountMinor),
        note: Value(input.note.trim()),
        startDate: Value(input.startDate),
        endDate: Value(input.endDate),
        nextDueDate: Value(input.nextDueDate),
        reminderDaysBefore: Value(input.reminderDaysBefore),
        autoCreate: Value(input.autoCreate),
        isActive: Value(input.isActive),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> softDeleteRecurringRule(String id) async {
    final DateTime now = DateTime.now();

    await (_database.update(
      _database.recurringRules,
    )..where((tbl) => tbl.id.equals(id))).write(
      db.RecurringRulesCompanion(
        isActive: const Value(false),
        updatedAt: Value(now),
        deletedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> restoreRecurringRule(String id) async {
    final DateTime now = DateTime.now();

    await (_database.update(
      _database.recurringRules,
    )..where((tbl) => tbl.id.equals(id))).write(
      db.RecurringRulesCompanion(
        isActive: const Value(true),
        updatedAt: Value(now),
        deletedAt: const Value(null),
      ),
    );
  }

  Future<List<domain.RecurringRule>> _mapRuleRows(
    List<db.RecurringRule> rows,
  ) async {
    final accountRows = await _database.select(_database.accounts).get();
    final categoryRows = await _database.select(_database.categories).get();

    final accountsById = <String, db.Account>{
      for (final account in accountRows) account.id: account,
    };
    final categoriesById = <String, db.Category>{
      for (final category in categoryRows) category.id: category,
    };

    return rows
        .map((row) {
          final type = TransactionType.values.firstWhere(
            (value) => value.name == row.type,
            orElse: () => TransactionType.expense,
          );
          final frequency = RecurringFrequency.values.firstWhere(
            (value) => value.name == row.frequency,
            orElse: () => RecurringFrequency.monthly,
          );
          final category = row.categoryId == null
              ? null
              : categoriesById[row.categoryId!];
          final childCategory = row.childCategoryId == null
              ? null
              : categoriesById[row.childCategoryId!];

          return domain.RecurringRule(
            id: row.id,
            title: row.title,
            type: type,
            frequency: frequency,
            intervalCount: row.intervalCount,
            accountId: row.accountId,
            accountName: accountsById[row.accountId]?.name ?? 'Unknown account',
            destinationAccountId: row.destinationAccountId,
            destinationAccountName: row.destinationAccountId == null
                ? null
                : accountsById[row.destinationAccountId!]?.name,
            categoryId: row.categoryId,
            categoryName: category?.name,
            childCategoryId: row.childCategoryId,
            childCategoryName: childCategory?.name,
            amountMinor: row.amountMinor,
            note: row.note,
            startDate: row.startDate,
            endDate: row.endDate,
            nextDueDate: row.nextDueDate,
            reminderDaysBefore: row.reminderDaysBefore,
            autoCreate: row.autoCreate,
            isActive: row.isActive,
            deletedAt: row.deletedAt,
          );
        })
        .toList(growable: false);
  }
}
