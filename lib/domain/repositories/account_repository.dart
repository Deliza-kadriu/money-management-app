import 'package:money_manager/domain/entities/account.dart';
import 'package:money_manager/domain/enums/account_type.dart';

abstract class AccountRepository {
  Stream<List<Account>> watchActiveAccounts();

  Future<void> createAccount(CreateAccountInput input);

  Future<void> updateAccount(String id, UpdateAccountInput input);

  Future<void> softDeleteAccount(String id);
}

class CreateAccountInput {
  const CreateAccountInput({
    required this.name,
    required this.type,
    required this.openingBalanceMinor,
    required this.currencyCode,
    required this.colorValue,
    required this.iconKey,
    this.isActive = true,
  });

  final String name;
  final AccountType type;
  final int openingBalanceMinor;
  final String currencyCode;
  final int colorValue;
  final String iconKey;
  final bool isActive;
}

class UpdateAccountInput {
  const UpdateAccountInput({
    required this.name,
    required this.type,
    required this.currencyCode,
    required this.colorValue,
    required this.iconKey,
    required this.isActive,
  });

  final String name;
  final AccountType type;
  final String currencyCode;
  final int colorValue;
  final String iconKey;
  final bool isActive;
}
