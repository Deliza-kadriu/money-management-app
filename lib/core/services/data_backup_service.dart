import 'dart:convert';
import 'dart:io';

import 'package:money_manager/core/services/app_settings_service.dart';
import 'package:money_manager/data/local/db/app_database.dart' as db;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DataBackupService {
  DataBackupService(this._database, this._appSettingsService);

  final db.AppDatabase _database;
  final AppSettingsService _appSettingsService;

  Future<String> createBackupFile() async {
    final Map<String, Object?> payload = await _buildBackupPayload();
    final Directory directory = await getApplicationDocumentsDirectory();
    final DateTime now = DateTime.now();
    final String fileName =
        'money_manager_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.json';
    final File file = File(p.join(directory.path, fileName));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    return file.path;
  }

  Future<BackupImportResult> restoreFromJsonString(String rawJson) async {
    final Object? decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Backup file format is invalid.');
    }
    _validateBackupFormat(decoded);

    final List<db.Account> accounts = _decodeRows<db.Account>(
      decoded['accounts'],
      db.Account.fromJson,
    );
    final List<db.Category> categories = _decodeRows<db.Category>(
      decoded['categories'],
      db.Category.fromJson,
    );
    final List<db.RecurringRule> recurringRules = _decodeRows<db.RecurringRule>(
      decoded['recurringRules'],
      db.RecurringRule.fromJson,
    );
    final List<db.Transaction> transactions = _decodeRows<db.Transaction>(
      decoded['transactions'],
      db.Transaction.fromJson,
    );
    final List<db.TransactionAttachment> attachments =
        _decodeRows<db.TransactionAttachment>(
          decoded['transactionAttachments'],
          db.TransactionAttachment.fromJson,
        );
    final List<db.RecurringRuleRun> recurringRuleRuns =
        _decodeRows<db.RecurringRuleRun>(
          decoded['recurringRuleRuns'],
          db.RecurringRuleRun.fromJson,
        );

    await _database.transaction(() async {
      await _database.delete(_database.recurringRuleRuns).go();
      await _database.delete(_database.transactionAttachments).go();
      await _database.delete(_database.transactions).go();
      await _database.delete(_database.recurringRules).go();
      await _database.delete(_database.categories).go();
      await _database.delete(_database.accounts).go();

      if (accounts.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(_database.accounts, accounts);
        });
      }
      if (categories.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(_database.categories, categories);
        });
      }
      if (recurringRules.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(_database.recurringRules, recurringRules);
        });
      }
      if (transactions.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(_database.transactions, transactions);
        });
      }
      if (attachments.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(_database.transactionAttachments, attachments);
        });
      }
      if (recurringRuleRuns.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(_database.recurringRuleRuns, recurringRuleRuns);
        });
      }
    });

    final Object? settingsJson = decoded['settings'];
    if (settingsJson is Map<String, Object?>) {
      await _appSettingsService.saveFromJson(settingsJson);
    }

    return BackupImportResult(
      accountCount: accounts.length,
      categoryCount: categories.length,
      transactionCount: transactions.length,
      recurringRuleCount: recurringRules.length,
    );
  }

  Future<Map<String, Object?>> _buildBackupPayload() async {
    final List<db.Account> accounts = await _database
        .select(_database.accounts)
        .get();
    final List<db.Category> categories = await _database
        .select(_database.categories)
        .get();
    final List<db.Transaction> transactions = await _database
        .select(_database.transactions)
        .get();
    final List<db.TransactionAttachment> attachments = await _database
        .select(_database.transactionAttachments)
        .get();
    final List<db.RecurringRule> recurringRules = await _database
        .select(_database.recurringRules)
        .get();
    final List<db.RecurringRuleRun> recurringRuleRuns = await _database
        .select(_database.recurringRuleRuns)
        .get();
    final settings = await _appSettingsService.load();

    return <String, Object?>{
      'formatVersion': 1,
      'schemaVersion': _database.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': settings.toJson(),
      'accounts': accounts.map((row) => row.toJson()).toList(growable: false),
      'categories': categories
          .map((row) => row.toJson())
          .toList(growable: false),
      'transactions': transactions
          .map((row) => row.toJson())
          .toList(growable: false),
      'transactionAttachments': attachments
          .map((row) => row.toJson())
          .toList(growable: false),
      'recurringRules': recurringRules
          .map((row) => row.toJson())
          .toList(growable: false),
      'recurringRuleRuns': recurringRuleRuns
          .map((row) => row.toJson())
          .toList(growable: false),
    };
  }

  List<T> _decodeRows<T>(
    Object? source,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (source is! List<Object?>) {
      return <T>[];
    }

    return source
        .whereType<Map<Object?, Object?>>()
        .map(
          (row) => fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  void _validateBackupFormat(Map<String, Object?> decoded) {
    if (decoded.containsKey('exported_from') &&
        decoded.containsKey('source_database')) {
      throw const FormatException(
        'This file is a MyFinance export, not a Money Manager backup. Use "Import MyFinance JSON" in Settings > Data.',
      );
    }

    const List<String> requiredKeys = <String>[
      'formatVersion',
      'accounts',
      'categories',
      'transactions',
      'transactionAttachments',
      'recurringRules',
      'recurringRuleRuns',
    ];

    final bool isValid = requiredKeys.every(decoded.containsKey);
    if (!isValid) {
      throw const FormatException(
        'This file is not a valid Money Manager backup.',
      );
    }
  }
}

class BackupImportResult {
  const BackupImportResult({
    required this.accountCount,
    required this.categoryCount,
    required this.transactionCount,
    required this.recurringRuleCount,
  });

  final int accountCount;
  final int categoryCount;
  final int transactionCount;
  final int recurringRuleCount;
}
