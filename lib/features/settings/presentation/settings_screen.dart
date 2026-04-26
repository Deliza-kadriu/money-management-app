import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          const _SettingsTile(
            title: 'Base currency',
            subtitle: 'USD for MVP, with future multi-currency support later.',
          ),
          const _SettingsTile(
            title: 'Notifications',
            subtitle: 'Recurring payment reminders and due-date alerts.',
          ),
          const _SettingsTile(
            title: 'Privacy',
            subtitle: 'Local-only storage for the MVP. No sign-in required.',
          ),
          const _SettingsTile(
            title: 'Export',
            subtitle: 'Filtered transaction and report export to Excel.',
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
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(subtitle),
        ),
      ),
    );
  }
}
