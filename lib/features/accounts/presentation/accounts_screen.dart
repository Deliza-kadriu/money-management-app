import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/core/utils/account_visuals.dart';
import 'package:money_manager/core/utils/currency_formatter.dart';
import 'package:money_manager/domain/entities/account.dart' as domain;
import 'package:money_manager/domain/enums/account_type.dart';
import 'package:money_manager/domain/repositories/account_repository.dart';
import 'package:money_manager/shared/providers/app_providers.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: <Widget>[
          IconButton(
            onPressed: () => _showCreateAccountSheet(context, ref),
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Create account',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateAccountSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add account'),
      ),
      body: accountsAsync.when(
        data: (accounts) {
          if (accounts.isEmpty) {
            return _EmptyAccountsState(
              onCreate: () => _showCreateAccountSheet(context, ref),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: accounts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final account = accounts[index];

              return Card(
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
                      }
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
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
              );
            },
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

class _EmptyAccountsState extends StatelessWidget {
  const _EmptyAccountsState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.account_balance_wallet_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'No accounts yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your first account to start tracking balances and transactions.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateAccountSheet extends StatefulWidget {
  const _CreateAccountSheet({
    required this.onCreate,
    this.onUpdate,
    this.account,
  });

  final Future<void> Function(CreateAccountInput input) onCreate;
  final Future<void> Function(UpdateAccountInput input)? onUpdate;
  final domain.Account? account;

  @override
  State<_CreateAccountSheet> createState() => _CreateAccountSheetState();
}

class _CreateAccountSheetState extends State<_CreateAccountSheet> {
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
    final MediaQueryData mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        mediaQuery.viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Text(
              _isEditing ? 'Edit account' : 'Create account',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Account name'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
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
                  _selectedIconKey = _defaultIconKey(value);
                });
              },
            ),
            const SizedBox(height: 12),
            if (_isEditing)
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Opening balance'),
                child: Text(_openingBalanceController.text),
              )
            else
              TextFormField(
                controller: _openingBalanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Opening balance'),
                validator: (value) {
                  final parsed = double.tryParse((value ?? '').trim());
                  if (parsed == null) {
                    return 'Enter a valid amount';
                  }
                  if (parsed < 0) {
                    return 'Use 0 or a positive amount';
                  }
                  return null;
                },
              ),
            const SizedBox(height: 16),
            Text('Color', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: AccountVisuals.palette
                  .map((colorValue) {
                    final bool selected = colorValue == _selectedColorValue;
                    final Color color = AccountVisuals.colorFromValue(
                      colorValue,
                    );

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedColorValue = colorValue;
                        });
                      },
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: color,
                        child: selected
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: AccountVisuals.iconMap.entries
                  .map((entry) {
                    final bool selected = entry.key == _selectedIconKey;

                    return ChoiceChip(
                      label: Icon(entry.value, size: 20),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _selectedIconKey = entry.key;
                        });
                      },
                    );
                  })
                  .toList(growable: false),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _submit,
              child: Text(_isSaving ? 'Saving...' : 'Save account'),
            ),
          ],
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
      if (_isEditing) {
        await widget.onUpdate!(
          UpdateAccountInput(
            name: _nameController.text,
            type: _selectedType,
            currencyCode: widget.account!.currencyCode,
            colorValue: _selectedColorValue,
            iconKey: _selectedIconKey,
            isActive: widget.account!.isActive,
          ),
        );
      } else {
        final int openingBalanceMinor = _parseMinorUnits(
          _openingBalanceController.text,
        );

        await widget.onCreate(
          CreateAccountInput(
            name: _nameController.text,
            type: _selectedType,
            openingBalanceMinor: openingBalanceMinor,
            currencyCode: 'USD',
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

  String _defaultIconKey(AccountType type) {
    switch (type) {
      case AccountType.cash:
        return 'wallet';
      case AccountType.bankAccount:
        return 'bank';
      case AccountType.creditCard:
        return 'credit_card';
      case AccountType.savings:
        return 'savings';
      case AccountType.other:
        return 'account';
    }
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
