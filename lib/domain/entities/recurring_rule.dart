import 'package:money_manager/domain/enums/recurring_frequency.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';

class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.title,
    required this.type,
    required this.frequency,
    required this.intervalCount,
    required this.accountId,
    required this.accountName,
    required this.amountMinor,
    required this.startDate,
    required this.nextDueDate,
    required this.reminderDaysBefore,
    required this.isActive,
    required this.autoCreate,
    this.destinationAccountId,
    this.destinationAccountName,
    this.categoryId,
    this.categoryName,
    this.childCategoryId,
    this.childCategoryName,
    this.note = '',
    this.endDate,
    this.deletedAt,
  });

  final String id;
  final String title;
  final TransactionType type;
  final RecurringFrequency frequency;
  final int intervalCount;
  final String accountId;
  final String accountName;
  final String? destinationAccountId;
  final String? destinationAccountName;
  final String? categoryId;
  final String? categoryName;
  final String? childCategoryId;
  final String? childCategoryName;
  final int amountMinor;
  final String note;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime nextDueDate;
  final int reminderDaysBefore;
  final bool autoCreate;
  final bool isActive;
  final DateTime? deletedAt;
}
