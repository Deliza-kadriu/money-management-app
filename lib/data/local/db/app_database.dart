import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/accounts_table.dart';
import 'tables/categories_table.dart';
import 'tables/loan_installments_table.dart';
import 'tables/loans_table.dart';
import 'tables/recurring_rule_runs_table.dart';
import 'tables/recurring_rules_table.dart';
import 'tables/transaction_attachments_table.dart';
import 'tables/transactions_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: <Type>[
    Accounts,
    Categories,
    Loans,
    LoanInstallments,
    Transactions,
    TransactionAttachments,
    RecurringRules,
    RecurringRuleRuns,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 5) {
        await migrator.addColumn(accounts, accounts.excludeFromTotals);
        await migrator.addColumn(accounts, accounts.isDefault);
      }
      if (from < 6) {
        await migrator.createTable(loans);
        await migrator.createTable(loanInstallments);
        await migrator.addColumn(transactions, transactions.source);
        await migrator.addColumn(transactions, transactions.loanId);
        await migrator.addColumn(transactions, transactions.loanInstallmentId);
      }
      if (from < 7) {
        await migrator.addColumn(loans, loans.accountId);
        await migrator.addColumn(loans, loans.categoryId);
        await migrator.addColumn(loans, loans.childCategoryId);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final File file = File(p.join(directory.path, 'money_manager.sqlite'));
    return NativeDatabase.createInBackground(file, logStatements: kDebugMode);
  });
}
