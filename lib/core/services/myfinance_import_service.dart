import 'dart:convert';

import 'package:money_manager/data/local/db/app_database.dart' as db;
import 'package:money_manager/domain/enums/account_type.dart';
import 'package:money_manager/domain/enums/category_type.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';

class MyFinanceImportService {
  MyFinanceImportService(this._database);

  final db.AppDatabase _database;

  Future<MyFinanceImportResult> replaceWithImport(String rawJson) async {
    final Object? decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid MyFinance export format.');
    }

    final List<Map<String, Object?>> accountMaps = _asMapList(
      decoded['accounts'],
    );
    final List<Map<String, Object?>> categoryMaps = _asMapList(
      decoded['categories'],
    );
    final List<Map<String, Object?>> transactionMaps = _asMapList(
      decoded['transactions'],
    );
    final List<Map<String, Object?>> transferMaps = _asMapList(
      decoded['transfers'],
    );

    final List<_ImportedTransaction> importedTransactions =
        <_ImportedTransaction>[
          ...transactionMaps
              .map(_mapRegularTransaction)
              .whereType<_ImportedTransaction>(),
          ...transferMaps.map(_mapTransfer).whereType<_ImportedTransaction>(),
        ]..sort((a, b) {
          final int byDate = a.transactionDate.compareTo(b.transactionDate);
          if (byDate != 0) {
            return byDate;
          }
          return a.createdAt.compareTo(b.createdAt);
        });

    final Map<String, int> balanceByAccountId = <String, int>{
      for (final account in accountMaps) _stringValue(account['uid']): 0,
    };

    for (final tx in importedTransactions) {
      switch (tx.type) {
        case TransactionType.income:
          balanceByAccountId.update(
            tx.accountId,
            (value) => value + tx.amountMinor,
            ifAbsent: () => tx.amountMinor,
          );
          break;
        case TransactionType.expense:
          balanceByAccountId.update(
            tx.accountId,
            (value) => value - tx.amountMinor,
            ifAbsent: () => -tx.amountMinor,
          );
          break;
        case TransactionType.transfer:
          balanceByAccountId.update(
            tx.accountId,
            (value) => value - tx.amountMinor,
            ifAbsent: () => -tx.amountMinor,
          );
          if (tx.destinationAccountId != null) {
            balanceByAccountId.update(
              tx.destinationAccountId!,
              (value) => value + tx.amountMinor,
              ifAbsent: () => tx.amountMinor,
            );
          }
          break;
      }
    }

    final List<db.Account> accounts = accountMaps
        .map(
          (json) => db.Account(
            id: _stringValue(json['uid']),
            name: _nonEmptyOrFallback(
              json['title'],
              fallback: 'Imported account',
            ),
            type: _mapAccountType(json).name,
            openingBalanceMinor: 0,
            currentBalanceMinor:
                balanceByAccountId[_stringValue(json['uid'])] ?? 0,
            currencyCode: _currencyCode(json['currencyCode']),
            colorValue: _intValue(json['color'], fallback: 0xFF115E59),
            iconKey: _mapAccountIconKey(json),
            isActive: _boolFromInt(json['isActive'], fallback: true),
            excludeFromTotals: _boolFromInt(
              json['ignoreInBalance'],
              fallback: false,
            ),
            isDefault: false,
            createdAt: _parseDateTime(
              json['created'],
              fallback: DateTime.now(),
            ),
            updatedAt: _parseDateTime(
              json['modified'],
              fallback: DateTime.now(),
            ),
            deletedAt: _boolFromInt(json['isActive'], fallback: true)
                ? null
                : _parseDateTime(json['modified']),
          ),
        )
        .toList(growable: false);

    final List<db.Category> categories = categoryMaps
        .map(
          (json) => db.Category(
            id: _stringValue(json['uid']),
            name: _categoryName(json),
            parentId: null,
            type: _mapCategoryType(json['type']).name,
            iconKey: _mapCategoryIconKey(json),
            colorValue: _intValue(json['color'], fallback: 0xFF115E59),
            sortOrder: _intValue(json['position']),
            isActive: true,
            createdAt: _parseDateTime(
              json['created'],
              fallback: DateTime.now(),
            ),
            updatedAt: _parseDateTime(
              json['modified'],
              fallback: DateTime.now(),
            ),
            deletedAt: null,
          ),
        )
        .toList(growable: false);

    final List<db.Transaction> transactions = importedTransactions
        .map(
          (tx) => db.Transaction(
            id: tx.id,
            type: tx.type.name,
            accountId: tx.accountId,
            destinationAccountId: tx.destinationAccountId,
            amountMinor: tx.amountMinor,
            transactionDate: tx.transactionDate,
            categoryId: tx.categoryId,
            childCategoryId: null,
            note: tx.note,
            recurringRuleId: null,
            createdAt: tx.createdAt,
            updatedAt: tx.updatedAt,
            deletedAt: null,
          ),
        )
        .toList(growable: false);

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
      if (transactions.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(_database.transactions, transactions);
        });
      }
    });

    return MyFinanceImportResult(
      accountCount: accounts.length,
      categoryCount: categories.length,
      transactionCount: transactionMaps.length,
      transferCount: transferMaps.length,
      importedEntryCount: transactions.length,
    );
  }

  _ImportedTransaction? _mapRegularTransaction(Map<String, Object?> json) {
    if (_boolFromInt(json['isRemoved'], fallback: false)) {
      return null;
    }

    final String accountId = _stringValue(json['account_uid']);
    if (accountId.isEmpty) {
      return null;
    }

    final TransactionType type = _mapTransactionType(json['type']);
    final String? categoryId = _nullableString(json['category_uid']);
    final String? photoName = _nullableString(json['photo_file']);

    return _ImportedTransaction(
      id: _stringValue(json['uid']),
      type: type,
      accountId: accountId,
      destinationAccountId: null,
      amountMinor: _amountToMinor(json['amount']),
      transactionDate: _parseDateOnly(json['date']),
      categoryId: categoryId,
      note: _noteWithPhotoHint(
        _nullableString(json['comment']) ?? '',
        photoName: photoName,
      ),
      createdAt: _parseDateTime(
        json['created'],
        fallback: _parseDateOnly(json['date']),
      ),
      updatedAt: _parseDateTime(
        json['modified'],
        fallback: _parseDateOnly(json['date']),
      ),
    );
  }

  _ImportedTransaction? _mapTransfer(Map<String, Object?> json) {
    if (_boolFromInt(json['isRemoved'], fallback: false)) {
      return null;
    }

    final String fromAccountId = _stringValue(json['from_account_uid']);
    final String toAccountId = _stringValue(json['to_account_uid']);
    if (fromAccountId.isEmpty || toAccountId.isEmpty) {
      return null;
    }

    return _ImportedTransaction(
      id: 'transfer_${_stringValue(json['uid'])}',
      type: TransactionType.transfer,
      accountId: fromAccountId,
      destinationAccountId: toAccountId,
      amountMinor: _amountToMinor(json['from_amount']),
      transactionDate: _parseDateOnly(json['date']),
      categoryId: null,
      note: _nullableString(json['comment']) ?? '',
      createdAt: _parseDateTime(
        json['created'],
        fallback: _parseDateOnly(json['date']),
      ),
      updatedAt: _parseDateTime(
        json['modified'],
        fallback: _parseDateOnly(json['date']),
      ),
    );
  }

  List<Map<String, Object?>> _asMapList(Object? value) {
    if (value is! List<Object?>) {
      return <Map<String, Object?>>[];
    }

    return value
        .whereType<Map<Object?, Object?>>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList(growable: false);
  }

  String _categoryName(Map<String, Object?> json) {
    final String title = _nonEmptyOrFallback(json['title'], fallback: '');
    if (title.isNotEmpty) {
      return title;
    }

    final String uid = _stringValue(json['uid']);
    if (uid.startsWith('Default') && uid.length > 'Default'.length) {
      return _humanize(uid.substring('Default'.length));
    }

    return _humanize(uid);
  }

  String _mapCategoryIconKey(Map<String, Object?> json) {
    final String icon = _stringValue(json['icon']).toLowerCase();
    if (icon.contains('car') || icon.contains('transport')) {
      return 'car';
    }
    if (icon.contains('salary') ||
        icon.contains('bank') ||
        icon.contains('payment') ||
        icon.contains('prepaid')) {
      return 'salary';
    }
    if (icon.contains('home')) {
      return 'home';
    }
    if (icon.contains('health') || icon.contains('dent')) {
      return 'health';
    }
    if (icon.contains('sale') ||
        icon.contains('basket') ||
        icon.contains('products') ||
        icon.contains('pizza') ||
        icon.contains('cafe') ||
        icon.contains('present')) {
      return 'shopping';
    }
    return 'category';
  }

  AccountType _mapAccountType(Map<String, Object?> json) {
    final String title = _stringValue(json['title']).toLowerCase();
    final String icon = _stringValue(json['icon']).toLowerCase();

    if (title.contains('loan') || title.contains('overdraft')) {
      return AccountType.creditCard;
    }
    if (icon == 'cash') {
      return AccountType.cash;
    }
    if (icon == 'cards') {
      return AccountType.creditCard;
    }
    if (icon == 'piggy_bank' ||
        title.contains('saving') ||
        title.contains('kursim')) {
      return AccountType.savings;
    }
    if (icon == 'bank') {
      return AccountType.bankAccount;
    }

    return AccountType.other;
  }

  String _mapAccountIconKey(Map<String, Object?> json) {
    final String icon = _stringValue(json['icon']).toLowerCase();
    switch (icon) {
      case 'cash':
        return 'wallet';
      case 'cards':
        return 'credit_card';
      case 'piggy_bank':
        return 'savings';
      case 'bank':
        return 'bank';
      default:
        return 'account';
    }
  }

  CategoryType _mapCategoryType(Object? rawType) {
    final String type = _stringValue(rawType).toLowerCase();
    if (type == 'income') {
      return CategoryType.income;
    }
    if (type == 'expense') {
      return CategoryType.expense;
    }
    return CategoryType.both;
  }

  TransactionType _mapTransactionType(Object? rawType) {
    final String type = _stringValue(rawType).toLowerCase();
    switch (type) {
      case 'income':
        return TransactionType.income;
      case 'expense':
        return TransactionType.expense;
      default:
        return TransactionType.expense;
    }
  }

  int _amountToMinor(Object? value) {
    if (value is int) {
      return value * 100;
    }
    if (value is double) {
      return (value * 100).round();
    }
    return ((double.tryParse(_stringValue(value)) ?? 0) * 100).round();
  }

  bool _boolFromInt(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return fallback;
  }

  int _intValue(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse(_stringValue(value)) ?? fallback;
  }

  String _currencyCode(Object? value) {
    final String code = _stringValue(value).toUpperCase();
    return code.length == 3 ? code : 'EUR';
  }

  String _noteWithPhotoHint(String note, {String? photoName}) {
    if (photoName == null || photoName.isEmpty) {
      return note;
    }
    if (note.isEmpty) {
      return '[Imported receipt: $photoName]';
    }
    return '$note [Imported receipt: $photoName]';
  }

  String _nonEmptyOrFallback(Object? value, {required String fallback}) {
    final String text = _stringValue(value).trim();
    return text.isEmpty ? fallback : text;
  }

  String _stringValue(Object? value) => value?.toString() ?? '';

  String? _nullableString(Object? value) {
    final String text = _stringValue(value).trim();
    return text.isEmpty ? null : text;
  }

  DateTime _parseDateOnly(Object? value) {
    final String raw = _stringValue(value);
    return DateTime.parse(raw);
  }

  DateTime _parseDateTime(Object? value, {DateTime? fallback}) {
    final String raw = _stringValue(value);
    if (raw.isEmpty) {
      return fallback ?? DateTime.now();
    }
    return DateTime.tryParse(raw) ?? fallback ?? DateTime.now();
  }

  String _humanize(String value) {
    final String spaced = value
        .replaceAll('_', ' ')
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .trim();
    if (spaced.isEmpty) {
      return 'Imported category';
    }

    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

class MyFinanceImportResult {
  const MyFinanceImportResult({
    required this.accountCount,
    required this.categoryCount,
    required this.transactionCount,
    required this.transferCount,
    required this.importedEntryCount,
  });

  final int accountCount;
  final int categoryCount;
  final int transactionCount;
  final int transferCount;
  final int importedEntryCount;
}

class _ImportedTransaction {
  const _ImportedTransaction({
    required this.id,
    required this.type,
    required this.accountId,
    required this.destinationAccountId,
    required this.amountMinor,
    required this.transactionDate,
    required this.categoryId,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final TransactionType type;
  final String accountId;
  final String? destinationAccountId;
  final int amountMinor;
  final DateTime transactionDate;
  final String? categoryId;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
}
