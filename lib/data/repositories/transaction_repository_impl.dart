import 'dart:async';

import 'package:drift/drift.dart';
import 'package:money_manager/data/local/db/app_database.dart';
import 'package:money_manager/domain/entities/dashboard_summary.dart';
import 'package:money_manager/domain/entities/money_transaction.dart' as domain;
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/domain/repositories/transaction_repository.dart';
import 'package:uuid/uuid.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl(this._database);

  final AppDatabase _database;
  final Uuid _uuid = const Uuid();

  @override
  Stream<List<domain.MoneyTransaction>> watchTransactions({
    bool archivedOnly = false,
  }) {
    final query = _database.select(_database.transactions)
      ..where(
        (tbl) =>
            archivedOnly ? tbl.deletedAt.isNotNull() : tbl.deletedAt.isNull(),
      )
      ..orderBy(<OrderingTerm Function($TransactionsTable)>[
        (tbl) => OrderingTerm.desc(tbl.transactionDate),
        (tbl) => OrderingTerm.desc(tbl.createdAt),
      ]);

    return query.watch().asyncMap(_mapTransactionRows);
  }

  @override
  Stream<List<domain.MoneyTransaction>> watchRecentTransactions({
    int limit = 5,
  }) {
    return watchTransactions().map(
      (items) => items.take(limit).toList(growable: false),
    );
  }

  @override
  Stream<DashboardSummary> watchDashboardSummary() {
    return Rx.combineLatest2<
      List<Account>,
      List<domain.MoneyTransaction>,
      DashboardSummary
    >(_watchActiveAccountRows(), watchTransactions(), (accounts, transactions) {
      final DateTime now = DateTime.now();
      final int totalBalanceMinor = accounts.fold<int>(
        0,
        (sum, account) => sum + account.currentBalanceMinor,
      );

      int monthIncomeMinor = 0;
      int monthExpenseMinor = 0;

      for (final transaction in transactions) {
        final bool sameMonth =
            transaction.transactionDate.year == now.year &&
            transaction.transactionDate.month == now.month;

        if (!sameMonth) continue;

        switch (transaction.type) {
          case TransactionType.income:
            monthIncomeMinor += transaction.amountMinor;
            break;
          case TransactionType.expense:
            monthExpenseMinor += transaction.amountMinor;
            break;
          case TransactionType.transfer:
            break;
        }
      }

      return DashboardSummary(
        totalBalanceMinor: totalBalanceMinor,
        monthIncomeMinor: monthIncomeMinor,
        monthExpenseMinor: monthExpenseMinor,
        activeAccountsCount: accounts.length,
      );
    });
  }

  @override
  Future<String> createTransaction(CreateTransactionInput input) async {
    final DateTime now = DateTime.now();
    final String transactionId = _uuid.v4();

    await _database.transaction(() async {
      await _database
          .into(_database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: transactionId,
              type: input.type.name,
              accountId: input.accountId,
              destinationAccountId: Value(input.destinationAccountId),
              amountMinor: input.amountMinor,
              transactionDate: input.transactionDate,
              categoryId: Value(input.categoryId),
              childCategoryId: Value(input.childCategoryId),
              note: Value(input.note.trim()),
              recurringRuleId: Value(input.recurringRuleId),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await _replaceAttachments(
        transactionId: transactionId,
        filePaths: input.attachmentFilePaths,
        createdAt: now,
      );

      await _applyBalanceImpact(
        type: input.type,
        accountId: input.accountId,
        destinationAccountId: input.destinationAccountId,
        amountMinor: input.amountMinor,
        reverse: false,
      );
    });

    return transactionId;
  }

  @override
  Future<void> updateTransaction(
    String id,
    CreateTransactionInput input,
  ) async {
    final Transaction existing = await (_database.select(
      _database.transactions,
    )..where((tbl) => tbl.id.equals(id))).getSingle();

    if (existing.deletedAt != null) {
      throw StateError(
        'Archived transactions must be restored before editing.',
      );
    }

    final TransactionType oldType = _transactionTypeFromName(existing.type);
    final DateTime now = DateTime.now();

    await _database.transaction(() async {
      await _applyBalanceImpact(
        type: oldType,
        accountId: existing.accountId,
        destinationAccountId: existing.destinationAccountId,
        amountMinor: existing.amountMinor,
        reverse: true,
      );

      await (_database.update(
        _database.transactions,
      )..where((tbl) => tbl.id.equals(id))).write(
        TransactionsCompanion(
          type: Value(input.type.name),
          accountId: Value(input.accountId),
          destinationAccountId: Value(input.destinationAccountId),
          amountMinor: Value(input.amountMinor),
          transactionDate: Value(input.transactionDate),
          categoryId: Value(input.categoryId),
          childCategoryId: Value(input.childCategoryId),
          note: Value(input.note.trim()),
          updatedAt: Value(now),
        ),
      );

      await _replaceAttachments(
        transactionId: id,
        filePaths: input.attachmentFilePaths,
        createdAt: now,
      );

      await _applyBalanceImpact(
        type: input.type,
        accountId: input.accountId,
        destinationAccountId: input.destinationAccountId,
        amountMinor: input.amountMinor,
        reverse: false,
      );
    });
  }

  @override
  Future<void> softDeleteTransaction(String id) async {
    final Transaction existing = await (_database.select(
      _database.transactions,
    )..where((tbl) => tbl.id.equals(id))).getSingle();

    if (existing.deletedAt != null) {
      return;
    }

    final TransactionType type = _transactionTypeFromName(existing.type);
    final DateTime now = DateTime.now();

    await _database.transaction(() async {
      await (_database.update(
        _database.transactions,
      )..where((tbl) => tbl.id.equals(id))).write(
        TransactionsCompanion(updatedAt: Value(now), deletedAt: Value(now)),
      );

      await _applyBalanceImpact(
        type: type,
        accountId: existing.accountId,
        destinationAccountId: existing.destinationAccountId,
        amountMinor: existing.amountMinor,
        reverse: true,
      );
    });
  }

  @override
  Future<void> restoreTransaction(String id) async {
    final Transaction existing = await (_database.select(
      _database.transactions,
    )..where((tbl) => tbl.id.equals(id))).getSingle();

    if (existing.deletedAt == null) {
      return;
    }

    final TransactionType type = _transactionTypeFromName(existing.type);
    final DateTime now = DateTime.now();

    await _database.transaction(() async {
      await (_database.update(
        _database.transactions,
      )..where((tbl) => tbl.id.equals(id))).write(
        TransactionsCompanion(
          updatedAt: Value(now),
          deletedAt: const Value(null),
        ),
      );

      await _applyBalanceImpact(
        type: type,
        accountId: existing.accountId,
        destinationAccountId: existing.destinationAccountId,
        amountMinor: existing.amountMinor,
        reverse: false,
      );
    });
  }

  Stream<List<Account>> _watchActiveAccountRows() {
    final query = _database.select(_database.accounts)
      ..where((tbl) => tbl.deletedAt.isNull());

    return query.watch();
  }

  Future<List<domain.MoneyTransaction>> _mapTransactionRows(
    List<Transaction> rows,
  ) async {
    final List<Account> accountRows = await _database
        .select(_database.accounts)
        .get();
    final List<Category> categoryRows = await _database
        .select(_database.categories)
        .get();
    final List<TransactionAttachment> attachmentRows = await _database
        .select(_database.transactionAttachments)
        .get();

    final Map<String, Account> accountsById = <String, Account>{
      for (final account in accountRows) account.id: account,
    };
    final Map<String, Category> categoriesById = <String, Category>{
      for (final category in categoryRows) category.id: category,
    };
    final Map<String, List<TransactionAttachment>> attachmentsByTransactionId =
        <String, List<TransactionAttachment>>{};

    for (final attachment in attachmentRows) {
      attachmentsByTransactionId
          .putIfAbsent(
            attachment.transactionId,
            () => <TransactionAttachment>[],
          )
          .add(attachment);
    }

    return rows
        .map((row) {
          final category = row.categoryId == null
              ? null
              : categoriesById[row.categoryId!];
          final childCategory = row.childCategoryId == null
              ? null
              : categoriesById[row.childCategoryId!];
          final attachmentFilePaths =
              (attachmentsByTransactionId[row.id] ??
                      const <TransactionAttachment>[])
                  .toList(growable: false)
                ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

          return domain.MoneyTransaction(
            id: row.id,
            type: _transactionTypeFromName(row.type),
            accountId: row.accountId,
            accountName: accountsById[row.accountId]?.name ?? 'Unknown account',
            destinationAccountId: row.destinationAccountId,
            destinationAccountName: row.destinationAccountId == null
                ? null
                : accountsById[row.destinationAccountId!]?.name,
            amountMinor: row.amountMinor,
            transactionDate: row.transactionDate,
            note: row.note,
            categoryId: row.categoryId,
            categoryName: category?.name,
            childCategoryId: row.childCategoryId,
            childCategoryName: childCategory?.name,
            attachmentFilePaths: attachmentFilePaths
                .map((attachment) => attachment.filePath)
                .toList(growable: false),
            deletedAt: row.deletedAt,
          );
        })
        .toList(growable: false);
  }

  Future<void> _replaceAttachments({
    required String transactionId,
    required List<String> filePaths,
    required DateTime createdAt,
  }) async {
    await (_database.delete(
      _database.transactionAttachments,
    )..where((tbl) => tbl.transactionId.equals(transactionId))).go();

    final limitedFilePaths = filePaths.take(4).toList(growable: false);
    for (int index = 0; index < limitedFilePaths.length; index += 1) {
      await _database
          .into(_database.transactionAttachments)
          .insert(
            TransactionAttachmentsCompanion.insert(
              id: _uuid.v4(),
              transactionId: transactionId,
              filePath: limitedFilePaths[index],
              sortOrder: Value(index),
              createdAt: createdAt,
            ),
          );
    }
  }

  TransactionType _transactionTypeFromName(String raw) {
    return TransactionType.values.firstWhere(
      (type) => type.name == raw,
      orElse: () => TransactionType.expense,
    );
  }

  Future<void> _applyBalanceImpact({
    required TransactionType type,
    required String accountId,
    required String? destinationAccountId,
    required int amountMinor,
    required bool reverse,
  }) async {
    switch (type) {
      case TransactionType.income:
        await _updateAccountBalance(
          accountId,
          reverse ? -amountMinor : amountMinor,
        );
        break;
      case TransactionType.expense:
        await _updateAccountBalance(
          accountId,
          reverse ? amountMinor : -amountMinor,
        );
        break;
      case TransactionType.transfer:
        if (destinationAccountId == null) {
          throw StateError('Transfer requires a destination account.');
        }
        await _updateAccountBalance(
          accountId,
          reverse ? amountMinor : -amountMinor,
        );
        await _updateAccountBalance(
          destinationAccountId,
          reverse ? -amountMinor : amountMinor,
        );
        break;
    }
  }

  Future<void> _updateAccountBalance(String accountId, int deltaMinor) async {
    final Account account = await (_database.select(
      _database.accounts,
    )..where((tbl) => tbl.id.equals(accountId))).getSingle();

    final DateTime now = DateTime.now();
    final int nextBalance = account.currentBalanceMinor + deltaMinor;

    await (_database.update(
      _database.accounts,
    )..where((tbl) => tbl.id.equals(accountId))).write(
      AccountsCompanion(
        currentBalanceMinor: Value(nextBalance),
        updatedAt: Value(now),
      ),
    );
  }
}

class Rx {
  const Rx._();

  static Stream<R> combineLatest2<A, B, R>(
    Stream<A> streamA,
    Stream<B> streamB,
    R Function(A a, B b) combiner,
  ) {
    late StreamController<R> controller;
    A? latestA;
    B? latestB;
    StreamSubscription<A>? subscriptionA;
    StreamSubscription<B>? subscriptionB;

    void emitIfReady() {
      final A? valueA = latestA;
      final B? valueB = latestB;
      if (valueA != null && valueB != null) {
        controller.add(combiner(valueA, valueB));
      }
    }

    controller = StreamController<R>(
      onListen: () {
        subscriptionA = streamA.listen((value) {
          latestA = value;
          emitIfReady();
        }, onError: controller.addError);

        subscriptionB = streamB.listen((value) {
          latestB = value;
          emitIfReady();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await subscriptionA?.cancel();
        await subscriptionB?.cancel();
      },
    );

    return controller.stream;
  }
}
