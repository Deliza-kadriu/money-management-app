import 'package:drift/drift.dart' as drift;
import 'package:money_manager/core/utils/category_visuals.dart';
import 'package:money_manager/data/local/db/app_database.dart';
import 'package:money_manager/domain/enums/category_type.dart';

class CategorySeedService {
  CategorySeedService(this._database);

  final AppDatabase _database;

  Future<void> seedDefaultsIfEmpty() async {
    final List<Category> existingCategories = await _database
        .select(_database.categories)
        .get();
    if (existingCategories.isNotEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    int parentSortOrder = 0;

    await _database.batch((batch) {
      for (final _SeedParentCategory parent in _defaultCategories) {
        parentSortOrder += 1;
        batch.insert(
          _database.categories,
          CategoriesCompanion.insert(
            id: parent.id,
            name: parent.name,
            parentId: const drift.Value(null),
            type: parent.type.name,
            iconKey: drift.Value(parent.iconKey),
            colorValue: parent.colorValue,
            sortOrder: drift.Value(parentSortOrder * 100),
            isActive: const drift.Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );

        int childOffset = 0;
        for (final String childName in parent.children) {
          childOffset += 1;
          batch.insert(
            _database.categories,
            CategoriesCompanion.insert(
              id: '${parent.id}-$childOffset',
              name: childName,
              parentId: drift.Value(parent.id),
              type: parent.type.name,
              iconKey: drift.Value(parent.iconKey),
              colorValue: parent.colorValue,
              sortOrder: drift.Value((parentSortOrder * 100) + childOffset),
              isActive: const drift.Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      }
    });
  }
}

class _SeedParentCategory {
  const _SeedParentCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.iconKey,
    required this.colorValue,
    required this.children,
  });

  final String id;
  final String name;
  final CategoryType type;
  final String iconKey;
  final int colorValue;
  final List<String> children;
}

final List<_SeedParentCategory> _defaultCategories = <_SeedParentCategory>[
  _SeedParentCategory(
    id: 'seed-food',
    name: 'Food',
    type: CategoryType.expense,
    iconKey: 'shopping',
    colorValue: CategoryVisuals.palette[0],
    children: <String>['Groceries', 'Restaurants', 'Coffee', 'Delivery'],
  ),
  _SeedParentCategory(
    id: 'seed-car-transport',
    name: 'Car / Transport',
    type: CategoryType.expense,
    iconKey: 'car',
    colorValue: CategoryVisuals.palette[1],
    children: <String>['Gas', 'Maintenance', 'Parking', 'Public Transport'],
  ),
  _SeedParentCategory(
    id: 'seed-home',
    name: 'Home',
    type: CategoryType.expense,
    iconKey: 'home',
    colorValue: CategoryVisuals.palette[2],
    children: <String>['Rent', 'Utilities', 'Internet', 'Repairs'],
  ),
  _SeedParentCategory(
    id: 'seed-shopping',
    name: 'Shopping',
    type: CategoryType.expense,
    iconKey: 'shopping',
    colorValue: CategoryVisuals.palette[3],
    children: <String>['Clothes', 'Electronics', 'Beauty', 'Gifts'],
  ),
  _SeedParentCategory(
    id: 'seed-health',
    name: 'Health',
    type: CategoryType.expense,
    iconKey: 'health',
    colorValue: CategoryVisuals.palette[4],
    children: <String>['Doctor', 'Pharmacy', 'Dentist', 'Gym'],
  ),
  _SeedParentCategory(
    id: 'seed-travel',
    name: 'Travel',
    type: CategoryType.expense,
    iconKey: 'category',
    colorValue: CategoryVisuals.palette[5],
    children: <String>['Hotel', 'Flight', 'Transport', 'Activities'],
  ),
  _SeedParentCategory(
    id: 'seed-entertainment',
    name: 'Entertainment',
    type: CategoryType.expense,
    iconKey: 'category',
    colorValue: CategoryVisuals.palette[0],
    children: <String>['Movies / Events', 'Subscriptions', 'Games', 'Hobbies'],
  ),
  _SeedParentCategory(
    id: 'seed-family-friends',
    name: 'Family & Friends',
    type: CategoryType.expense,
    iconKey: 'category',
    colorValue: CategoryVisuals.palette[1],
    children: <String>['Gifts', 'Family Support', 'Kids'],
  ),
  _SeedParentCategory(
    id: 'seed-personal-care',
    name: 'Personal Care',
    type: CategoryType.expense,
    iconKey: 'health',
    colorValue: CategoryVisuals.palette[2],
    children: <String>['Hairdresser', 'Nails', 'Skincare'],
  ),
  _SeedParentCategory(
    id: 'seed-work',
    name: 'Work',
    type: CategoryType.expense,
    iconKey: 'category',
    colorValue: CategoryVisuals.palette[3],
    children: <String>['Software', 'Equipment', 'Office Supplies'],
  ),
  _SeedParentCategory(
    id: 'seed-savings',
    name: 'Savings',
    type: CategoryType.expense,
    iconKey: 'salary',
    colorValue: CategoryVisuals.palette[4],
    children: <String>['Emergency Fund', 'Savings Goal', 'Investments'],
  ),
  _SeedParentCategory(
    id: 'seed-debt',
    name: 'Debt',
    type: CategoryType.expense,
    iconKey: 'salary',
    colorValue: CategoryVisuals.palette[5],
    children: <String>['Loan Payment', 'Credit Card', 'Fees'],
  ),
  _SeedParentCategory(
    id: 'seed-income',
    name: 'Income',
    type: CategoryType.income,
    iconKey: 'salary',
    colorValue: CategoryVisuals.palette[0],
    children: <String>['Salary', 'Freelance', 'Bonus', 'Refund'],
  ),
  _SeedParentCategory(
    id: 'seed-other',
    name: 'Other',
    type: CategoryType.both,
    iconKey: 'category',
    colorValue: CategoryVisuals.palette[1],
    children: <String>['Uncategorized', 'Cash Withdrawal', 'Miscellaneous'],
  ),
];
