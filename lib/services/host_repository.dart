import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'secure_secrets.dart';

class HostRepository {
  HostRepository({required SecureSecrets secrets}) : _secrets = secrets;

  static const _prefsKey = 'bridgebox.hosts.v1';
  final SecureSecrets _secrets;
  final _uuid = const Uuid();

  Future<List<HostProfile>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    final items = jsonDecode(raw) as List<dynamic>;
    return items
        .map((e) => HostProfile.fromJson(Map<String, Object?>.from(e as Map)))
        .toList();
  }

  Future<HostProfile> upsert({
    HostProfile? existing,
    required String name,
    required String host,
    required int port,
    required String username,
    required AuthKind authKind,
    String? password,
    String? privateKeyPem,
    String? keyPassphrase,
  }) async {
    final profile = existing?.copyWith(
          name: name,
          host: host,
          port: port,
          username: username,
          authKind: authKind,
        ) ??
        HostProfile(
          id: _uuid.v4(),
          name: name,
          host: host,
          port: port,
          username: username,
          authKind: authKind,
        );

    if (authKind == AuthKind.password) {
      if (password != null && password.isNotEmpty) {
        await _secrets.savePassword(profile.id, password);
      }
    } else if (privateKeyPem != null && privateKeyPem.isNotEmpty) {
      await _secrets.savePrivateKey(
        hostId: profile.id,
        pem: privateKeyPem,
        passphrase: keyPassphrase,
      );
    }

    final all = await list();
    final next = [
      ...all.where((h) => h.id != profile.id),
      profile,
    ]..sort((a, b) => a.name.compareTo(b.name));
    await _save(next);
    return profile;
  }

  Future<void> remove(String id) async {
    await _secrets.deleteHost(id);
    final next = (await list()).where((h) => h.id != id).toList();
    await _save(next);
  }

  Future<void> _save(List<HostProfile> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(hosts.map((h) => h.toJson()).toList()),
    );
  }
}
