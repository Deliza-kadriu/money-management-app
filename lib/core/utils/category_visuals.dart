import 'package:flutter/material.dart';

class CategoryVisuals {
  const CategoryVisuals._();

  static const List<int> palette = <int>[
    0xFF115E59,
    0xFFD97706,
    0xFF1D4ED8,
    0xFFBE185D,
    0xFF7C3AED,
    0xFF0F766E,
  ];

  static const Map<String, IconData> iconMap = <String, IconData>{
    'shopping': Icons.shopping_basket_rounded,
    'car': Icons.directions_car_filled_rounded,
    'salary': Icons.payments_rounded,
    'home': Icons.home_rounded,
    'health': Icons.health_and_safety_rounded,
    'category': Icons.category_rounded,
  };

  static Color colorFromValue(int colorValue) => Color(colorValue);

  static IconData iconFromKey(String key) =>
      iconMap[key] ?? Icons.category_rounded;
}
