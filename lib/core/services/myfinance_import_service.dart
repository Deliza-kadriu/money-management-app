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

    late final int importedEntryCount;

    await _database.transaction(() async {
      await _database.delete(_database.recurringRuleRuns).go();
      await _database.delete(_database.transactionAttachments).go();
      await _database.delete(_database.loanInstallments).go();
      await _database.delete(_database.transactions).go();
      await _database.delete(_database.loans).go();
      await _database.delete(_database.recurringRules).go();
      await _database.delete(_database.accounts).go();

      final Map<String, _ResolvedCategory> resolvedCategoriesBySourceId =
      await _ensureImportCategories(categoryMaps);

      final List<db.Transaction> transactions = importedTransactions
          .map((tx) {
        final _ResolvedCategory? resolvedCategory = tx.categoryId == null
            ? null
            : resolvedCategoriesBySourceId[tx.categoryId!];

        return db.Transaction(
          id: tx.id,
          type: tx.type.name,
          accountId: tx.accountId,
          destinationAccountId: tx.destinationAccountId,
          amountMinor: tx.amountMinor,
          transactionDate: tx.transactionDate,
          categoryId: resolvedCategory?.parentId,
          childCategoryId: resolvedCategory?.childId,
          note: tx.note,
          recurringRuleId: null,
          source: null,
          loanId: null,
          loanInstallmentId: null,
          createdAt: tx.createdAt,
          updatedAt: tx.updatedAt,
          deletedAt: null,
        );
      })
          .toList(growable: false);

      importedEntryCount = transactions.length;

      if (accounts.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(_database.accounts, accounts);
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
      categoryCount: categoryMaps.length,
      transactionCount: transactionMaps.length,
      transferCount: transferMaps.length,
      importedEntryCount: importedEntryCount,
    );
  }

  Future<Map<String, _ResolvedCategory>> _ensureImportCategories(
      List<Map<String, Object?>> categoryMaps,
      ) async {
    final List<db.Category> knownCategories =
    (await _database.select(_database.categories).get()).toList();

    final Map<String, _ResolvedCategory> result = <String, _ResolvedCategory>{};

    for (final json in categoryMaps) {
      final String sourceCategoryId = _stringValue(json['uid']);
      if (sourceCategoryId.isEmpty) {
        continue;
      }

      final _CategoryTarget target = _categoryTargetFromJson(json);
      final CategoryType categoryType = _targetCategoryType(
        target,
        rawType: json['type'],
      );

      final db.Category parent = await _findOrCreateCategory(
        knownCategories: knownCategories,
        name: target.parentName,
        parentId: null,
        type: categoryType,
        iconKey: _mapCategoryIconKey(json),
        colorValue: _intValue(json['color'], fallback: 0xFF115E59),
      );

      db.Category? child;
      final String? childName = target.childName;
      if (childName != null &&
          childName.trim().isNotEmpty &&
          childName.trim().toLowerCase() != parent.name.trim().toLowerCase()) {
        child = await _findOrCreateCategory(
          knownCategories: knownCategories,
          name: childName,
          parentId: parent.id,
          type: categoryType,
          iconKey: _mapCategoryIconKey(json),
          colorValue: _intValue(json['color'], fallback: parent.colorValue),
        );
      }

      result[sourceCategoryId] = _ResolvedCategory(
        parentId: parent.id,
        childId: child?.id,
      );
    }

    return result;
  }

  Future<db.Category> _findOrCreateCategory({
    required List<db.Category> knownCategories,
    required String name,
    required String? parentId,
    required CategoryType type,
    required String iconKey,
    required int colorValue,
  }) async {
    final db.Category? existing = _findCategory(
      knownCategories,
      name: name,
      parentId: parentId,
      type: type,
    );
    if (existing != null) {
      return existing;
    }

    final String id = _uniqueCategoryId(
      knownCategories,
      _buildCategoryId(type: type, name: name, parentId: parentId),
    );

    final DateTime now = DateTime.now();
    final db.Category created = db.Category(
      id: id,
      name: name,
      parentId: parentId,
      type: type.name,
      iconKey: iconKey,
      colorValue: colorValue,
      sortOrder: _nextCategorySortOrder(knownCategories, parentId: parentId),
      isActive: true,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );

    await _database.into(_database.categories).insert(created);
    knownCategories.add(created);

    return created;
  }

  db.Category? _findCategory(
      List<db.Category> categories, {
        required String name,
        required String? parentId,
        required CategoryType type,
      }) {
    final String normalizedName = _normalizeName(name);

    for (final category in categories) {
      if (_normalizeName(category.name) != normalizedName) {
        continue;
      }
      if (category.parentId != parentId) {
        continue;
      }

      final CategoryType existingType = _mapCategoryType(category.type);
      if (_isCompatibleCategoryType(existingType, type)) {
        return category;
      }
    }

    return null;
  }

  bool _isCompatibleCategoryType(CategoryType existing, CategoryType requested) {
    return existing == requested || existing == CategoryType.both;
  }

  int _nextCategorySortOrder(
      List<db.Category> categories, {
        required String? parentId,
      }) {
    int maxSortOrder = -1;
    for (final category in categories) {
      if (category.parentId == parentId && category.sortOrder > maxSortOrder) {
        maxSortOrder = category.sortOrder;
      }
    }
    return maxSortOrder + 1;
  }

  String _uniqueCategoryId(List<db.Category> categories, String baseId) {
    String candidate = baseId;
    int counter = 2;
    while (categories.any((category) => category.id == candidate)) {
      candidate = '${baseId}_$counter';
      counter++;
    }
    return candidate;
  }

  String _buildCategoryId({
    required CategoryType type,
    required String name,
    required String? parentId,
  }) {
    final String prefix = parentId == null ? 'import_parent' : 'import_child';
    final String source = parentId == null
        ? '${type.name}_$name'
        : '${type.name}_${parentId}_$name';
    return '${prefix}_${_slug(source)}';
  }

  _CategoryTarget _categoryTargetFromJson(Map<String, Object?> json) {
    final String? parentFromJson = _nullableString(
      json['mapped_parent_category'],
    ) ??
        _nullableString(json['category_parent_name']);
    final String? childFromJson = _nullableString(
      json['mapped_child_category'],
    ) ??
        _nullableString(json['category_child_name']);

    if (parentFromJson != null) {
      return _CategoryTarget(
        parentName: parentFromJson,
        childName: childFromJson,
      );
    }

    final String? path = _nullableString(json['mapped_category_path']) ??
        _nullableString(json['category_path']);
    if (path != null) {
      final List<String> parts = path
          .split('>')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      if (parts.length >= 2) {
        return _CategoryTarget(parentName: parts.first, childName: parts.last);
      }
      if (parts.length == 1) {
        return _CategoryTarget(parentName: parts.first);
      }
    }

    final _CategoryTarget? legacyTarget =
    _legacyCategoryTargetsByUid[_stringValue(json['uid'])];
    if (legacyTarget != null) {
      return legacyTarget;
    }

    return _CategoryTarget(parentName: _categoryName(json));
  }

  CategoryType _targetCategoryType(
      _CategoryTarget target, {
        required Object? rawType,
      }) {
    if (_normalizeName(target.parentName) == _normalizeName('Other')) {
      return CategoryType.both;
    }
    if (_normalizeName(target.parentName) == _normalizeName('Income')) {
      return CategoryType.income;
    }
    return _mapCategoryType(rawType);
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
    final String title = _nonEmptyOrFallback(json['source_title'], fallback: '');
    if (title.isNotEmpty) {
      return title;
    }

    final String mappedTitle = _nonEmptyOrFallback(json['title'], fallback: '');
    if (mappedTitle.isNotEmpty) {
      return mappedTitle;
    }

    final String uid = _stringValue(json['uid']);
    if (uid.startsWith('Default') && uid.length > 'Default'.length) {
      return _humanize(uid.substring('Default'.length));
    }

    return _humanize(uid);
  }

  String _mapCategoryIconKey(Map<String, Object?> json) {
    final _CategoryTarget target = _categoryTargetFromJson(json);
    final String parentName = target.parentName.toLowerCase();
    final String? childName = target.childName?.toLowerCase();
    final String icon = _stringValue(json['icon']).toLowerCase();

    if (parentName.contains('car') ||
        parentName.contains('transport') ||
        icon.contains('car') ||
        icon.contains('transport')) {
      return 'car';
    }
    if (parentName.contains('income') ||
        parentName.contains('debt') ||
        childName?.contains('loan') == true ||
        icon.contains('salary') ||
        icon.contains('bank') ||
        icon.contains('payment') ||
        icon.contains('prepaid')) {
      return 'salary';
    }
    if (parentName.contains('home') || icon.contains('home')) {
      return 'home';
    }
    if (parentName.contains('health') ||
        childName?.contains('gym') == true ||
        icon.contains('health') ||
        icon.contains('dent') ||
        icon.contains('sport')) {
      return 'health';
    }
    if (parentName.contains('shopping') ||
        parentName.contains('food') ||
        childName?.contains('coffee') == true ||
        icon.contains('sale') ||
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
    if (type == 'both') {
      return CategoryType.both;
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

  String _normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _slug(String value) {
    final String slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return slug.isEmpty ? 'category' : slug;
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

class _CategoryTarget {
  const _CategoryTarget({required this.parentName, this.childName});

  final String parentName;
  final String? childName;
}

class _ResolvedCategory {
  const _ResolvedCategory({required this.parentId, required this.childId});

  final String parentId;
  final String? childId;
}

const Map<String, _CategoryTarget> _legacyCategoryTargetsByUid =
<String, _CategoryTarget>{
  'b9d7347b-622b-4e67-9349-759fd19640d8': _CategoryTarget(
    parentName: 'Shopping',
  ),
  'cac0fa99-8200-45fc-a99c-d30d25f88f8e': _CategoryTarget(
    parentName: 'Car / Transport',
  ),
  '457733a1-cec9-43cf-984b-dfc909603f48': _CategoryTarget(
    parentName: 'Work',
  ),
  '34b32a30-c6c4-4750-99d9-a7c7e60e1913': _CategoryTarget(
    parentName: 'Food',
  ),
  'DefaultCafe': _CategoryTarget(parentName: 'Food', childName: 'Coffee'),
  '2699b859-03cb-496e-a251-01cb5b83c895': _CategoryTarget(
    parentName: 'Travel',
  ),
  'DefaultHealth': _CategoryTarget(parentName: 'Health'),
  '0b11c4a6-dc09-457f-9391-ff13d0315cc3': _CategoryTarget(
    parentName: 'Pet',
  ),
  'fe000a4a-3efa-47e7-b756-0e99e0c4d666': _CategoryTarget(
    parentName: 'Debt',
    childName: 'Giving Loan',
  ),
  'fbc38788-7a49-4d42-bb6a-8709fcdd4c62': _CategoryTarget(
    parentName: 'Personal Care',
  ),
  '4ea104f4-7c79-46e4-a1bf-4ca5c1141d6a': _CategoryTarget(
    parentName: 'Entertainment',
    childName: 'Night Out',
  ),
  'DefaultHome': _CategoryTarget(parentName: 'Home'),
  'DefaultProducts': _CategoryTarget(parentName: 'Shopping'),
  'DefaultPresents': _CategoryTarget(
    parentName: 'Family & Friends',
    childName: 'Gifts',
  ),
  'DefaultFamily': _CategoryTarget(parentName: 'Family & Friends'),
  'DefaultSport': _CategoryTarget(parentName: 'Health', childName: 'Gym'),
  'DefaultLeisure': _CategoryTarget(parentName: 'Entertainment'),
  'DefaultEducation': _CategoryTarget(parentName: 'Education'),
  'DefaultTransport': _CategoryTarget(parentName: 'Car / Transport'),
  'other_expense': _CategoryTarget(parentName: 'Other'),
  '3b9ef2eb-65b9-4f5b-b39a-b1c494036620': _CategoryTarget(
    parentName: 'Travel',
    childName: 'Spain',
  ),
  'baa0ce6c-aad9-4c0e-9e7c-45f10504fa7c': _CategoryTarget(
    parentName: 'Travel',
    childName: 'Vacation',
  ),
  'f1ba0e01-a80e-4929-bf60-1618e9a440f6': _CategoryTarget(
    parentName: 'Debt',
    childName: 'Loan Return',
  ),
  'c70c801e-d044-4744-a799-cccdc1273e4d': _CategoryTarget(
    parentName: 'Wedding',
  ),
  '3f1ae531-5327-4a99-b976-d610ceb6c0c3': _CategoryTarget(
    parentName: 'Car / Transport',
    childName: 'New Car',
  ),
  '9d09b9bb-6985-4fed-81af-8f7c65d8adb4': _CategoryTarget(
    parentName: 'Shopping',
    childName: 'Electronics',
  ),
  '69fa57a6-689b-47a2-8d70-3fef11ecf6ec': _CategoryTarget(
    parentName: 'Home',
    childName: 'Renovation',
  ),
  'c1d9277b-e4b6-46c4-9b20-92a3e1a625f0': _CategoryTarget(
    parentName: 'Debt',
    childName: 'Loan Payment',
  ),
  '5c5e123f-245d-4e95-b033-8f396d342e84': _CategoryTarget(
    parentName: 'Home',
    childName: 'New Home',
  ),
  'DefaultSalary': _CategoryTarget(parentName: 'Income', childName: 'Salary'),
  '9e01c040-ea6e-4cd0-9222-22568b3c3e62': _CategoryTarget(
    parentName: 'Income',
    childName: 'Freelance',
  ),
  'DefaultPresent': _CategoryTarget(parentName: 'Other'),
  'DefaultPercents': _CategoryTarget(parentName: 'Other'),
  'other_income': _CategoryTarget(parentName: 'Other'),
  'be75f31e-c0c5-4eda-8264-6dfaf27c5d89': _CategoryTarget(
    parentName: 'Income',
    childName: 'Loan Return',
  ),
  '25f4ea01-2940-4e5e-a0fe-47493f5bfef3': _CategoryTarget(
    parentName: 'Income',
    childName: 'Loan Received',
  ),
  '1799a735-529a-4e03-b2b3-47f592817b1c': _CategoryTarget(
    parentName: 'Income',
    childName: 'Loan Investment',
  ),
  '25b92bbb-3a66-4128-9401-9cfd37c5f380': _CategoryTarget(
    parentName: 'Income',
    childName: 'Home Reimbursement',
  ),
};
