import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ExcelExportService {
  Future<String> exportReport({
    required String periodLabel,
    required int incomeMinor,
    required int expenseMinor,
    required int netMinor,
    required List<ExportCategoryRow> categoryRows,
    required List<ExportAccountRow> accountRows,
    required List<ExportTransactionRow> transactionRows,
  }) async {
    final Excel excel = Excel.createExcel();

    final Sheet summarySheet = excel['Summary'];
    summarySheet.appendRow(<CellValue>[
      TextCellValue('Money Manager Report'),
      TextCellValue(periodLabel),
    ]);
    summarySheet.appendRow(<CellValue>[
      TextCellValue('Income'),
      IntCellValue(incomeMinor),
    ]);
    summarySheet.appendRow(<CellValue>[
      TextCellValue('Expense'),
      IntCellValue(expenseMinor),
    ]);
    summarySheet.appendRow(<CellValue>[
      TextCellValue('Net'),
      IntCellValue(netMinor),
    ]);

    final Sheet categorySheet = excel['Category Breakdown'];
    categorySheet.appendRow(<CellValue>[
      TextCellValue('Category'),
      TextCellValue('Amount Minor'),
    ]);
    for (final row in categoryRows) {
      categorySheet.appendRow(<CellValue>[
        TextCellValue(row.label),
        IntCellValue(row.amountMinor),
      ]);
    }

    final Sheet accountSheet = excel['Account Balances'];
    accountSheet.appendRow(<CellValue>[
      TextCellValue('Account'),
      TextCellValue('Balance Minor'),
    ]);
    for (final row in accountRows) {
      accountSheet.appendRow(<CellValue>[
        TextCellValue(row.name),
        IntCellValue(row.balanceMinor),
      ]);
    }

    final Sheet transactionSheet = excel['Transactions'];
    transactionSheet.appendRow(<CellValue>[
      TextCellValue('Date'),
      TextCellValue('Type'),
      TextCellValue('Account'),
      TextCellValue('Destination Account'),
      TextCellValue('Category'),
      TextCellValue('Child Category'),
      TextCellValue('Amount Minor'),
      TextCellValue('Note'),
    ]);
    for (final row in transactionRows) {
      transactionSheet.appendRow(<CellValue>[
        TextCellValue(row.dateLabel),
        TextCellValue(row.typeLabel),
        TextCellValue(row.accountName),
        TextCellValue(row.destinationAccountName ?? ''),
        TextCellValue(row.categoryName ?? ''),
        TextCellValue(row.childCategoryName ?? ''),
        IntCellValue(row.amountMinor),
        TextCellValue(row.note),
      ]);
    }

    excel.delete('Sheet1');

    final List<int>? bytes = excel.save();
    if (bytes == null) {
      throw StateError('Excel export failed: no file bytes were generated.');
    }

    final Directory directory = await getTemporaryDirectory();
    final String timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final String filePath =
        p.join(directory.path, 'money_manager_report_$timestamp.xlsx');
    final File file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    return file.path;
  }
}

class ExportCategoryRow {
  const ExportCategoryRow({
    required this.label,
    required this.amountMinor,
  });

  final String label;
  final int amountMinor;
}

class ExportAccountRow {
  const ExportAccountRow({
    required this.name,
    required this.balanceMinor,
  });

  final String name;
  final int balanceMinor;
}

class ExportTransactionRow {
  const ExportTransactionRow({
    required this.dateLabel,
    required this.typeLabel,
    required this.accountName,
    required this.amountMinor,
    required this.note,
    this.destinationAccountName,
    this.categoryName,
    this.childCategoryName,
  });

  final String dateLabel;
  final String typeLabel;
  final String accountName;
  final String? destinationAccountName;
  final String? categoryName;
  final String? childCategoryName;
  final int amountMinor;
  final String note;
}
