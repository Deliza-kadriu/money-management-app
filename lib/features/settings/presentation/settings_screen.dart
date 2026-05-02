import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:money_manager/domain/entities/app_settings.dart';
import 'package:money_manager/shared/providers/app_providers.dart';
import 'package:share_plus/share_plus.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isCreatingBackup = false;
  bool _isRestoringBackup = false;
  bool _isImportingMyFinance = false;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        data: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            const _SettingsSectionTitle(title: 'General'),
            _ThemeTile(settings: settings),
            _CurrencyTile(settings: settings),
            _NotificationsTile(settings: settings),
            const _PrivacyTile(),
            _DataManagementSection(
              isCreatingBackup: _isCreatingBackup,
              isRestoringBackup: _isRestoringBackup,
              isImportingMyFinance: _isImportingMyFinance,
              onCreateBackup: _createBackup,
              onRestoreBackup: _restoreBackup,
              onImportMyFinance: _importMyFinance,
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.all(18),
                title: const Text('Recurring rules'),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Open the recurring payments manager.'),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/recurring'),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load settings.\n$error'),
          ),
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    if (_isCreatingBackup) {
      return;
    }

    setState(() {
      _isCreatingBackup = true;
    });

    try {
      final backupService = ref.read(dataBackupServiceProvider);
      final String filePath = await backupService.createBackupFile();
      if (!mounted) {
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          text: 'Money Manager backup',
          files: <XFile>[XFile(filePath)],
        ),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup file created successfully.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingBackup = false;
        });
      }
    }
  }

  Future<void> _restoreBackup() async {
    if (_isRestoringBackup) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup'),
        content: const Text(
          'This will replace your current local data with the selected backup file.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isRestoringBackup = true;
    });

    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
        withData: true,
      );
      if (result == null || !mounted) {
        return;
      }

      final PlatformFile pickedFile = result.files.single;
      final String rawJson;
      if (pickedFile.bytes != null) {
        rawJson = String.fromCharCodes(pickedFile.bytes!);
      } else if (pickedFile.path != null) {
        rawJson = await XFile(pickedFile.path!).readAsString();
      } else {
        throw const FormatException('Could not read the selected backup file.');
      }

      final backupService = ref.read(dataBackupServiceProvider);
      final summary = await backupService.restoreFromJsonString(rawJson);
      await ref.read(appSettingsProvider.notifier).reload();
      final settings = await ref.read(appSettingsServiceProvider).load();

      if (settings.notificationsEnabled) {
        await ref.read(notificationServiceProvider).initialize();
      }
      await ref.read(recurringReminderServiceProvider).syncActiveReminders();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup restored: ${summary.accountCount} accounts, ${summary.categoryCount} categories, ${summary.transactionCount} transactions, ${summary.recurringRuleCount} recurring rules.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isRestoringBackup = false;
        });
      }
    }
  }

  Future<void> _importMyFinance() async {
    if (_isImportingMyFinance) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import MyFinance export'),
        content: const Text(
          'This will delete your current accounts, categories, transactions, recurring rules, and imported app data before importing the selected MyFinance JSON file.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isImportingMyFinance = true;
    });

    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
        withData: true,
      );
      if (result == null || !mounted) {
        return;
      }

      final PlatformFile pickedFile = result.files.single;
      final String rawJson;
      if (pickedFile.bytes != null) {
        rawJson = String.fromCharCodes(pickedFile.bytes!);
      } else if (pickedFile.path != null) {
        rawJson = await XFile(pickedFile.path!).readAsString();
      } else {
        throw const FormatException('Could not read the selected JSON file.');
      }

      final summary = await ref
          .read(myFinanceImportServiceProvider)
          .replaceWithImport(rawJson);
      await ref.read(recurringReminderServiceProvider).syncActiveReminders();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported MyFinance data: ${summary.accountCount} accounts, ${summary.categoryCount} categories, ${summary.transactionCount} transactions, ${summary.transferCount} transfers.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('MyFinance import failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImportingMyFinance = false;
        });
      }
    }
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _CurrencyTile extends ConsumerWidget {
  const _CurrencyTile({required this.settings});

  final AppSettings settings;

  static const List<String> _currencies = <String>[
    'USD',
    'EUR',
    'GBP',
    'CHF',
    'ALL',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        title: const Text('Base currency'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Used as the default currency for new accounts in this MVP.',
          ),
        ),
        trailing: DropdownButton<String>(
          value: settings.baseCurrencyCode,
          underline: const SizedBox.shrink(),
          items: _currencies
              .map(
                (currency) => DropdownMenuItem<String>(
                  value: currency,
                  child: Text(currency),
                ),
              )
              .toList(growable: false),
          onChanged: (value) async {
            if (value == null) {
              return;
            }
            await ref
                .read(appSettingsProvider.notifier)
                .updateBaseCurrencyCode(value);
          },
        ),
      ),
    );
  }
}

class _ThemeTile extends ConsumerWidget {
  const _ThemeTile({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        title: const Text('Appearance'),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Choose light mode, dark mode, or follow the device setting.',
          ),
        ),
        trailing: DropdownButton<AppThemePreference>(
          value: settings.themePreference,
          underline: const SizedBox.shrink(),
          items: AppThemePreference.values
              .map(
                (mode) => DropdownMenuItem<AppThemePreference>(
                  value: mode,
                  child: Text(_themeLabel(mode)),
                ),
              )
              .toList(growable: false),
          onChanged: (value) async {
            if (value == null) {
              return;
            }

            await ref
                .read(appSettingsProvider.notifier)
                .updateThemePreference(value);
          },
        ),
      ),
    );
  }

  static String _themeLabel(AppThemePreference mode) {
    switch (mode) {
      case AppThemePreference.system:
        return 'System';
      case AppThemePreference.light:
        return 'Light';
      case AppThemePreference.dark:
        return 'Dark';
    }
  }
}

class _NotificationsTile extends ConsumerWidget {
  const _NotificationsTile({required this.settings});

  final AppSettings settings;

  static const List<int> _leadDayOptions = <int>[0, 1, 2, 3, 7];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notifications'),
              subtitle: const Text(
                'Enable recurring payment reminders and due updates.',
              ),
              value: settings.notificationsEnabled,
              onChanged: (value) async {
                if (value) {
                  await ref.read(notificationServiceProvider).initialize();
                }
                await ref
                    .read(appSettingsProvider.notifier)
                    .updateNotificationsEnabled(value);
                await ref
                    .read(recurringReminderServiceProvider)
                    .syncActiveReminders();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Default reminder lead time',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                DropdownButton<int>(
                  value: settings.reminderLeadDays,
                  items: _leadDayOptions
                      .map(
                        (days) => DropdownMenuItem<int>(
                          value: days,
                          child: Text(days == 0 ? 'Same day' : '$days day(s)'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: settings.notificationsEnabled
                      ? (value) async {
                          if (value == null) {
                            return;
                          }
                          await ref
                              .read(appSettingsProvider.notifier)
                              .updateReminderLeadDays(value);
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyTile extends StatelessWidget {
  const _PrivacyTile();

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: EdgeInsets.all(18),
        title: Text('Privacy'),
        subtitle: Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'All data stays on-device for the MVP. No sign-in or cloud sync is enabled.',
          ),
        ),
      ),
    );
  }
}

class _DataManagementSection extends StatelessWidget {
  const _DataManagementSection({
    required this.isCreatingBackup,
    required this.isRestoringBackup,
    required this.isImportingMyFinance,
    required this.onCreateBackup,
    required this.onRestoreBackup,
    required this.onImportMyFinance,
  });

  final bool isCreatingBackup;
  final bool isRestoringBackup;
  final bool isImportingMyFinance;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onRestoreBackup;
  final Future<void> Function() onImportMyFinance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SettingsSectionTitle(title: 'Data'),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: <Widget>[
              ListTile(
                contentPadding: const EdgeInsets.all(18),
                title: const Text('Create backup'),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Export a full local backup including accounts, categories, transactions, recurring rules, and settings.',
                  ),
                ),
                trailing: isCreatingBackup
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Icon(Icons.ios_share_rounded),
                onTap: isCreatingBackup ? null : onCreateBackup,
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.all(18),
                title: const Text('Restore backup'),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Replace current local data using a previously exported JSON backup file.',
                  ),
                ),
                trailing: isRestoringBackup
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Icon(Icons.upload_file_rounded),
                onTap: isRestoringBackup ? null : onRestoreBackup,
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.all(18),
                title: const Text('Import MyFinance JSON'),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Delete current app data and import accounts, categories, transactions, and transfers from a MyFinance export file.',
                  ),
                ),
                trailing: isImportingMyFinance
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Icon(Icons.file_download_rounded),
                onTap: isImportingMyFinance ? null : onImportMyFinance,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
