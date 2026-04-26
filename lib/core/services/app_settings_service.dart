import 'dart:convert';
import 'dart:io';

import 'package:money_manager/domain/entities/app_settings.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppSettingsService {
  Future<AppSettings> load() async {
    try {
      final File file = await _settingsFile();
      if (!await file.exists()) {
        return const AppSettings.defaults();
      }

      final String raw = await file.readAsString();
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return const AppSettings.defaults();
      }

      return AppSettings.fromJson(decoded);
    } catch (_) {
      return const AppSettings.defaults();
    }
  }

  Future<AppSettings> save(AppSettings settings) async {
    final File file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()));
    return settings;
  }

  Future<File> _settingsFile() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, 'app_settings.json'));
  }
}
