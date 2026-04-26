import 'package:flutter/material.dart';
import 'package:money_manager/domain/enums/category_type.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.parentId,
    required this.type,
    required this.iconKey,
    required this.colorValue,
    required this.sortOrder,
    required this.isActive,
    required this.color,
  });

  final String id;
  final String name;
  final String? parentId;
  final CategoryType type;
  final String iconKey;
  final int colorValue;
  final int sortOrder;
  final bool isActive;
  final Color color;

  bool get isParent => parentId == null;
}
