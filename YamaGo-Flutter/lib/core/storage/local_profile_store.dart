import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalProfileStore {
  LocalProfileStore(this._prefs);

  static const _nicknameKey = 'profile.nickname';
  static const _lastGameIdKey = 'profile.lastGameId';

  final SharedPreferences _prefs;

  String? get nickname => _prefs.getString(_nicknameKey);
  String? get lastGameId => _prefs.getString(_lastGameIdKey);

  Future<void> saveNickname(String value) async {
    await _prefs.setString(_nicknameKey, value);
  }

  Future<void> saveLastGameId(String value) async {
    await _prefs.setString(_lastGameIdKey, value);
  }

  Future<void> clearProfile() async {
    await _prefs.remove(_nicknameKey);
    await _prefs.remove(_lastGameIdKey);
  }
}

final localProfileStoreProvider =
    FutureProvider<LocalProfileStore>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return LocalProfileStore(prefs);
});
