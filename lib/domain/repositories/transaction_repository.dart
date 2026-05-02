import 'package:money_manager/domain/entities/dashboard_summary.dart';
import 'package:money_manager/domain/entities/money_transaction.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';

abstract class TransactionRepository {
  Stream<List<MoneyTransaction>> watchTransactions({bool archivedOnly = false});

  Stream<List<MoneyTransaction>> watchRecentTransactions({int limit = 5});

  Stream<DashboardSummary> watchDashboardSummary();

  Future<String> createTransaction(CreateTransactionInput input);

  Future<void> updateTransaction(String id, CreateTransactionInput input);

  Future<void> softDeleteTransaction(String id);

  Future<void> restoreTransaction(String id);
}

class CreateTransactionInput {
  const CreateTransactionInput({
    required this.type,
    required this.accountId,
    required this.amountMinor,
    required this.transactionDate,
    required this.note,
    this.source,
    this.loanId,
    this.loanInstallmentId,
    this.destinationAccountId,
    this.categoryId,
    this.childCategoryId,
    this.recurringRuleId,
    this.attachmentFilePaths = const <String>[],
  });

  final TransactionType type;
  final String accountId;
  final String? destinationAccountId;
  final int amountMinor;
  final DateTime transactionDate;
  final String note;
  final String? source;
  final String? loanId;
  final String? loanInstallmentId;
  final String? categoryId;
  final String? childCategoryId;
  final String? recurringRuleId;
  final List<String> attachmentFilePaths;
}
