import 'package:money_manager/core/services/app_settings_service.dart';
import 'package:money_manager/core/services/notification_service.dart';
import 'package:money_manager/domain/entities/recurring_rule.dart';
import 'package:money_manager/domain/enums/transaction_type.dart';
import 'package:money_manager/domain/repositories/recurring_rule_repository.dart';

class RecurringReminderService {
  RecurringReminderService(
    this._notificationService,
    this._settingsService,
    this._recurringRuleRepository,
  );

  final NotificationService _notificationService;
  final AppSettingsService _settingsService;
  final RecurringRuleRepository _recurringRuleRepository;

  Future<void> syncActiveReminders() async {
    final settings = await _settingsService.load();
    final rules = await _recurringRuleRepository.getRecurringRules();

    for (final rule in rules) {
      if (!rule.isActive ||
          rule.deletedAt != null ||
          !settings.notificationsEnabled) {
        await cancelForRule(rule.id);
        continue;
      }

      await scheduleForRule(rule);
    }
  }

  Future<void> scheduleForRule(RecurringRule rule) async {
    final String body =
        'Recurring ${_typeLabel(rule.type).toLowerCase()} is due on ${_dateLabel(rule.nextDueDate)}.';
    await _notificationService.scheduleRecurringRuleReminder(
      notificationId: notificationIdForRule(rule.id),
      title: rule.title,
      body: body,
      scheduledFor: _scheduledReminderTime(
        dueDate: rule.nextDueDate,
        reminderDaysBefore: rule.reminderDaysBefore,
      ),
    );
  }

  Future<void> scheduleForInput({
    required String ruleId,
    required String title,
    required TransactionType type,
    required DateTime nextDueDate,
    required int reminderDaysBefore,
  }) async {
    final settings = await _settingsService.load();
    if (!settings.notificationsEnabled) {
      await cancelForRule(ruleId);
      return;
    }

    await _notificationService.scheduleRecurringRuleReminder(
      notificationId: notificationIdForRule(ruleId),
      title: title,
      body:
          'Recurring ${_typeLabel(type).toLowerCase()} is due on ${_dateLabel(nextDueDate)}.',
      scheduledFor: _scheduledReminderTime(
        dueDate: nextDueDate,
        reminderDaysBefore: reminderDaysBefore,
      ),
    );
  }

  Future<void> cancelForRule(String ruleId) {
    return _notificationService.cancel(notificationIdForRule(ruleId));
  }

  int notificationIdForRule(String ruleId) {
    return ruleId.hashCode & 0x7fffffff;
  }

  DateTime _scheduledReminderTime({
    required DateTime dueDate,
    required int reminderDaysBefore,
  }) {
    final DateTime reminderDate = dueDate.subtract(
      Duration(days: reminderDaysBefore),
    );
    final DateTime scheduled = DateTime(
      reminderDate.year,
      reminderDate.month,
      reminderDate.day,
      9,
    );

    if (scheduled.isAfter(DateTime.now())) {
      return scheduled;
    }

    return DateTime.now().add(const Duration(seconds: 5));
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
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
