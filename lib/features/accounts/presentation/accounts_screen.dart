import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/core/utils/account_visuals.dart';
import 'package:money_manager/core/utils/currency_formatter.dart';
import 'package:money_manager/domain/entities/account.dart' as domain;
import 'package:money_manager/domain/enums/account_type.dart';
import 'package:money_manager/domain/repositories/account_repository.dart';
import 'package:money_manager/shared/providers/app_providers.dart';
import 'package:money_manager/shared/widgets/app_mode_tabs.dart';

enum AccountListMode { active, archived }

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  AccountListMode _mode = AccountListMode.active;

  @override
  Widget build(BuildContext context) {
    final bool archivedOnly = _mode == AccountListMode.archived;
    final accountsAsync = ref.watch(accountsByModeProvider(archivedOnly));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: <Widget>[
          if (!archivedOnly)
            IconButton(
              onPressed: () => _showCreateAccountSheet(context, ref),
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: 'Create account',
            ),
        ],
      ),
      floatingActionButton: archivedOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showCreateAccountSheet(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add account'),
            ),
      body: accountsAsync.when(
        data: (accounts) {
          if (accounts.isEmpty) {
            return _EmptyAccountsState(
              mode: _mode,
              onModeChanged: (mode) {
                setState(() {
                  _mode = mode;
                });
              },
              onCreate: archivedOnly
                  ? null
                  : () => _showCreateAccountSheet(context, ref),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: <Widget>[
              _AccountToolbar(
                mode: _mode,
                onModeChanged: (mode) {
                  setState(() {
                    _mode = mode;
                  });
                },
              ),
              const SizedBox(height: 16),
              ...accounts.map(
                (account) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: account.color.withValues(alpha: 0.16),
                      foregroundColor: account.color,
                      child: Icon(account.icon),
                    ),
                    title: Text(account.name),
                    subtitle: Text(_accountTypeLabel(account.type)),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'edit') {
                          await _showEditAccountSheet(context, ref, account);
                        } else if (value == 'archive') {
                          await ref
                              .read(accountRepositoryProvider)
                              .softDeleteAccount(account.id);
                        } else if (value == 'restore') {
                          await ref
                              .read(accountRepositoryProvider)
                              .restoreAccount(account.id);
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
                              account.currentBalanceMinor,
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            account.currencyCode,
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
            child: Text('Failed to load accounts.\n$error'),
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateAccountSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateAccountSheet(
        onCreate: (input) async {
          await ref.read(accountRepositoryProvider).createAccount(input);
        },
      ),
    );
  }

  Future<void> _showEditAccountSheet(
    BuildContext context,
    WidgetRef ref,
    domain.Account account,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateAccountSheet(
        account: account,
        onCreate: (input) async {
          await ref.read(accountRepositoryProvider).createAccount(input);
        },
        onUpdate: (input) async {
          await ref
              .read(accountRepositoryProvider)
              .updateAccount(account.id, input);
        },
      ),
    );
  }

  String _accountTypeLabel(AccountType type) {
    switch (type) {
      case AccountType.cash:
        return 'Cash';
      case AccountType.bankAccount:
        return 'Bank account';
      case AccountType.creditCard:
        return 'Credit card';
      case AccountType.savings:
        return 'Savings';
      case AccountType.other:
        return 'Other';
    }
  }
}

class _AccountToolbar extends StatelessWidget {
  const _AccountToolbar({required this.mode, required this.onModeChanged});

  final AccountListMode mode;
  final ValueChanged<AccountListMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return AppModeTabs<AccountListMode>(
      selected: mode,
      onChanged: onModeChanged,
      items: const <AppModeTabItem<AccountListMode>>[
        AppModeTabItem<AccountListMode>(
          value: AccountListMode.active,
          label: 'Active',
          icon: Icons.account_balance_wallet_outlined,
        ),
        AppModeTabItem<AccountListMode>(
          value: AccountListMode.archived,
          label: 'Archived',
          icon: Icons.archive_outlined,
        ),
      ],
    );
  }
}

class _EmptyAccountsState extends StatelessWidget {
  const _EmptyAccountsState({
    required this.mode,
    required this.onModeChanged,
    required this.onCreate,
  });

  final AccountListMode mode;
  final ValueChanged<AccountListMode> onModeChanged;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final bool archivedOnly = mode == AccountListMode.archived;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: <Widget>[
          _AccountToolbar(mode: mode, onModeChanged: onModeChanged),
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
                          : Icons.account_balance_wallet_outlined,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      archivedOnly ? 'No archived accounts' : 'No accounts yet',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      archivedOnly
                          ? 'Archived accounts will appear here and can be restored.'
                          : 'Create your first account to start tracking balances and transactions.',
                      textAlign: TextAlign.center,
                    ),
                    if (!archivedOnly) ...<Widget>[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: onCreate,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create account'),
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

class _CreateAccountSheet extends ConsumerStatefulWidget {
  const _CreateAccountSheet({
    required this.onCreate,
    this.onUpdate,
    this.account,
  });

  final Future<void> Function(CreateAccountInput input) onCreate;
  final Future<void> Function(UpdateAccountInput input)? onUpdate;
  final domain.Account? account;

  @override
  ConsumerState<_CreateAccountSheet> createState() =>
      _CreateAccountSheetState();
}

class _CreateAccountSheetState extends ConsumerState<_CreateAccountSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _openingBalanceController = TextEditingController(
    text: '0.00',
  );

  AccountType _selectedType = AccountType.bankAccount;
  int _selectedColorValue = AccountVisuals.palette.first;
  String _selectedIconKey = 'bank';
  bool _isSaving = false;
  bool get _isEditing => widget.account != null;

  @override
  void initState() {
    super.initState();

    final account = widget.account;
    if (account == null) {
      return;
    }

    _nameController.text = account.name;
    _openingBalanceController.text = (account.openingBalanceMinor / 100)
        .toStringAsFixed(2);
    _selectedType = account.type;
    _selectedColorValue = account.colorValue;
    _selectedIconKey = account.iconKey;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String baseCurrencyCode =
        ref.watch(appSettingsProvider).valueOrNull?.baseCurrencyCode ?? 'USD';
    final MediaQueryData mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        mediaQuery.viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _isEditing ? 'Edit account' : 'Add account',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Account name'),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Enter an account name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccountType>(
                initialValue: _selectedType,
                decoration: const InputDecoration(labelText: 'Account type'),
                items: AccountType.values
                    .map(
                      (type) => DropdownMenuItem<AccountType>(
                        value: type,
                        child: Text(_accountTypeLabel(type)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedType = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _openingBalanceController,
                enabled: !_isEditing,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Opening balance'),
                validator: (value) {
                  final parsed = double.tryParse((value ?? '').trim());
                  if (parsed == null) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Currency'),
                child: Text(baseCurrencyCode),
              ),
              const SizedBox(height: 16),
              Text('Color', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: AccountVisuals.palette
                    .map((value) {
                      final Color color = AccountVisuals.colorFromValue(value);
                      final bool isSelected = _selectedColorValue == value;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedColorValue = value;
                          });
                        },
                        child: CircleAvatar(
                          radius: isSelected ? 22 : 20,
                          backgroundColor: color,
                          child: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              Text('Icon', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: AccountVisuals.iconMap.entries
                    .map((entry) {
                      final bool isSelected = _selectedIconKey == entry.key;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedIconKey = entry.key;
                          });
                        },
                        child: CircleAvatar(
                          radius: isSelected ? 22 : 20,
                          backgroundColor: isSelected
                              ? AccountVisuals.colorFromValue(
                                  _selectedColorValue,
                                )
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          foregroundColor: isSelected
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                          child: Icon(entry.value),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSaving ? null : _submit,
                child: Text(
                  _isSaving
                      ? 'Saving...'
                      : _isEditing
                      ? 'Update account'
                      : 'Save account',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final String baseCurrencyCode =
        ref.read(appSettingsProvider).valueOrNull?.baseCurrencyCode ?? 'USD';

    setState(() {
      _isSaving = true;
    });

    try {
      if (_isEditing) {
        await widget.onUpdate?.call(
          UpdateAccountInput(
            name: _nameController.text,
            type: _selectedType,
            currencyCode: baseCurrencyCode,
            colorValue: _selectedColorValue,
            iconKey: _selectedIconKey,
            isActive: true,
          ),
        );
      } else {
        await widget.onCreate(
          CreateAccountInput(
            name: _nameController.text,
            type: _selectedType,
            openingBalanceMinor: _parseMinorUnits(
              _openingBalanceController.text,
            ),
            currencyCode: baseCurrencyCode,
            colorValue: _selectedColorValue,
            iconKey: _selectedIconKey,
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

  int _parseMinorUnits(String value) {
    final double parsed = double.parse(value.trim());
    return (parsed * 100).round();
  }

  String _accountTypeLabel(AccountType type) {
    switch (type) {
      case AccountType.cash:
        return 'Cash';
      case AccountType.bankAccount:
        return 'Bank account';
      case AccountType.creditCard:
        return 'Credit card';
      case AccountType.savings:
        return 'Savings';
      case AccountType.other:
        return 'Other';
    }
  }
}
