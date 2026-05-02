import 'package:money_manager/domain/enums/transaction_type.dart';

class MoneyTransaction {
  const MoneyTransaction({
    required this.id,
    required this.type,
    required this.accountId,
    required this.accountName,
    required this.amountMinor,
    required this.transactionDate,
    required this.note,
    this.source,
    this.loanId,
    this.loanInstallmentId,
    this.destinationAccountId,
    this.destinationAccountName,
    this.categoryId,
    this.categoryName,
    this.childCategoryId,
    this.childCategoryName,
    this.attachmentFilePaths = const <String>[],
    this.deletedAt,
  });

  final String id;
  final TransactionType type;
  final String accountId;
  final String accountName;
  final String? destinationAccountId;
  final String? destinationAccountName;
  final int amountMinor;
  final DateTime transactionDate;
  final String note;
  final String? source;
  final String? loanId;
  final String? loanInstallmentId;
  final String? categoryId;
  final String? categoryName;
  final String? childCategoryId;
  final String? childCategoryName;
  final List<String> attachmentFilePaths;
  final DateTime? deletedAt;
}
