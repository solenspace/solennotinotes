import 'package:hive_ce_flutter/hive_flutter.dart';

class DbHelper {
  static String userBoxName = 'user_v2';
  static String settingsBoxName = 'settings_v2';

  static Future<void> initBox(String boxName) async {
    await Hive.initFlutter();
    await Hive.openBox<dynamic>(boxName);
  }

  static Box<dynamic> getBox(String boxName) {
    return Hive.box<dynamic>(boxName);
  }

  static Future<void> insertUpdateData(
    String boxName,
    String key,
    dynamic value,
  ) async {
    await Hive.box<dynamic>(boxName).put(key, value);
  }

  static Future<void> deleteData(String boxName, String key) async {
    await Hive.box<dynamic>(boxName).delete(key);
  }

  static Future<void> closeBox(String boxName) async {
    await Hive.box<dynamic>(boxName).close();
  }

  static Future<void> deleteBox(String boxName) async {
    await Hive.deleteBoxFromDisk(boxName);
  }

  static Future<void> deleteAllBoxes() async {
    await Hive.deleteFromDisk();
  }

  static Future<void> clearBox(String boxName) async {
    await Hive.box<dynamic>(boxName).clear();
  }
}
