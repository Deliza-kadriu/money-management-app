import 'package:money_manager/domain/entities/category.dart';
import 'package:money_manager/domain/enums/category_type.dart';

abstract class CategoryRepository {
  Stream<List<Category>> watchActiveCategories();

  Future<void> createCategory(CreateCategoryInput input);

  Future<void> updateCategory(String id, UpdateCategoryInput input);

  Future<void> softDeleteCategory(String id);
}

class CreateCategoryInput {
  const CreateCategoryInput({
    required this.name,
    required this.parentId,
    required this.type,
    required this.iconKey,
    required this.colorValue,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String name;
  final String? parentId;
  final CategoryType type;
  final String iconKey;
  final int colorValue;
  final int sortOrder;
  final bool isActive;
}

class UpdateCategoryInput {
  const UpdateCategoryInput({
    required this.name,
    required this.parentId,
    required this.type,
    required this.iconKey,
    required this.colorValue,
    required this.sortOrder,
    required this.isActive,
  });

  final String name;
  final String? parentId;
  final CategoryType type;
  final String iconKey;
  final int colorValue;
  final int sortOrder;
  final bool isActive;
}
