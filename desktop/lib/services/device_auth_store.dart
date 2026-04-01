import 'package:shared_preferences/shared_preferences.dart';

class DeviceAuthStore {
  Future<String?> loadToken(String deviceId, String role) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _tokenKey(deviceId, role);
    return prefs.getString(key);
  }

  Future<void> saveToken(String deviceId, String role, String token) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _tokenKey(deviceId, role);
    await prefs.setString(key, token);
  }

  String _tokenKey(String deviceId, String role) =>
      'gateway.deviceToken.${deviceId.toLowerCase()}.${role.toLowerCase()}';
}
