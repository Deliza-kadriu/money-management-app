import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:money_manager/domain/entities/app_settings.dart';
import 'package:money_manager/shared/providers/app_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        data: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            _SettingsSectionTitle(title: 'General'),
            _CurrencyTile(settings: settings),
            _NotificationsTile(settings: settings),
            const _PrivacyTile(),
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
