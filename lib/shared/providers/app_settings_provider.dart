import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/core/services/app_settings_service.dart';
import 'package:money_manager/domain/entities/app_settings.dart';

class AppSettingsController extends StateNotifier<AsyncValue<AppSettings>> {
  AppSettingsController(this._service) : super(const AsyncValue.loading()) {
    _load();
  }

  final AppSettingsService _service;

  Future<void> _load() async {
    state = await AsyncValue.guard(_service.load);
  }

  Future<void> updateBaseCurrencyCode(String value) async {
    final AppSettings current =
        state.valueOrNull ?? const AppSettings.defaults();
    final AppSettings next = current.copyWith(baseCurrencyCode: value);
    state = AsyncValue.data(next);
    state = await AsyncValue.guard(() => _service.save(next));
  }

  Future<void> updateNotificationsEnabled(bool value) async {
    final AppSettings current =
        state.valueOrNull ?? const AppSettings.defaults();
    final AppSettings next = current.copyWith(notificationsEnabled: value);
    state = AsyncValue.data(next);
    state = await AsyncValue.guard(() => _service.save(next));
  }

  Future<void> updateReminderLeadDays(int value) async {
    final AppSettings current =
        state.valueOrNull ?? const AppSettings.defaults();
    final AppSettings next = current.copyWith(reminderLeadDays: value);
    state = AsyncValue.data(next);
    state = await AsyncValue.guard(() => _service.save(next));
  }
}
