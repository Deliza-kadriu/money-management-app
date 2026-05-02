import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/core/utils/date_formatter.dart';
import 'package:money_manager/core/utils/currency_formatter.dart';
import 'package:money_manager/domain/entities/recurring_rule.dart';
import 'package:money_manager/domain/entities/recurring_rule_run.dart';
import 'package:money_manager/domain/enums/category_type.dart';
import 'package:money_manager/domain/enums/recurring_frequency.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/domain/repositories/recurring_rule_repository.dart';
import 'package:money_manager/shared/providers/app_providers.dart';
import 'package:money_manager/shared/widgets/app_mode_tabs.dart';

enum RecurringListMode { active, suggestions, archived }

class RecurringRulesScreen extends ConsumerStatefulWidget {
  const RecurringRulesScreen({super.key});

  @override
  ConsumerState<RecurringRulesScreen> createState() =>
      _RecurringRulesScreenState();
}

class _RecurringRulesScreenState extends ConsumerState<RecurringRulesScreen> {
  RecurringListMode _mode = RecurringListMode.active;

  @override
  Widget build(BuildContext context) {
    final bool archivedOnly = _mode == RecurringListMode.archived;
    final bool suggestionsOnly = _mode == RecurringListMode.suggestions;
    final rulesAsync = ref.watch(recurringRulesProvider(archivedOnly));
    final suggestionsAsync = ref.watch(recurringSuggestionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Process due rules',
            onPressed: _processDueRules,
            icon: const Icon(Icons.playlist_add_check_circle_outlined),
          ),
        ],
      ),
      floatingActionButton: archivedOnly || suggestionsOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openCreateSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add rule'),
            ),
      body: suggestionsOnly
          ? suggestionsAsync.when(
              data: _buildSuggestionsBody,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Failed to load recurring suggestions.\n$error'),
                ),
              ),
            )
          : rulesAsync.when(
              data: (rules) {
                if (rules.isEmpty) {
                  return _EmptyRecurringState(
                    mode: _mode,
                    onCreate: archivedOnly
                        ? null
                        : () => _openCreateSheet(context),
                    onModeChanged: (mode) {
                      setState(() {
                        _mode = mode;
                      });
                    },
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: <Widget>[
                    _RecurringToolbar(
                      mode: _mode,
                      onModeChanged: (mode) {
                        setState(() {
                          _mode = mode;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    ...rules.map(
                      (rule) => Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text(rule.title),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${_frequencyLabel(rule.frequency)} • Due ${_dateLabel(rule.nextDueDate)} • ${rule.accountName}',
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                await _openEditSheet(context, rule);
                              } else if (value == 'archive') {
                                await ref
                                    .read(recurringRuleRepositoryProvider)
                                    .softDeleteRecurringRule(rule.id);
                                await ref
                                    .read(recurringReminderServiceProvider)
                                    .cancelForRule(rule.id);
                              } else if (value == 'restore') {
                                await ref
                                    .read(recurringRuleRepositoryProvider)
                                    .restoreRecurringRule(rule.id);
                                await ref
                                    .read(recurringReminderServiceProvider)
                                    .scheduleForRule(rule);
                              }
                            },
                            itemBuilder: (context) => archivedOnly
                                ? const <PopupMenuEntry<String>>[
                                    PopupMenuItem<String>(
                                      value: 'restore',
                                      child: Text('Restore'),
                                    ),
                                  ]
                                : const <PopupMenuEntry<String>>[
                                    PopupMenuItem<String>(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'archive',
                                      child: Text('Archive'),
                                    ),
                                  ],
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                Text(
                                  CurrencyFormatter.formatMinorUnits(
                                    rule.amountMinor,
                                  ),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _typeLabel(rule.type),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Failed to load recurring rules.\n$error'),
                ),
              ),
            ),
    );
  }

  Widget _buildSuggestionsBody(List<RecurringRuleRun> suggestions) {
    if (suggestions.isEmpty) {
      return _EmptyRecurringState(
        mode: RecurringListMode.suggestions,
        onCreate: null,
        onModeChanged: (mode) {
          setState(() {
            _mode = mode;
          });
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        _RecurringToolbar(
          mode: _mode,
          onModeChanged: (mode) {
            setState(() {
              _mode = mode;
            });
          },
        ),
        const SizedBox(height: 16),
        ...suggestions.map(
          (run) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          run.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.formatMinorUnits(run.amountMinor),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_typeLabel(run.type)} • Due ${_dateLabel(run.scheduledFor)} • ${run.accountName}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (run.destinationAccountName != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      'To ${run.destinationAccountName}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: () => _approveSuggestion(run.id),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Create transaction'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _dismissSuggestion(run.id),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Dismiss'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openCreateSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateRecurringRuleSheet(
        onCreate: (input) async {
          final String ruleId = await ref
              .read(recurringRuleRepositoryProvider)
              .createRecurringRule(input);
          await _afterRuleSaved(
            ruleId: ruleId,
            title: input.title,
            type: input.type,
            nextDueDate: input.nextDueDate,
            reminderDaysBefore: input.reminderDaysBefore,
          );
        },
      ),
    );
  }

  Future<void> _openEditSheet(BuildContext context, RecurringRule rule) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateRecurringRuleSheet(
        rule: rule,
        onCreate: (input) async {
          await ref
              .read(recurringRuleRepositoryProvider)
              .createRecurringRule(input);
        },
        onUpdate: (input) async {
          await ref
              .read(recurringRuleRepositoryProvider)
              .updateRecurringRule(rule.id, input);
          await _afterRuleSaved(
            ruleId: rule.id,
            title: input.title,
            type: input.type,
            nextDueDate: input.nextDueDate,
            reminderDaysBefore: input.reminderDaysBefore,
          );
        },
      ),
    );
  }

  Future<void> _afterRuleSaved({
    required String ruleId,
    required String title,
    required TransactionType type,
    required DateTime nextDueDate,
    required int reminderDaysBefore,
  }) async {
    await ref
        .read(recurringReminderServiceProvider)
        .scheduleForInput(
          ruleId: ruleId,
          title: title,
          type: type,
          nextDueDate: nextDueDate,
          reminderDaysBefore: reminderDaysBefore,
        );
    await ref
        .read(recurringRuleProcessorProvider)
        .processDueRules(notifyWhenWorkFound: false);
    await ref.read(recurringReminderServiceProvider).syncActiveReminders();
  }

  Future<void> _processDueRules() async {
    final result = await ref
        .read(recurringRuleProcessorProvider)
        .processDueRules();
    await ref.read(recurringReminderServiceProvider).syncActiveReminders();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.hasWork
              ? 'Processed ${result.processedRulesCount} rule(s): ${result.autoCreatedCount} auto-created, ${result.suggestedCount} reminder(s).'
              : 'No recurring rules are due right now.',
        ),
      ),
    );
  }

  Future<void> _approveSuggestion(String runId) async {
    await ref.read(recurringRuleProcessorProvider).approveSuggestedRun(runId);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transaction created from recurring rule.')),
    );
  }

  Future<void> _dismissSuggestion(String runId) async {
    await ref.read(recurringRuleProcessorProvider).dismissSuggestedRun(runId);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recurring suggestion dismissed.')),
    );
  }

  String _frequencyLabel(RecurringFrequency frequency) {
    switch (frequency) {
      case RecurringFrequency.daily:
        return 'Daily';
      case RecurringFrequency.weekly:
        return 'Weekly';
      case RecurringFrequency.monthly:
        return 'Monthly';
      case RecurringFrequency.yearly:
        return 'Yearly';
    }
  }

  String _typeLabel(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.income:
        return 'Income';
      case TransactionType.transfer:
        return 'Transfer';
    }
  }

  String _dateLabel(DateTime date) {
    return AppDateFormatter.format(date);
  }
}

class _RecurringToolbar extends StatelessWidget {
  const _RecurringToolbar({required this.mode, required this.onModeChanged});

  final RecurringListMode mode;
  final ValueChanged<RecurringListMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return AppModeTabs<RecurringListMode>(
      selected: mode,
      onChanged: onModeChanged,
      items: const <AppModeTabItem<RecurringListMode>>[
        AppModeTabItem<RecurringListMode>(
          value: RecurringListMode.active,
          label: 'Active',
          icon: Icons.repeat_rounded,
        ),
        AppModeTabItem<RecurringListMode>(
          value: RecurringListMode.suggestions,
          label: 'Suggestions',
          icon: Icons.fact_check_outlined,
        ),
        AppModeTabItem<RecurringListMode>(
          value: RecurringListMode.archived,
          label: 'Archived',
          icon: Icons.archive_outlined,
        ),
      ],
    );
  }
}

class _EmptyRecurringState extends StatelessWidget {
  const _EmptyRecurringState({
    required this.mode,
    required this.onCreate,
    required this.onModeChanged,
  });

  final RecurringListMode mode;
  final VoidCallback? onCreate;
  final ValueChanged<RecurringListMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final bool archivedOnly = mode == RecurringListMode.archived;
    final bool suggestionsOnly = mode == RecurringListMode.suggestions;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: <Widget>[
          _RecurringToolbar(mode: mode, onModeChanged: onModeChanged),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      archivedOnly
                          ? Icons.archive_outlined
                          : suggestionsOnly
                          ? Icons.fact_check_outlined
                          : Icons.repeat_rounded,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      archivedOnly
                          ? 'No archived rules'
                          : suggestionsOnly
                          ? 'No suggestions pending'
                          : 'No recurring rules yet',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      archivedOnly
                          ? 'Archived recurring rules will appear here.'
                          : suggestionsOnly
                          ? 'Due recurring rules that need review will appear here.'
                          : 'Create recurring rent, subscriptions, salary, or transfers.',
                      textAlign: TextAlign.center,
                    ),
                    if (mode == RecurringListMode.active) ...<Widget>[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: onCreate,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add recurring rule'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateRecurringRuleSheet extends ConsumerStatefulWidget {
  const _CreateRecurringRuleSheet({
    required this.onCreate,
    this.onUpdate,
    this.rule,
  });

  final Future<void> Function(CreateRecurringRuleInput input) onCreate;
  final Future<void> Function(UpdateRecurringRuleInput input)? onUpdate;
  final RecurringRule? rule;

  @override
  ConsumerState<_CreateRecurringRuleSheet> createState() =>
      _CreateRecurringRuleSheetState();
}

class _CreateRecurringRuleSheetState
    extends ConsumerState<_CreateRecurringRuleSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController(
    text: '0.00',
  );
  final TextEditingController _noteController = TextEditingController();

  TransactionType _selectedType = TransactionType.expense;
  RecurringFrequency _selectedFrequency = RecurringFrequency.monthly;
  String? _selectedAccountId;
  String? _selectedDestinationAccountId;
  String? _selectedCategoryId;
  String? _selectedChildCategoryId;
  DateTime _selectedStartDate = DateTime.now();
  TimeOfDay _selectedExecutionTime = TimeOfDay.now();
  int _reminderDaysBefore = 0;
  bool _autoCreate = true;
  bool _isSaving = false;
  bool get _isEditing => widget.rule != null;

  @override
  void initState() {
    super.initState();

    final rule = widget.rule;
    if (rule == null) {
      return;
    }

    _titleController.text = rule.title;
    _amountController.text = (rule.amountMinor / 100).toStringAsFixed(2);
    _noteController.text = rule.note;
    _selectedType = rule.type;
    _selectedFrequency = rule.frequency;
    _selectedAccountId = rule.accountId;
    _selectedDestinationAccountId = rule.destinationAccountId;
    _selectedCategoryId = rule.categoryId;
    _selectedChildCategoryId = rule.childCategoryId;
    _selectedStartDate = rule.startDate;
    _selectedExecutionTime = TimeOfDay.fromDateTime(rule.nextDueDate);
    _reminderDaysBefore = rule.reminderDaysBefore;
    _autoCreate = rule.autoCreate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        mediaQuery.viewInsets.bottom + 24,
      ),
      child: accountsAsync.when(
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Create at least one account before adding recurring rules.',
              ),
            );
          }

          _selectedAccountId ??= accounts.first.id;

          return Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                Text(
                  _isEditing ? 'Edit recurring rule' : 'Add recurring rule',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SegmentedButton<TransactionType>(
                  segments: const <ButtonSegment<TransactionType>>[
                    ButtonSegment<TransactionType>(
                      value: TransactionType.expense,
                      label: Text('Expense'),
                    ),
                    ButtonSegment<TransactionType>(
                      value: TransactionType.income,
                      label: Text('Income'),
                    ),
                    ButtonSegment<TransactionType>(
                      value: TransactionType.transfer,
                      label: Text('Transfer'),
                    ),
                  ],
                  selected: <TransactionType>{_selectedType},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _selectedType = selection.first;
                      if (_selectedType == TransactionType.transfer) {
                        _selectedCategoryId = null;
                        _selectedChildCategoryId = null;
                      } else {
                        _selectedDestinationAccountId = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RecurringFrequency>(
                  initialValue: _selectedFrequency,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                  items: RecurringFrequency.values
                      .map(
                        (frequency) => DropdownMenuItem<RecurringFrequency>(
                          value: frequency,
                          child: Text(_frequencyLabel(frequency)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedFrequency = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount'),
                  validator: (value) {
                    final parsed = double.tryParse((value ?? '').trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a positive amount';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedAccountId,
                  decoration: const InputDecoration(labelText: 'Account'),
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
                ),
                if (_selectedType == TransactionType.transfer) ...<Widget>[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDestinationAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Destination account',
                    ),
                    items: accounts
                        .where((account) => account.id != _selectedAccountId)
                        .map(
                          (account) => DropdownMenuItem<String>(
                            value: account.id,
                            child: Text(account.name),
                          ),
                        )
                        .toList(growable: false),
                    validator: (value) {
                      if (_selectedType == TransactionType.transfer &&
                          (value == null || value == _selectedAccountId)) {
                        return 'Choose a different destination account';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      setState(() {
                        _selectedDestinationAccountId = value;
                      });
                    },
                  ),
                ],
                if (_selectedType != TransactionType.transfer) ...<Widget>[
                  const SizedBox(height: 12),
                  categoriesAsync.when(
                    data: (categories) {
                      final parentCategories = categories
                          .where(
                            (category) =>
                                category.isParent &&
                                (category.type ==
                                        _categoryTypeForTransaction(
                                          _selectedType,
                                        ) ||
                                    category.type == CategoryType.both),
                          )
                          .toList(growable: false);
                      final childCategories = categories
                          .where(
                            (category) =>
                                category.parentId == _selectedCategoryId,
                          )
                          .toList(growable: false);

                      return Column(
                        children: <Widget>[
                          DropdownButtonFormField<String?>(
                            initialValue: _selectedCategoryId,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                            ),
                            items: <DropdownMenuItem<String?>>[
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('None'),
                              ),
                              ...parentCategories.map(
                                (category) => DropdownMenuItem<String?>(
                                  value: category.id,
                                  child: Text(category.name),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedCategoryId = value;
                                _selectedChildCategoryId = null;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String?>(
                            initialValue: _selectedChildCategoryId,
                            decoration: const InputDecoration(
                              labelText: 'Child category',
                            ),
                            items: <DropdownMenuItem<String?>>[
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('None'),
                              ),
                              ...childCategories.map(
                                (category) => DropdownMenuItem<String?>(
                                  value: category.id,
                                  child: Text(category.name),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedChildCategoryId = value;
                              });
                            },
                          ),
                        ],
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
                const SizedBox(height: 12),
                _DateField(
                  label: 'Start date',
                  value: _selectedStartDate,
                  onTap: () async {
                    final picked = await _pickDate(_selectedStartDate);
                    if (picked != null) {
                      setState(() {
                        _selectedStartDate = picked;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                _TimeField(
                  label: 'Execution time',
                  value: _selectedExecutionTime,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _selectedExecutionTime,
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedExecutionTime = picked;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _reminderDaysBefore,
                  decoration: const InputDecoration(
                    labelText: 'Reminder before due date',
                  ),
                  items: const <DropdownMenuItem<int>>[
                    DropdownMenuItem<int>(value: 0, child: Text('Same day')),
                    DropdownMenuItem<int>(
                      value: 1,
                      child: Text('1 day before'),
                    ),
                    DropdownMenuItem<int>(
                      value: 3,
                      child: Text('3 days before'),
                    ),
                    DropdownMenuItem<int>(
                      value: 7,
                      child: Text('7 days before'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _reminderDaysBefore = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _autoCreate,
                  onChanged: (value) {
                    setState(() {
                      _autoCreate = value;
                    });
                  },
                  title: const Text('Auto-create transaction'),
                  subtitle: const Text(
                    'Create the transaction automatically when the rule becomes due.',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSaving ? null : _submit,
                  child: Text(_isSaving ? 'Saving...' : 'Save recurring rule'),
                ),
              ],
            ),
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load recurring rule form.\n$error'),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final String? destinationAccountId =
          _selectedType == TransactionType.transfer
          ? _selectedDestinationAccountId
          : null;
      final String? categoryId = _selectedType == TransactionType.transfer
          ? null
          : _selectedCategoryId;
      final String? childCategoryId = _selectedType == TransactionType.transfer
          ? null
          : _selectedChildCategoryId;
      final int amountMinor = _parseMinorUnits(_amountController.text);
      final DateTime scheduledStart = _combineDateAndTime(
        _selectedStartDate,
        _selectedExecutionTime,
      );

      if (_isEditing) {
        await widget.onUpdate!(
          UpdateRecurringRuleInput(
            title: _titleController.text,
            type: _selectedType,
            frequency: _selectedFrequency,
            accountId: _selectedAccountId!,
            destinationAccountId: destinationAccountId,
            categoryId: categoryId,
            childCategoryId: childCategoryId,
            amountMinor: amountMinor,
            note: _noteController.text,
            startDate: scheduledStart,
            nextDueDate: scheduledStart,
            reminderDaysBefore: _reminderDaysBefore,
            autoCreate: _autoCreate,
            isActive: widget.rule!.isActive,
          ),
        );
      } else {
        await widget.onCreate(
          CreateRecurringRuleInput(
            title: _titleController.text,
            type: _selectedType,
            frequency: _selectedFrequency,
            accountId: _selectedAccountId!,
            destinationAccountId: destinationAccountId,
            categoryId: categoryId,
            childCategoryId: childCategoryId,
            amountMinor: amountMinor,
            note: _noteController.text,
            startDate: scheduledStart,
            nextDueDate: scheduledStart,
            reminderDaysBefore: _reminderDaysBefore,
            autoCreate: _autoCreate,
          ),
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  int _parseMinorUnits(String value) {
    final double parsed = double.parse(value.trim());
    return (parsed * 100).round();
  }

  Future<DateTime?> _pickDate(DateTime initialDate) {
    final DateTime now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
  }

  String _frequencyLabel(RecurringFrequency frequency) {
    switch (frequency) {
      case RecurringFrequency.daily:
        return 'Daily';
      case RecurringFrequency.weekly:
        return 'Weekly';
      case RecurringFrequency.monthly:
        return 'Monthly';
      case RecurringFrequency.yearly:
        return 'Yearly';
    }
  }

  CategoryType _categoryTypeForTransaction(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return CategoryType.expense;
      case TransactionType.income:
        return CategoryType.income;
      case TransactionType.transfer:
        return CategoryType.expense;
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(AppDateFormatter.format(value)),
            const Icon(Icons.calendar_today_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final TimeOfDay value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(value.format(context)),
            const Icon(Icons.schedule_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
