import 'package:money_manager/domain/entities/recurring_rule.dart';
import 'package:money_manager/domain/enums/recurring_frequency.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';

abstract class RecurringRuleRepository {
  Stream<List<RecurringRule>> watchRecurringRules({bool archivedOnly = false});

  Future<void> createRecurringRule(CreateRecurringRuleInput input);

  Future<void> updateRecurringRule(String id, UpdateRecurringRuleInput input);

  Future<void> softDeleteRecurringRule(String id);

  Future<void> restoreRecurringRule(String id);
}

class CreateRecurringRuleInput {
  const CreateRecurringRuleInput({
    required this.title,
    required this.type,
    required this.frequency,
    required this.accountId,
    required this.amountMinor,
    required this.startDate,
    required this.nextDueDate,
    this.intervalCount = 1,
    this.destinationAccountId,
    this.categoryId,
    this.childCategoryId,
    this.note = '',
    this.endDate,
    this.reminderDaysBefore = 0,
    this.autoCreate = false,
  });

  final String title;
  final TransactionType type;
  final RecurringFrequency frequency;
  final int intervalCount;
  final String accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? childCategoryId;
  final int amountMinor;
  final String note;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime nextDueDate;
  final int reminderDaysBefore;
  final bool autoCreate;
}

class UpdateRecurringRuleInput {
  const UpdateRecurringRuleInput({
    required this.title,
    required this.type,
    required this.frequency,
    required this.accountId,
    required this.amountMinor,
    required this.startDate,
    required this.nextDueDate,
    required this.isActive,
    this.intervalCount = 1,
    this.destinationAccountId,
    this.categoryId,
    this.childCategoryId,
    this.note = '',
    this.endDate,
    this.reminderDaysBefore = 0,
    this.autoCreate = false,
  });

  final String title;
  final TransactionType type;
  final RecurringFrequency frequency;
  final int intervalCount;
  final String accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? childCategoryId;
  final int amountMinor;
  final String note;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime nextDueDate;
  final int reminderDaysBefore;
  final bool autoCreate;
  final bool isActive;
}
