import 'package:money_manager/domain/enums/transaction_type.dart';

class RecurringRuleRun {
  const RecurringRuleRun({
    required this.id,
    required this.recurringRuleId,
    required this.title,
    required this.type,
    required this.accountName,
    required this.amountMinor,
    required this.scheduledFor,
    required this.status,
    this.destinationAccountName,
    this.transactionId,
  });

  final String id;
  final String recurringRuleId;
  final String title;
  final TransactionType type;
  final String accountName;
  final String? destinationAccountName;
  final int amountMinor;
  final DateTime scheduledFor;
  final String status;
  final String? transactionId;
}
