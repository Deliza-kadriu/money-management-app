import 'package:drift/drift.dart';
import 'package:money_manager/core/services/notification_service.dart';
import 'package:money_manager/data/local/db/app_database.dart' as db;
import 'package:money_manager/domain/entities/recurring_rule_run.dart'
    as domain;
import 'package:money_manager/domain/enums/recurring_frequency.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/domain/repositories/transaction_repository.dart';
import 'package:uuid/uuid.dart';

class RecurringProcessingResult {
  const RecurringProcessingResult({
    required this.processedRulesCount,
    required this.autoCreatedCount,
    required this.suggestedCount,
  });

  final int processedRulesCount;
  final int autoCreatedCount;
  final int suggestedCount;

  bool get hasWork =>
      processedRulesCount > 0 || autoCreatedCount > 0 || suggestedCount > 0;
}

class RecurringRuleProcessor {
  RecurringRuleProcessor(
    this._database,
    this._transactionRepository,
    this._notificationService,
  );

  final db.AppDatabase _database;
  final TransactionRepository _transactionRepository;
  final NotificationService _notificationService;
  final Uuid _uuid = const Uuid();

  Stream<List<domain.RecurringRuleRun>> watchPendingSuggestions() {
    final query = _database.select(_database.recurringRuleRuns)
      ..where(
        (tbl) => tbl.status.equals('suggested') & tbl.transactionId.isNull(),
      )
      ..orderBy(<OrderingTerm Function(db.$RecurringRuleRunsTable)>[
        (tbl) => OrderingTerm.desc(tbl.scheduledFor),
      ]);

    return query.watch().asyncMap(_mapRunRows);
  }

  Future<String> approveSuggestedRun(String runId) async {
    final run = await (_database.select(
      _database.recurringRuleRuns,
    )..where((tbl) => tbl.id.equals(runId))).getSingle();

    if (run.status != 'suggested' || run.transactionId != null) {
      throw StateError('Only pending recurring suggestions can be approved.');
    }

    final rule = await (_database.select(
      _database.recurringRules,
    )..where((tbl) => tbl.id.equals(run.recurringRuleId))).getSingle();

    final transactionId = await _createTransactionFromRule(
      rule,
      run.scheduledFor,
    );

    await (_database.update(
      _database.recurringRuleRuns,
    )..where((tbl) => tbl.id.equals(run.id))).write(
      db.RecurringRuleRunsCompanion(
        transactionId: Value(transactionId),
        status: const Value('created_from_suggestion'),
      ),
    );

    return transactionId;
  }

  Future<void> dismissSuggestedRun(String runId) async {
    await (_database.update(_database.recurringRuleRuns)
          ..where((tbl) => tbl.id.equals(runId)))
        .write(const db.RecurringRuleRunsCompanion(status: Value('dismissed')));
  }

  Future<RecurringProcessingResult> processDueRules({
    DateTime? now,
    bool notifyWhenWorkFound = true,
  }) async {
    final DateTime currentTime = now ?? DateTime.now();
    final dueRules =
        await (_database.select(_database.recurringRules)
              ..where(
                (tbl) =>
                    tbl.deletedAt.isNull() &
                    tbl.isActive.equals(true) &
                    tbl.nextDueDate.isSmallerOrEqualValue(currentTime),
              )
              ..orderBy(<OrderingTerm Function(db.$RecurringRulesTable)>[
                (tbl) => OrderingTerm.asc(tbl.nextDueDate),
                (tbl) => OrderingTerm.asc(tbl.title),
              ]))
            .get();

    int processedRulesCount = 0;
    int autoCreatedCount = 0;
    int suggestedCount = 0;

    for (final rule in dueRules) {
      final result = await _processSingleRule(rule, currentTime);
      if (!result.hasWork) {
        continue;
      }

      processedRulesCount += 1;
      autoCreatedCount += result.autoCreatedCount;
      suggestedCount += result.suggestedCount;
    }

    final summary = RecurringProcessingResult(
      processedRulesCount: processedRulesCount,
      autoCreatedCount: autoCreatedCount,
      suggestedCount: suggestedCount,
    );

    if (notifyWhenWorkFound && summary.hasWork) {
      await _notificationService.showRecurringDigest(
        autoCreatedCount: autoCreatedCount,
        suggestedCount: suggestedCount,
      );
    }

    return summary;
  }

  Future<RecurringProcessingResult> _processSingleRule(
    db.RecurringRule rule,
    DateTime currentTime,
  ) async {
    DateTime scheduledFor = rule.nextDueDate;
    DateTime? lastGeneratedAt;
    DateTime? nextDueDate = rule.nextDueDate;
    int autoCreatedCount = 0;
    int suggestedCount = 0;

    while (!scheduledFor.isAfter(currentTime)) {
      if (rule.endDate != null && scheduledFor.isAfter(rule.endDate!)) {
        nextDueDate = null;
        break;
      }

      String? transactionId;
      if (rule.autoCreate) {
        transactionId = await _createTransactionFromRule(rule, scheduledFor);
        autoCreatedCount += 1;
      } else {
        suggestedCount += 1;
      }

      await _database
          .into(_database.recurringRuleRuns)
          .insert(
            db.RecurringRuleRunsCompanion.insert(
              id: _uuid.v4(),
              recurringRuleId: rule.id,
              scheduledFor: scheduledFor,
              transactionId: Value(transactionId),
              status: rule.autoCreate ? 'auto_created' : 'suggested',
              createdAt: currentTime,
            ),
          );

      lastGeneratedAt = scheduledFor;
      final advancedDate = _advanceDate(
        scheduledFor,
        _frequencyFromName(rule.frequency),
        rule.intervalCount,
      );

      if (rule.endDate != null && advancedDate.isAfter(rule.endDate!)) {
        nextDueDate = null;
        break;
      }

      nextDueDate = advancedDate;
      scheduledFor = advancedDate;
    }

    if (lastGeneratedAt == null && nextDueDate != null) {
      return const RecurringProcessingResult(
        processedRulesCount: 0,
        autoCreatedCount: 0,
        suggestedCount: 0,
      );
    }

    if (lastGeneratedAt == null && nextDueDate == null) {
      await (_database.update(
        _database.recurringRules,
      )..where((tbl) => tbl.id.equals(rule.id))).write(
        db.RecurringRulesCompanion(
          isActive: const Value(false),
          updatedAt: Value(currentTime),
        ),
      );

      return const RecurringProcessingResult(
        processedRulesCount: 0,
        autoCreatedCount: 0,
        suggestedCount: 0,
      );
    }

    await (_database.update(
      _database.recurringRules,
    )..where((tbl) => tbl.id.equals(rule.id))).write(
      db.RecurringRulesCompanion(
        nextDueDate: Value(nextDueDate ?? lastGeneratedAt!),
        lastGeneratedAt: Value(lastGeneratedAt),
        isActive: Value(nextDueDate != null),
        updatedAt: Value(currentTime),
      ),
    );

    return RecurringProcessingResult(
      processedRulesCount: 1,
      autoCreatedCount: autoCreatedCount,
      suggestedCount: suggestedCount,
    );
  }

  Future<String> _createTransactionFromRule(
    db.RecurringRule rule,
    DateTime scheduledFor,
  ) async {
    return _transactionRepository.createTransaction(
      CreateTransactionInput(
        type: _transactionTypeFromName(rule.type),
        accountId: rule.accountId,
        destinationAccountId: rule.destinationAccountId,
        amountMinor: rule.amountMinor,
        transactionDate: scheduledFor,
        note: rule.note.isEmpty ? rule.title : rule.note,
        categoryId: rule.categoryId,
        childCategoryId: rule.childCategoryId,
        recurringRuleId: rule.id,
      ),
    );
  }

  Future<List<domain.RecurringRuleRun>> _mapRunRows(
    List<db.RecurringRuleRun> rows,
  ) async {
    final ruleRows = await _database.select(_database.recurringRules).get();
    final accountRows = await _database.select(_database.accounts).get();

    final rulesById = <String, db.RecurringRule>{
      for (final rule in ruleRows) rule.id: rule,
    };
    final accountsById = <String, db.Account>{
      for (final account in accountRows) account.id: account,
    };

    return rows
        .map((row) {
          final rule = rulesById[row.recurringRuleId];
          final type = _transactionTypeFromName(rule?.type ?? '');
          final accountName = rule == null
              ? 'Unknown account'
              : accountsById[rule.accountId]?.name ?? 'Unknown account';
          final destinationAccountName = rule?.destinationAccountId == null
              ? null
              : accountsById[rule!.destinationAccountId!]?.name;

          return domain.RecurringRuleRun(
            id: row.id,
            recurringRuleId: row.recurringRuleId,
            title: rule?.title ?? 'Deleted recurring rule',
            type: type,
            accountName: accountName,
            destinationAccountName: destinationAccountName,
            amountMinor: rule?.amountMinor ?? 0,
            scheduledFor: row.scheduledFor,
            status: row.status,
            transactionId: row.transactionId,
          );
        })
        .toList(growable: false);
  }

  TransactionType _transactionTypeFromName(String value) {
    return TransactionType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => TransactionType.expense,
    );
  }

  RecurringFrequency _frequencyFromName(String value) {
    return RecurringFrequency.values.firstWhere(
      (frequency) => frequency.name == value,
      orElse: () => RecurringFrequency.monthly,
    );
  }

  DateTime _advanceDate(
    DateTime date,
    RecurringFrequency frequency,
    int intervalCount,
  ) {
    switch (frequency) {
      case RecurringFrequency.daily:
        return date.add(Duration(days: intervalCount));
      case RecurringFrequency.weekly:
        return date.add(Duration(days: 7 * intervalCount));
      case RecurringFrequency.monthly:
        return DateTime(
          date.year,
          date.month + intervalCount,
          date.day,
          date.hour,
          date.minute,
          date.second,
          date.millisecond,
          date.microsecond,
        );
      case RecurringFrequency.yearly:
        return DateTime(
          date.year + intervalCount,
          date.month,
          date.day,
          date.hour,
          date.minute,
          date.second,
          date.millisecond,
          date.microsecond,
        );
    }
  }
}
