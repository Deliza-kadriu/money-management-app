import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/accounts_table.dart';
import 'tables/categories_table.dart';
import 'tables/recurring_rule_runs_table.dart';
import 'tables/recurring_rules_table.dart';
import 'tables/transaction_attachments_table.dart';
import 'tables/transactions_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: <Type>[
    Accounts,
    Categories,
    Transactions,
    TransactionAttachments,
    RecurringRules,
    RecurringRuleRuns,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final File file = File(p.join(directory.path, 'money_manager.sqlite'));
    return NativeDatabase.createInBackground(file, logStatements: kDebugMode);
  });
}
