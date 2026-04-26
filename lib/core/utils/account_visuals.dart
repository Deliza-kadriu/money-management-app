import 'package:flutter/material.dart';

class AccountVisuals {
  const AccountVisuals._();

  static const List<int> palette = <int>[
    0xFF115E59,
    0xFFD97706,
    0xFF1D4ED8,
    0xFFBE185D,
    0xFF7C3AED,
  ];

  static const Map<String, IconData> iconMap = <String, IconData>{
    'bank': Icons.account_balance_rounded,
    'wallet': Icons.wallet_rounded,
    'credit_card': Icons.credit_card_rounded,
    'savings': Icons.savings_rounded,
    'account': Icons.account_balance_wallet_rounded,
  };

  static Color colorFromValue(int colorValue) => Color(colorValue);

  static IconData iconFromKey(String key) =>
      iconMap[key] ?? Icons.account_balance_wallet_rounded;
}
