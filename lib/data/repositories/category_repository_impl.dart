import 'package:drift/drift.dart';
import 'package:money_manager/core/utils/category_visuals.dart';
import 'package:money_manager/data/local/db/app_database.dart';
import 'package:money_manager/domain/entities/category.dart' as domain;
import 'package:money_manager/domain/enums/category_type.dart';
import 'package:money_manager/domain/repositories/category_repository.dart';
import 'package:uuid/uuid.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl(this._database);

  final AppDatabase _database;
  final Uuid _uuid = const Uuid();

  @override
  Stream<List<domain.Category>> watchActiveCategories() {
    final query = _database.select(_database.categories)
      ..where((tbl) => tbl.deletedAt.isNull())
      ..orderBy(<OrderingTerm Function($CategoriesTable)>[
        (tbl) => OrderingTerm.asc(tbl.sortOrder),
        (tbl) => OrderingTerm.asc(tbl.name),
      ]);

    return query.watch().map(
      (rows) => rows.map(_mapCategoryRow).toList(growable: false),
    );
  }

  @override
  Future<void> createCategory(CreateCategoryInput input) async {
    final DateTime now = DateTime.now();

    await _database
        .into(_database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: _uuid.v4(),
            name: input.name.trim(),
            parentId: Value(input.parentId),
            type: input.type.name,
            iconKey: Value(input.iconKey),
            colorValue: input.colorValue,
            sortOrder: Value(input.sortOrder),
            isActive: Value(input.isActive),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  @override
  Future<void> updateCategory(String id, UpdateCategoryInput input) async {
    final DateTime now = DateTime.now();

    await (_database.update(
      _database.categories,
    )..where((tbl) => tbl.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(input.name.trim()),
        parentId: Value(input.parentId),
        type: Value(input.type.name),
        iconKey: Value(input.iconKey),
        colorValue: Value(input.colorValue),
        sortOrder: Value(input.sortOrder),
        isActive: Value(input.isActive),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> softDeleteCategory(String id) async {
    final DateTime now = DateTime.now();

    await (_database.update(
      _database.categories,
    )..where((tbl) => tbl.id.equals(id))).write(
      CategoriesCompanion(
        isActive: const Value(false),
        updatedAt: Value(now),
        deletedAt: Value(now),
      ),
    );
  }

  domain.Category _mapCategoryRow(Category row) {
    final CategoryType type = CategoryType.values.firstWhere(
      (value) => value.name == row.type,
      orElse: () => CategoryType.expense,
    );

    return domain.Category(
      id: row.id,
      name: row.name,
      parentId: row.parentId,
      type: type,
      iconKey: row.iconKey,
      colorValue: row.colorValue,
      sortOrder: row.sortOrder,
      isActive: row.isActive,
      color: CategoryVisuals.colorFromValue(row.colorValue),
    );
  }
}
