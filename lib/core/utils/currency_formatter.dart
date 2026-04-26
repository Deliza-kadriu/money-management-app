import 'package:intl/intl.dart';

class CurrencyFormatter {
  const CurrencyFormatter._();

  static String formatMinorUnits(
    int amountMinor, {
    String currencySymbol = '\$',
  }) {
    final NumberFormat formatter = NumberFormat.currency(
      symbol: currencySymbol,
      decimalDigits: 2,
    );

    return formatter.format(amountMinor / 100);
  }
}
