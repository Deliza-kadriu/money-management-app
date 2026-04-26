import 'package:flutter/material.dart';
import 'package:money_manager/domain/enums/account_type.dart';

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalanceMinor,
    required this.currentBalanceMinor,
    required this.currencyCode,
    required this.colorValue,
    required this.iconKey,
    required this.color,
    required this.icon,
    required this.isActive,
  });

  final String id;
  final String name;
  final AccountType type;
  final int openingBalanceMinor;
  final int currentBalanceMinor;
  final String currencyCode;
  final int colorValue;
  final String iconKey;
  final Color color;
  final IconData icon;
  final bool isActive;
}
