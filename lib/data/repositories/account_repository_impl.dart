import 'package:drift/drift.dart';
import 'package:money_manager/core/utils/account_visuals.dart';
import 'package:money_manager/data/local/db/app_database.dart';
import 'package:money_manager/domain/entities/account.dart' as domain;
import 'package:money_manager/domain/enums/account_type.dart';
import 'package:money_manager/domain/repositories/account_repository.dart';
import 'package:uuid/uuid.dart';

class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl(this._database);

  final AppDatabase _database;
  final Uuid _uuid = const Uuid();

  @override
  Stream<List<domain.Account>> watchAccounts({bool archivedOnly = false}) {
    final query = _database.select(_database.accounts)
      ..where(
        (tbl) =>
            archivedOnly ? tbl.deletedAt.isNotNull() : tbl.deletedAt.isNull(),
      )
      ..orderBy(<OrderingTerm Function($AccountsTable)>[
        (tbl) => OrderingTerm.asc(tbl.name),
      ]);

    return query.watch().map(
      (rows) => rows.map(_mapAccountRow).toList(growable: false),
    );
  }

  @override
  Future<void> createAccount(CreateAccountInput input) async {
    final DateTime now = DateTime.now();
    await _database.transaction(() async {
      if (input.isDefault) {
        await _clearDefaultAccount();
      }

      await _database.into(_database.accounts).insert(
          AccountsCompanion.insert(
            id: _uuid.v4(),
            name: input.name.trim(),
            type: input.type.name,
            openingBalanceMinor: Value(input.openingBalanceMinor),
            currentBalanceMinor: Value(input.openingBalanceMinor),
            currencyCode: Value(input.currencyCode),
            colorValue: input.colorValue,
            iconKey: Value(input.iconKey),
            isActive: Value(input.isActive),
            excludeFromTotals: Value(input.excludeFromTotals),
            isDefault: Value(input.isDefault),
            createdAt: now,
            updatedAt: now,
          ),
        );
    });
  }

  @override
  Future<void> updateAccount(String id, UpdateAccountInput input) async {
    final DateTime now = DateTime.now();
    await _database.transaction(() async {
      if (input.isDefault) {
        await _clearDefaultAccount(exceptId: id);
      }

      await (_database.update(
        _database.accounts,
      )..where((tbl) => tbl.id.equals(id))).write(
        AccountsCompanion(
          name: Value(input.name.trim()),
          type: Value(input.type.name),
          currencyCode: Value(input.currencyCode),
          colorValue: Value(input.colorValue),
          iconKey: Value(input.iconKey),
          isActive: Value(input.isActive),
          excludeFromTotals: Value(input.excludeFromTotals),
          isDefault: Value(input.isDefault),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<void> softDeleteAccount(String id) async {
    final DateTime now = DateTime.now();

    await (_database.update(
      _database.accounts,
    )..where((tbl) => tbl.id.equals(id))).write(
      AccountsCompanion(
        isActive: const Value(false),
        updatedAt: Value(now),
        deletedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> restoreAccount(String id) async {
    final DateTime now = DateTime.now();

    await (_database.update(
      _database.accounts,
    )..where((tbl) => tbl.id.equals(id))).write(
      AccountsCompanion(
        isActive: const Value(true),
        updatedAt: Value(now),
        deletedAt: const Value(null),
      ),
    );
  }

  domain.Account _mapAccountRow(Account row) {
    final AccountType type = AccountType.values.firstWhere(
      (value) => value.name == row.type,
      orElse: () => AccountType.other,
    );

    return domain.Account(
      id: row.id,
      name: row.name,
      type: type,
      openingBalanceMinor: row.openingBalanceMinor,
      currentBalanceMinor: row.currentBalanceMinor,
      currencyCode: row.currencyCode,
      colorValue: row.colorValue,
      iconKey: row.iconKey,
      color: AccountVisuals.colorFromValue(row.colorValue),
      icon: AccountVisuals.iconFromKey(row.iconKey),
      isActive: row.isActive,
      excludeFromTotals: row.excludeFromTotals,
      isDefault: row.isDefault,
    );
  }

  Future<void> _clearDefaultAccount({String? exceptId}) async {
    final update = _database.update(_database.accounts)
      ..where((tbl) {
        final base = tbl.isDefault.equals(true);
        if (exceptId == null) {
          return base;
        }
        return base & tbl.id.isNotValue(exceptId);
      });

    await update.write(
      const AccountsCompanion(
        isDefault: Value(false),
      ),
    );
  }
}
