import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:money_manager/core/utils/category_visuals.dart';
import 'package:money_manager/data/local/db/app_database.dart';
import 'package:money_manager/domain/entities/loan.dart' as domain;
import 'package:money_manager/domain/entities/loan_details.dart'
    as details_domain;
import 'package:money_manager/domain/entities/loan_installment.dart'
    as installment_domain;
import 'package:money_manager/domain/enums/category_type.dart';
import 'package:money_manager/domain/enums/loan_installment_status.dart';
import 'package:money_manager/domain/enums/loan_status.dart';
import 'package:money_manager/domain/enums/loan_type.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/domain/repositories/loan_repository.dart';
import 'package:money_manager/domain/repositories/transaction_repository.dart';
import 'package:uuid/uuid.dart';

class LoanRepositoryImpl implements LoanRepository {
  LoanRepositoryImpl(this._database, this._transactionRepository);

  final AppDatabase _database;
  final TransactionRepository _transactionRepository;
  final Uuid _uuid = const Uuid();

  @override
  Stream<List<domain.Loan>> watchLoans() {
    final query = _database.select(_database.loans)
      ..orderBy(<OrderingTerm Function($LoansTable)>[
        (tbl) => OrderingTerm.asc(tbl.status),
        (tbl) => OrderingTerm.desc(tbl.createdAt),
      ]);

    return query.watch().map(
      (rows) => rows.map(_mapLoanRow).toList(growable: false),
    );
  }

  @override
  Stream<details_domain.LoanDetails?> watchLoanDetails(String loanId) {
    final loanStream = (_database.select(
      _database.loans,
    )..where((tbl) => tbl.id.equals(loanId))).watchSingleOrNull();
    final installmentStream =
        (_database.select(_database.loanInstallments)
              ..where((tbl) => tbl.loanId.equals(loanId))
              ..orderBy(<OrderingTerm Function($LoanInstallmentsTable)>[
                (tbl) => OrderingTerm.asc(tbl.installmentNumber),
              ]))
            .watch();

    return Stream<details_domain.LoanDetails?>.multi((controller) {
      Loan? latestLoan;
      List<LoanInstallment> latestInstallments = const <LoanInstallment>[];
      bool hasLoanValue = false;
      bool hasInstallmentValue = false;

      void emitIfReady() {
        if (!hasLoanValue || !hasInstallmentValue) {
          return;
        }

        if (latestLoan == null) {
          controller.add(null);
          return;
        }

        controller.add(
          details_domain.LoanDetails(
            loan: _mapLoanRow(latestLoan!),
            installments: latestInstallments
                .map(_mapInstallmentRow)
                .toList(growable: false),
          ),
        );
      }

      final StreamSubscription<Loan?> loanSubscription = loanStream.listen((
        loanRow,
      ) {
        latestLoan = loanRow;
        hasLoanValue = true;
        emitIfReady();
      }, onError: controller.addError);

      final StreamSubscription<List<LoanInstallment>> installmentSubscription =
          installmentStream.listen((rows) {
            latestInstallments = rows;
            hasInstallmentValue = true;
            emitIfReady();
          }, onError: controller.addError);

      controller.onCancel = () async {
        await loanSubscription.cancel();
        await installmentSubscription.cancel();
      };
    });
  }

  @override
  Future<void> createLoan(CreateLoanInput input) async {
    final DateTime now = DateTime.now();
    await _saveLoanDefinition(
      loanId: _uuid.v4(),
      input: input,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> updateLoan(String loanId, CreateLoanInput input) async {
    final Loan existingLoan = await (_database.select(
      _database.loans,
    )..where((tbl) => tbl.id.equals(loanId))).getSingle();
    final int paidInstallmentCount =
        await (_database.select(_database.loanInstallments)..where(
              (tbl) =>
                  tbl.loanId.equals(loanId) &
                  tbl.status.equals(LoanInstallmentStatus.paid.name),
            ))
            .get()
            .then((rows) => rows.length);

    if (paidInstallmentCount > 0) {
      throw StateError(
        'This loan already has paid installments. Undo payments before editing the loan schedule.',
      );
    }

    final DateTime now = DateTime.now();
    await _database.transaction(() async {
      await (_database.delete(
        _database.loanInstallments,
      )..where((tbl) => tbl.loanId.equals(loanId))).go();
      await _saveLoanDefinition(
        loanId: loanId,
        input: input,
        createdAt: existingLoan.createdAt,
        updatedAt: now,
      );
    });
  }

  @override
  Future<void> deleteLoan(String loanId) async {
    final List<LoanInstallment> installments = await (_database.select(
      _database.loanInstallments,
    )..where((tbl) => tbl.loanId.equals(loanId))).get();

    await _database.transaction(() async {
      for (final installment in installments) {
        if (installment.transactionId != null) {
          await _transactionRepository.softDeleteTransaction(
            installment.transactionId!,
          );
        }
      }

      await (_database.delete(
        _database.loanInstallments,
      )..where((tbl) => tbl.loanId.equals(loanId))).go();
      await (_database.delete(
        _database.loans,
      )..where((tbl) => tbl.id.equals(loanId))).go();
    });
  }

  Future<void> _saveLoanDefinition({
    required String loanId,
    required CreateLoanInput input,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final double monthlyPaymentRaw = _calculateMonthlyPayment(
      loanAmountMinor: input.totalAmountMinor,
      annualInterestRate: input.interestRate,
      numberOfInstallments: input.numberOfInstallments,
    );
    final int monthlyPaymentMinor = monthlyPaymentRaw.round();
    final List<_InstallmentScheduleRow> schedule = _buildSchedule(
      loanId: loanId,
      startDate: input.startDate,
      totalAmountMinor: input.totalAmountMinor,
      annualInterestRate: input.interestRate,
      numberOfInstallments: input.numberOfInstallments,
      monthlyPaymentMinor: monthlyPaymentMinor,
      timestamp: updatedAt,
    );

    await _database
        .into(_database.loans)
        .insertOnConflictUpdate(
          Loan(
            id: loanId,
            loanName: input.loanName.trim(),
            loanType: input.loanType.name,
            bankName: input.bankName.trim(),
            accountId: input.accountId,
            categoryId: input.categoryId,
            childCategoryId: input.childCategoryId,
            totalAmountMinor: input.totalAmountMinor,
            interestRate: input.interestRate,
            startDate: input.startDate,
            endDate: schedule.last.dueDate,
            numberOfInstallments: input.numberOfInstallments,
            monthlyPaymentMinor: monthlyPaymentMinor,
            remainingBalanceMinor: input.totalAmountMinor,
            paidInstallments: 0,
            status: LoanStatus.active.name,
            remindersEnabled: input.remindersEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
        );

    await _database.batch((batch) {
      batch.insertAll(
        _database.loanInstallments,
        schedule
            .map(
              (row) => LoanInstallment(
                id: row.id,
                loanId: loanId,
                installmentNumber: row.installmentNumber,
                dueDate: row.dueDate,
                amountMinor: row.amountMinor,
                principalAmountMinor: row.principalAmountMinor,
                interestAmountMinor: row.interestAmountMinor,
                remainingBalanceMinor: row.remainingBalanceMinor,
                status: LoanInstallmentStatus.unpaid.name,
                paidDate: null,
                transactionId: null,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
            )
            .toList(growable: false),
      );
    });
  }

  @override
  Future<void> markInstallmentPaid(
    String installmentId, {
    String? accountId,
    required DateTime paidDate,
    bool createExpenseTransaction = true,
    String? note,
  }) async {
    final LoanInstallment installment = await (_database.select(
      _database.loanInstallments,
    )..where((tbl) => tbl.id.equals(installmentId))).getSingle();

    if (installment.status == LoanInstallmentStatus.paid.name) {
      return;
    }

    final Loan loan = await (_database.select(
      _database.loans,
    )..where((tbl) => tbl.id.equals(installment.loanId))).getSingle();

    String? transactionId;
    if (createExpenseTransaction) {
      final String? effectiveAccountId = accountId ?? loan.accountId;
      if (effectiveAccountId == null) {
        throw StateError(
          'An account is required when creating a loan expense transaction.',
        );
      }

      final _LoanCategoryRefs categoryRefs = await _ensureLoanCategories(
        _loanTypeFromName(loan.loanType),
        parentCategoryId: loan.categoryId,
        childCategoryId: loan.childCategoryId,
      );

      transactionId = await _transactionRepository.createTransaction(
        CreateTransactionInput(
          type: TransactionType.expense,
          accountId: effectiveAccountId,
          amountMinor: installment.amountMinor,
          transactionDate: paidDate,
          note: note?.trim().isNotEmpty == true
              ? note!.trim()
              : '${loan.loanName} Payment',
          source: 'loan',
          loanId: loan.id,
          loanInstallmentId: installment.id,
          categoryId: categoryRefs.parentCategoryId,
          childCategoryId: categoryRefs.childCategoryId,
        ),
      );
    }

    final DateTime now = DateTime.now();

    await _database.transaction(() async {
      await (_database.update(
        _database.loanInstallments,
      )..where((tbl) => tbl.id.equals(installmentId))).write(
        LoanInstallmentsCompanion(
          status: Value(LoanInstallmentStatus.paid.name),
          paidDate: Value(paidDate),
          transactionId: Value(transactionId),
          updatedAt: Value(now),
        ),
      );

      await _refreshLoanProgress(loan.id, updatedAt: now);
    });
  }

  @override
  Future<void> undoInstallmentPayment(String installmentId) async {
    final LoanInstallment installment = await (_database.select(
      _database.loanInstallments,
    )..where((tbl) => tbl.id.equals(installmentId))).getSingle();

    if (installment.status != LoanInstallmentStatus.paid.name) {
      return;
    }

    final DateTime now = DateTime.now();
    await _database.transaction(() async {
      if (installment.transactionId != null) {
        await _transactionRepository.softDeleteTransaction(
          installment.transactionId!,
        );
      }

      await (_database.update(
        _database.loanInstallments,
      )..where((tbl) => tbl.id.equals(installmentId))).write(
        LoanInstallmentsCompanion(
          status: Value(LoanInstallmentStatus.unpaid.name),
          paidDate: const Value(null),
          transactionId: const Value(null),
          updatedAt: Value(now),
        ),
      );

      await _refreshLoanProgress(installment.loanId, updatedAt: now);
    });
  }

  @override
  Future<int> processDueInstallments() async {
    final DateTime today = DateTime.now();
    final DateTime endOfToday = DateTime(
      today.year,
      today.month,
      today.day,
      23,
      59,
      59,
      999,
    );
    final List<LoanInstallment> dueInstallments =
        await (_database.select(_database.loanInstallments)
              ..where(
                (tbl) =>
                    tbl.status.equals(LoanInstallmentStatus.unpaid.name) &
                    tbl.dueDate.isSmallerOrEqualValue(endOfToday),
              )
              ..orderBy(<OrderingTerm Function($LoanInstallmentsTable)>[
                (tbl) => OrderingTerm.asc(tbl.dueDate),
                (tbl) => OrderingTerm.asc(tbl.installmentNumber),
              ]))
            .get();

    int processed = 0;
    for (final installment in dueInstallments) {
      final Loan loan = await (_database.select(
        _database.loans,
      )..where((tbl) => tbl.id.equals(installment.loanId))).getSingle();
      if (loan.accountId == null) {
        continue;
      }

      await markInstallmentPaid(
        installment.id,
        accountId: loan.accountId,
        paidDate: installment.dueDate,
        createExpenseTransaction: true,
        note: 'Automatic loan payment',
      );
      processed += 1;
    }

    return processed;
  }

  Future<void> _refreshLoanProgress(
    String loanId, {
    required DateTime updatedAt,
  }) async {
    final Loan loan = await (_database.select(
      _database.loans,
    )..where((tbl) => tbl.id.equals(loanId))).getSingle();
    final List<LoanInstallment> installments = await (_database.select(
      _database.loanInstallments,
    )..where((tbl) => tbl.loanId.equals(loanId))).get();

    final List<LoanInstallment> paidInstallments = installments
        .where((item) => item.status == LoanInstallmentStatus.paid.name)
        .toList(growable: false);
    final int paidPrincipalMinor = paidInstallments.fold<int>(
      0,
      (sum, item) => sum + item.principalAmountMinor,
    );
    final int remainingBalanceMinor = math.max(
      0,
      loan.totalAmountMinor - paidPrincipalMinor,
    );
    final int paidCount = paidInstallments.length;
    final LoanStatus status =
        remainingBalanceMinor <= 0 || paidCount >= loan.numberOfInstallments
        ? LoanStatus.closed
        : LoanStatus.active;

    await (_database.update(
      _database.loans,
    )..where((tbl) => tbl.id.equals(loanId))).write(
      LoansCompanion(
        remainingBalanceMinor: Value(remainingBalanceMinor),
        paidInstallments: Value(paidCount),
        status: Value(status.name),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  double _calculateMonthlyPayment({
    required int loanAmountMinor,
    required double annualInterestRate,
    required int numberOfInstallments,
  }) {
    if (numberOfInstallments <= 0) {
      throw ArgumentError.value(
        numberOfInstallments,
        'numberOfInstallments',
        'Installments must be greater than zero.',
      );
    }

    final double loanAmount = loanAmountMinor / 100;
    if (annualInterestRate == 0) {
      return loanAmountMinor / numberOfInstallments;
    }

    final double monthlyInterestRate = annualInterestRate / 12 / 100;
    final double growthFactor = math
        .pow(1 + monthlyInterestRate, numberOfInstallments)
        .toDouble();

    final double monthlyPayment =
        loanAmount * monthlyInterestRate * growthFactor / (growthFactor - 1);

    return monthlyPayment * 100;
  }

  List<_InstallmentScheduleRow> _buildSchedule({
    required String loanId,
    required DateTime startDate,
    required int totalAmountMinor,
    required double annualInterestRate,
    required int numberOfInstallments,
    required int monthlyPaymentMinor,
    required DateTime timestamp,
  }) {
    final List<_InstallmentScheduleRow> rows = <_InstallmentScheduleRow>[];
    int balanceMinor = totalAmountMinor;
    final double monthlyInterestRate = annualInterestRate / 12 / 100;

    for (int index = 0; index < numberOfInstallments; index++) {
      final bool isLast = index == numberOfInstallments - 1;
      final int interestMinor = annualInterestRate == 0
          ? 0
          : ((balanceMinor / 100) * monthlyInterestRate * 100).round();
      int principalMinor = monthlyPaymentMinor - interestMinor;
      if (isLast || principalMinor > balanceMinor) {
        principalMinor = balanceMinor;
      }
      final int amountMinor = principalMinor + interestMinor;
      balanceMinor = math.max(0, balanceMinor - principalMinor);

      rows.add(
        _InstallmentScheduleRow(
          id: _uuid.v4(),
          loanId: loanId,
          installmentNumber: index + 1,
          dueDate: _addMonthsKeepingDay(startDate, index),
          amountMinor: amountMinor,
          principalAmountMinor: principalMinor,
          interestAmountMinor: interestMinor,
          remainingBalanceMinor: balanceMinor,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
    }

    return rows;
  }

  DateTime _addMonthsKeepingDay(DateTime date, int months) {
    final int targetMonth = date.month + months;
    final int targetYear = date.year + ((targetMonth - 1) ~/ 12);
    final int normalizedMonth = ((targetMonth - 1) % 12) + 1;
    final int lastDayOfMonth = DateTime(targetYear, normalizedMonth + 1, 0).day;
    final int day = math.min(date.day, lastDayOfMonth);
    return DateTime(
      targetYear,
      normalizedMonth,
      day,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }

  Future<_LoanCategoryRefs> _ensureLoanCategories(
    LoanType loanType, {
    required String? parentCategoryId,
    required String? childCategoryId,
  }) async {
    final List<Category> categories = await _database
        .select(_database.categories)
        .get();

    if (parentCategoryId != null) {
      bool parentExists = false;
      for (final category in categories) {
        if (category.id == parentCategoryId && category.deletedAt == null) {
          parentExists = true;
          break;
        }
      }
      if (parentExists) {
        return _LoanCategoryRefs(
          parentCategoryId: parentCategoryId,
          childCategoryId: childCategoryId,
        );
      }
    }

    Category? parent;
    for (final category in categories) {
      if (category.parentId == null &&
          category.deletedAt == null &&
          category.name.toLowerCase() == 'loan') {
        parent = category;
        break;
      }
    }

    final DateTime now = DateTime.now();

    if (parent == null) {
      parent = Category(
        id: _uuid.v4(),
        name: 'Loan',
        parentId: null,
        type: CategoryType.expense.name,
        iconKey: 'debt',
        colorValue: CategoryVisuals.palette[6],
        sortOrder: 990,
        isActive: true,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      );
      await _database.into(_database.categories).insert(parent);
    }

    final String childName = loanType.label;
    Category? child;
    for (final category in categories) {
      if (category.parentId == parent.id &&
          category.deletedAt == null &&
          category.name.toLowerCase() == childName.toLowerCase()) {
        child = category;
        break;
      }
    }

    if (child == null) {
      child = Category(
        id: _uuid.v4(),
        name: childName,
        parentId: parent.id,
        type: CategoryType.expense.name,
        iconKey: switch (loanType) {
          LoanType.housing => 'home',
          LoanType.personal => 'wallet',
          LoanType.car => 'car',
          LoanType.other => 'debt',
        },
        colorValue: CategoryVisuals.palette[8],
        sortOrder: 991,
        isActive: true,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      );
      await _database.into(_database.categories).insert(child);
    }

    return _LoanCategoryRefs(
      parentCategoryId: parent.id,
      childCategoryId: child.id,
    );
  }

  domain.Loan _mapLoanRow(Loan row) {
    return domain.Loan(
      id: row.id,
      loanName: row.loanName,
      loanType: _loanTypeFromName(row.loanType),
      bankName: row.bankName,
      accountId: row.accountId,
      categoryId: row.categoryId,
      childCategoryId: row.childCategoryId,
      totalAmountMinor: row.totalAmountMinor,
      interestRate: row.interestRate,
      startDate: row.startDate,
      endDate: row.endDate,
      numberOfInstallments: row.numberOfInstallments,
      monthlyPaymentMinor: row.monthlyPaymentMinor,
      remainingBalanceMinor: row.remainingBalanceMinor,
      paidInstallments: row.paidInstallments,
      status: _loanStatusFromName(row.status),
      remindersEnabled: row.remindersEnabled,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  installment_domain.LoanInstallment _mapInstallmentRow(LoanInstallment row) {
    return installment_domain.LoanInstallment(
      id: row.id,
      loanId: row.loanId,
      installmentNumber: row.installmentNumber,
      dueDate: row.dueDate,
      amountMinor: row.amountMinor,
      principalAmountMinor: row.principalAmountMinor,
      interestAmountMinor: row.interestAmountMinor,
      remainingBalanceMinor: row.remainingBalanceMinor,
      status: row.status == LoanInstallmentStatus.paid.name
          ? LoanInstallmentStatus.paid
          : LoanInstallmentStatus.unpaid,
      paidDate: row.paidDate,
      transactionId: row.transactionId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  LoanType _loanTypeFromName(String name) {
    return LoanType.values.firstWhere(
      (value) => value.name == name,
      orElse: () => LoanType.housing,
    );
  }

  LoanStatus _loanStatusFromName(String name) {
    return LoanStatus.values.firstWhere(
      (value) => value.name == name,
      orElse: () => LoanStatus.active,
    );
  }
}

class _InstallmentScheduleRow {
  const _InstallmentScheduleRow({
    required this.id,
    required this.loanId,
    required this.installmentNumber,
    required this.dueDate,
    required this.amountMinor,
    required this.principalAmountMinor,
    required this.interestAmountMinor,
    required this.remainingBalanceMinor,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String loanId;
  final int installmentNumber;
  final DateTime dueDate;
  final int amountMinor;
  final int principalAmountMinor;
  final int interestAmountMinor;
  final int remainingBalanceMinor;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class _LoanCategoryRefs {
  const _LoanCategoryRefs({
    required this.parentCategoryId,
    required this.childCategoryId,
  });

  final String parentCategoryId;
  final String? childCategoryId;
}
