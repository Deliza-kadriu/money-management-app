import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:money_manager/core/utils/currency_formatter.dart';
import 'package:money_manager/core/utils/date_formatter.dart';
import 'package:money_manager/domain/entities/account.dart' as account_domain;
import 'package:money_manager/domain/entities/category.dart' as category_domain;
import 'package:money_manager/domain/entities/loan.dart';
import 'package:money_manager/domain/entities/loan_details.dart';
import 'package:money_manager/domain/entities/loan_installment.dart';
import 'package:money_manager/domain/enums/loan_installment_status.dart';
import 'package:money_manager/domain/enums/loan_status.dart';
import 'package:money_manager/domain/enums/loan_type.dart';
import 'package:money_manager/domain/repositories/loan_repository.dart';
import 'package:money_manager/shared/providers/app_providers.dart';

class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(loansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/loans/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add loan'),
      ),
      body: loansAsync.when(
        data: (loans) {
          if (loans.isEmpty) {
            return const _EmptyLoansState();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: loans.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final loan = loans[index];
              return _LoanListCard(loan: loan);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load loans.\n$error'),
          ),
        ),
      ),
    );
  }
}

class AddLoanScreen extends ConsumerStatefulWidget {
  const AddLoanScreen({super.key, this.loanId});

  final String? loanId;

  @override
  ConsumerState<AddLoanScreen> createState() => _AddLoanScreenState();
}

class _AddLoanScreenState extends ConsumerState<AddLoanScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _loanNameController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _interestController = TextEditingController(
    text: '0',
  );
  final TextEditingController _installmentsController = TextEditingController(
    text: '120',
  );

  LoanType _loanType = LoanType.housing;
  DateTime _startDate = DateTime.now();
  String? _selectedAccountId;
  String? _selectedCategorySelection;
  bool _isSaving = false;

  bool get _isEditing => widget.loanId != null;

  @override
  void initState() {
    super.initState();
    final String? loanId = widget.loanId;
    if (loanId == null) {
      return;
    }

    Loan? loan;
    final loans = ref.read(loansProvider).valueOrNull;
    if (loans != null) {
      for (final item in loans) {
        if (item.id == loanId) {
          loan = item;
          break;
        }
      }
    }
    if (loan == null) {
      return;
    }

    _loanNameController.text = loan.loanName;
    _bankNameController.text = loan.bankName;
    _amountController.text = (loan.totalAmountMinor / 100).toStringAsFixed(2);
    _interestController.text = loan.interestRate.toStringAsFixed(2);
    _installmentsController.text = loan.numberOfInstallments.toString();
    _loanType = loan.loanType;
    _startDate = loan.startDate;
    _selectedAccountId = loan.accountId;
    _selectedCategorySelection = loan.childCategoryId ?? loan.categoryId;
  }

  @override
  void dispose() {
    _loanNameController.dispose();
    _bankNameController.dispose();
    _amountController.dispose();
    _interestController.dispose();
    _installmentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final int? totalAmountMinor = _parseAmountMinor(_amountController.text);
    final double? interestRate = double.tryParse(_interestController.text);
    final int? installments = int.tryParse(_installmentsController.text);
    final int? monthlyPaymentMinor =
        totalAmountMinor != null &&
            interestRate != null &&
            installments != null &&
            installments > 0
        ? _previewMonthlyPaymentMinor(
            totalAmountMinor: totalAmountMinor,
            interestRate: interestRate,
            numberOfInstallments: installments,
          )
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit loan' : 'Add loan')),
      body: accountsAsync.when(
        data: (accounts) => categoriesAsync.when(
          data: (categories) {
            final categoryOptions = _buildLoanCategoryOptions(categories);
            _selectedAccountId = _resolveSelectedLoanAccount(
              _selectedAccountId,
              accounts,
            );
            _selectedCategorySelection = _resolveSelectedLoanCategory(
              _selectedCategorySelection,
              categoryOptions,
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextFormField(
                      controller: _loanNameController,
                      decoration: const InputDecoration(labelText: 'Loan name'),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Enter a loan name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<LoanType>(
                      initialValue: _loanType,
                      decoration: const InputDecoration(labelText: 'Loan type'),
                      items: LoanType.values
                          .map(
                            (type) => DropdownMenuItem<LoanType>(
                              value: type,
                              child: Text(type.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _loanType = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bankNameController,
                      decoration: const InputDecoration(labelText: 'Bank name'),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Enter a bank name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedAccountId,
                      decoration: const InputDecoration(
                        labelText: 'Installment account',
                      ),
                      items: accounts
                          .map(
                            (account) => DropdownMenuItem<String>(
                              value: account.id,
                              child: Text(account.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setState(() {
                          _selectedAccountId = value;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Choose the account for loan payments';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategorySelection,
                      decoration: const InputDecoration(
                        labelText: 'Installment expense category',
                      ),
                      items: categoryOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option.value,
                              child: Text(option.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setState(() {
                          _selectedCategorySelection = value;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Choose the category for loan payments';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Loan amount',
                      ),
                      validator: (value) {
                        if (_parseAmountMinor(value) == null) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _interestController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Annual interest rate (%)',
                      ),
                      validator: (value) {
                        if (double.tryParse((value ?? '').trim()) == null) {
                          return 'Enter a valid interest rate';
                        }
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _installmentsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Number of installments',
                      ),
                      validator: (value) {
                        final int? parsed = int.tryParse((value ?? '').trim());
                        if (parsed == null || parsed <= 0) {
                          return 'Enter a valid installment count';
                        }
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: const Text('Start date'),
                        subtitle: Text(AppDateFormatter.format(_startDate)),
                        trailing: const Icon(Icons.calendar_today_rounded),
                        onTap: _pickStartDate,
                      ),
                    ),
                    if (monthlyPaymentMinor != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Preview',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Monthly payment: ${CurrencyFormatter.formatMinorUnits(monthlyPaymentMinor)}',
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'End date: ${AppDateFormatter.format(_estimateEndDate(_startDate, installments!))}',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _submit,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(
                        _isSaving
                            ? 'Saving...'
                            : _isEditing
                            ? 'Update loan'
                            : 'Create loan',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to load loan form.\n$error'),
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load loan form.\n$error'),
          ),
        ),
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _startDate = picked;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final int? totalAmountMinor = _parseAmountMinor(_amountController.text);
    final double? interestRate = double.tryParse(_interestController.text);
    final int? installments = int.tryParse(_installmentsController.text);
    final _LoanCategorySelection categorySelection =
        _parseLoanCategorySelection(
          _selectedCategorySelection,
          ref.read(categoriesProvider).valueOrNull ??
              const <category_domain.Category>[],
        );
    if (totalAmountMinor == null ||
        interestRate == null ||
        installments == null ||
        _selectedAccountId == null) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final input = CreateLoanInput(
        loanName: _loanNameController.text.trim(),
        loanType: _loanType,
        bankName: _bankNameController.text.trim(),
        accountId: _selectedAccountId!,
        categoryId: categorySelection.parentCategoryId,
        childCategoryId: categorySelection.childCategoryId,
        totalAmountMinor: totalAmountMinor,
        interestRate: interestRate,
        startDate: _startDate,
        numberOfInstallments: installments,
      );
      if (_isEditing) {
        await ref
            .read(loanRepositoryProvider)
            .updateLoan(widget.loanId!, input);
      } else {
        await ref.read(loanRepositoryProvider).createLoan(input);
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Loan save failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  int? _parseAmountMinor(String? value) {
    final double? parsed = double.tryParse((value ?? '').trim());
    if (parsed == null) {
      return null;
    }
    return (parsed * 100).round();
  }

  int _previewMonthlyPaymentMinor({
    required int totalAmountMinor,
    required double interestRate,
    required int numberOfInstallments,
  }) {
    if (interestRate == 0) {
      return (totalAmountMinor / numberOfInstallments).round();
    }

    final double monthlyInterestRate = interestRate / 12 / 100;
    final double growthFactor = math
        .pow(1 + monthlyInterestRate, numberOfInstallments)
        .toDouble();
    final double amount = totalAmountMinor / 100;
    final double payment =
        amount * monthlyInterestRate * growthFactor / (growthFactor - 1);
    return (payment * 100).round();
  }

  DateTime _estimateEndDate(DateTime startDate, int installments) {
    final int offset = installments - 1;
    final int targetMonth = startDate.month + offset;
    final int year = startDate.year + ((targetMonth - 1) ~/ 12);
    final int month = ((targetMonth - 1) % 12) + 1;
    final int lastDay = DateTime(year, month + 1, 0).day;
    final int day = math.min(startDate.day, lastDay);
    return DateTime(year, month, day);
  }
}

class LoanDetailsScreen extends ConsumerWidget {
  const LoanDetailsScreen({super.key, required this.loanId});

  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loanDetailsAsync = ref.watch(loanDetailsProvider(loanId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loan details'),
        actions: <Widget>[
          loanDetailsAsync.valueOrNull == null
              ? const SizedBox.shrink()
              : PopupMenuButton<String>(
                  onSelected: (value) async {
                    final details = loanDetailsAsync.valueOrNull;
                    if (details == null) {
                      return;
                    }

                    if (value == 'edit') {
                      await context.push('/loans/${details.loan.id}/edit');
                    } else if (value == 'delete' && context.mounted) {
                      final bool? confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete loan'),
                          content: const Text(
                            'This will remove the loan and its installments. Any linked loan expense transactions will be archived.',
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await ref
                            .read(loanRepositoryProvider)
                            .deleteLoan(details.loan.id);
                        if (context.mounted) {
                          context.pop();
                        }
                      }
                    }
                  },
                  itemBuilder: (context) => const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Edit loan'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete loan'),
                    ),
                  ],
                ),
        ],
      ),
      body: loanDetailsAsync.when(
        data: (details) {
          if (details == null) {
            return const Center(child: Text('Loan not found.'));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              _LoanSummaryCard(loan: details.loan),
              const SizedBox(height: 16),
              _LoanProgressCard(loan: details.loan),
              const SizedBox(height: 16),
              _NextInstallmentCard(installment: details.nextUnpaidInstallment),
              const SizedBox(height: 20),
              Text(
                'Installments',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ...details.installments.map(
                (installment) => _InstallmentTile(
                  installment: installment,
                  onMarkPaid: installment.status == LoanInstallmentStatus.unpaid
                      ? () => _showMarkPaidSheet(
                          context,
                          ref,
                          details,
                          installment,
                        )
                      : null,
                  onUndoPaid: installment.status == LoanInstallmentStatus.paid
                      ? () => _undoPayment(context, ref, installment)
                      : null,
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load loan details.\n$error'),
          ),
        ),
      ),
    );
  }

  Future<void> _showMarkPaidSheet(
    BuildContext context,
    WidgetRef ref,
    LoanDetails details,
    LoanInstallment installment,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MarkInstallmentPaidSheet(
        loan: details.loan,
        installment: installment,
      ),
    );
  }

  Future<void> _undoPayment(
    BuildContext context,
    WidgetRef ref,
    LoanInstallment installment,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Undo payment'),
        content: const Text(
          'This will mark the installment as unpaid again. If a linked expense transaction exists, it will be archived.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Undo'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await ref
        .read(loanRepositoryProvider)
        .undoInstallmentPayment(installment.id);
  }
}

class _LoanListCard extends StatelessWidget {
  const _LoanListCard({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/loans/${loan.id}'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          loan.loanName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(loan.bankName),
                      ],
                    ),
                  ),
                  _LoanStatusBadge(status: loan.status),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 18,
                runSpacing: 10,
                children: <Widget>[
                  _LoanMetric(
                    label: 'Monthly',
                    value: CurrencyFormatter.formatMinorUnits(
                      loan.monthlyPaymentMinor,
                    ),
                  ),
                  _LoanMetric(
                    label: 'Remaining',
                    value: CurrencyFormatter.formatMinorUnits(
                      loan.remainingBalanceMinor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: loan.progressPercent,
                minHeight: 10,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 10),
              Text(
                '${loan.paidInstallments} of ${loan.numberOfInstallments} installments paid',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoanSummaryCard extends StatelessWidget {
  const _LoanSummaryCard({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    loan.loanName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _LoanStatusBadge(status: loan.status),
              ],
            ),
            const SizedBox(height: 6),
            Text('${loan.bankName} • ${loan.loanType.label}'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: <Widget>[
                _LoanMetric(
                  label: 'Total loan',
                  value: CurrencyFormatter.formatMinorUnits(
                    loan.totalAmountMinor,
                  ),
                ),
                _LoanMetric(
                  label: 'Remaining',
                  value: CurrencyFormatter.formatMinorUnits(
                    loan.remainingBalanceMinor,
                  ),
                ),
                _LoanMetric(
                  label: 'Monthly payment',
                  value: CurrencyFormatter.formatMinorUnits(
                    loan.monthlyPaymentMinor,
                  ),
                ),
                _LoanMetric(
                  label: 'Interest',
                  value: '${loan.interestRate.toStringAsFixed(2)}%',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoanProgressCard extends StatelessWidget {
  const _LoanProgressCard({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Progress', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: loan.progressPercent,
              minHeight: 12,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 12),
            Text(
              '${loan.paidInstallments} of ${loan.numberOfInstallments} installments paid',
            ),
            const SizedBox(height: 6),
            Text(
              '${(loan.progressPercent * 100).toStringAsFixed(0)}% completed',
            ),
            const SizedBox(height: 6),
            Text(
              '${CurrencyFormatter.formatMinorUnits(loan.remainingBalanceMinor)} remaining',
            ),
          ],
        ),
      ),
    );
  }
}

class _NextInstallmentCard extends StatelessWidget {
  const _NextInstallmentCard({required this.installment});

  final LoanInstallment? installment;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        title: const Text('Next unpaid installment'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            installment == null
                ? 'All installments are paid.'
                : 'Installment #${installment!.installmentNumber} • ${AppDateFormatter.format(installment!.dueDate)}',
          ),
        ),
        trailing: installment == null
            ? null
            : Text(
                CurrencyFormatter.formatMinorUnits(installment!.amountMinor),
                style: Theme.of(context).textTheme.titleMedium,
              ),
      ),
    );
  }
}

class _InstallmentTile extends StatelessWidget {
  const _InstallmentTile({
    required this.installment,
    required this.onMarkPaid,
    required this.onUndoPaid,
  });

  final LoanInstallment installment;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onUndoPaid;

  @override
  Widget build(BuildContext context) {
    final bool isPaid = installment.status == LoanInstallmentStatus.paid;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text('Installment #${installment.installmentNumber}'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Due ${AppDateFormatter.format(installment.dueDate)} • ${CurrencyFormatter.formatMinorUnits(installment.amountMinor)}',
              ),
              const SizedBox(height: 4),
              Text(
                isPaid
                    ? 'Paid on ${AppDateFormatter.format(installment.paidDate!)}'
                    : 'Principal ${CurrencyFormatter.formatMinorUnits(installment.principalAmountMinor)} • Interest ${CurrencyFormatter.formatMinorUnits(installment.interestAmountMinor)}',
              ),
            ],
          ),
        ),
        trailing: isPaid
            ? TextButton.icon(
                onPressed: onUndoPaid,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Undo'),
              )
            : FilledButton(
                onPressed: onMarkPaid,
                child: const Text('Mark paid'),
              ),
      ),
    );
  }
}

class _MarkInstallmentPaidSheet extends ConsumerStatefulWidget {
  const _MarkInstallmentPaidSheet({
    required this.loan,
    required this.installment,
  });

  final Loan loan;
  final LoanInstallment installment;

  @override
  ConsumerState<_MarkInstallmentPaidSheet> createState() =>
      _MarkInstallmentPaidSheetState();
}

class _MarkInstallmentPaidSheetState
    extends ConsumerState<_MarkInstallmentPaidSheet> {
  final TextEditingController _noteController = TextEditingController();
  DateTime _paidDate = DateTime.now();
  bool _createExpenseTransaction = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        ref.watch(accountsProvider).valueOrNull ??
        const <account_domain.Account>[];
    final categories =
        ref.watch(categoriesProvider).valueOrNull ??
        const <category_domain.Category>[];
    final accountName = _accountName(accounts, widget.loan.accountId);
    final categoryLabel = _categoryLabel(categories, widget.loan);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Mark installment as paid',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Add expense transaction'),
            subtitle: Text(
              'If enabled, this payment will also be added to expenses under Loan > ${widget.loan.loanType.label}.',
            ),
            value: _createExpenseTransaction,
            onChanged: (value) {
              setState(() {
                _createExpenseTransaction = value;
              });
            },
          ),
          const SizedBox(height: 8),
          if (_createExpenseTransaction && widget.loan.accountId == null)
            const Text(
              'This loan has no attached payment account yet. Edit the loan first and choose an account.',
            )
          else ...<Widget>[
            if (_createExpenseTransaction) ...<Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_balance_wallet_rounded),
                title: const Text('Attached account'),
                subtitle: Text(accountName ?? 'Not configured'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.category_rounded),
                title: const Text('Attached category'),
                subtitle: Text(categoryLabel ?? 'Loan default category'),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: const Text('Paid date'),
                subtitle: Text(AppDateFormatter.format(_paidDate)),
                trailing: const Icon(Icons.calendar_today_rounded),
                onTap: _pickPaidDate,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: 'Transaction note',
                hintText: '${widget.loan.loanName} Payment',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isSaving ? null : _submit,
              icon: const Icon(Icons.check_rounded),
              label: Text(_isSaving ? 'Saving...' : 'Save payment'),
            ),
          ],
        ],
      ),
    );
  }

  String? _accountName(
    List<account_domain.Account> accounts,
    String? accountId,
  ) {
    if (accountId == null) {
      return null;
    }

    for (final account in accounts) {
      if (account.id == accountId) {
        return account.name;
      }
    }

    return null;
  }

  Future<void> _pickPaidDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _paidDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _paidDate = picked;
    });
  }

  String? _categoryLabel(List<category_domain.Category> categories, Loan loan) {
    if (loan.childCategoryId != null) {
      category_domain.Category? parent;
      category_domain.Category? child;
      for (final category in categories) {
        if (category.id == loan.categoryId) {
          parent = category;
        }
        if (category.id == loan.childCategoryId) {
          child = category;
        }
      }
      if (parent != null && child != null) {
        return '${parent.name} > ${child.name}';
      }
    }

    if (loan.categoryId != null) {
      for (final category in categories) {
        if (category.id == loan.categoryId) {
          return category.name;
        }
      }
    }

    return null;
  }

  Future<void> _submit() async {
    if (_createExpenseTransaction && widget.loan.accountId == null) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await ref
          .read(loanRepositoryProvider)
          .markInstallmentPaid(
            widget.installment.id,
            accountId: widget.loan.accountId,
            paidDate: _paidDate,
            createExpenseTransaction: _createExpenseTransaction,
            note: _noteController.text.trim(),
          );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

class _LoanCategoryOption {
  const _LoanCategoryOption({
    required this.value,
    required this.label,
    required this.parentCategoryId,
    required this.childCategoryId,
  });

  final String value;
  final String label;
  final String parentCategoryId;
  final String? childCategoryId;
}

class _LoanCategorySelection {
  const _LoanCategorySelection({
    required this.parentCategoryId,
    required this.childCategoryId,
  });

  final String? parentCategoryId;
  final String? childCategoryId;
}

String? _resolveSelectedLoanAccount(
  String? currentSelection,
  List<account_domain.Account> accounts,
) {
  if (currentSelection != null &&
      accounts.any((account) => account.id == currentSelection)) {
    return currentSelection;
  }

  for (final account in accounts) {
    if (account.isDefault) {
      return account.id;
    }
  }

  return accounts.isEmpty ? null : accounts.first.id;
}

String? _resolveSelectedLoanCategory(
  String? currentSelection,
  List<_LoanCategoryOption> options,
) {
  if (currentSelection != null &&
      options.any((option) => option.value == currentSelection)) {
    return currentSelection;
  }

  return null;
}

List<_LoanCategoryOption> _buildLoanCategoryOptions(
  List<category_domain.Category> categories,
) {
  final List<category_domain.Category> parents = categories
      .where((category) => category.parentId == null)
      .toList(growable: false);
  final List<_LoanCategoryOption> options = <_LoanCategoryOption>[];

  for (final parent in parents) {
    options.add(
      _LoanCategoryOption(
        value: parent.id,
        label: parent.name,
        parentCategoryId: parent.id,
        childCategoryId: null,
      ),
    );

    final List<category_domain.Category> children = categories
        .where((category) => category.parentId == parent.id)
        .toList(growable: false);
    for (final child in children) {
      options.add(
        _LoanCategoryOption(
          value: child.id,
          label: '${parent.name} > ${child.name}',
          parentCategoryId: parent.id,
          childCategoryId: child.id,
        ),
      );
    }
  }

  return options;
}

_LoanCategorySelection _parseLoanCategorySelection(
  String? value,
  List<category_domain.Category> categories,
) {
  if (value == null) {
    return const _LoanCategorySelection(
      parentCategoryId: null,
      childCategoryId: null,
    );
  }

  for (final category in categories) {
    if (category.id == value) {
      return _LoanCategorySelection(
        parentCategoryId: category.parentId ?? category.id,
        childCategoryId: category.parentId == null ? null : category.id,
      );
    }
  }

  return const _LoanCategorySelection(
    parentCategoryId: null,
    childCategoryId: null,
  );
}

class _LoanStatusBadge extends StatelessWidget {
  const _LoanStatusBadge({required this.status});

  final LoanStatus status;

  @override
  Widget build(BuildContext context) {
    final bool closed = status == LoanStatus.closed;
    final Color background = closed
        ? Colors.green.withValues(alpha: 0.12)
        : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
    final Color foreground = closed
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _LoanMetric extends StatelessWidget {
  const _LoanMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _EmptyLoansState extends StatelessWidget {
  const _EmptyLoansState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.home_work_outlined, size: 52),
            const SizedBox(height: 16),
            Text('No loans yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Add your first housing loan to track installments, remaining balance, and monthly payments.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
