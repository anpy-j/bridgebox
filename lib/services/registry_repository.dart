import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'secure_secrets.dart';

class RegistryRepository {
  RegistryRepository({required SecureSecrets secrets}) : _secrets = secrets;

  static const _prefsKey = 'bridgebox.registries.v1';
  final SecureSecrets _secrets;
  final _uuid = const Uuid();

  Future<List<DockerRegistryConfig>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    final items = jsonDecode(raw) as List<dynamic>;
    return items
        .map((e) => DockerRegistryConfig.fromJson(Map<String, Object?>.from(e as Map)))
        .toList();
  }

  Future<DockerRegistryConfig> save({
    String? existingId,
    required String name,
    required String registryUrl,
    required String namespace,
    String? username,
    String? password,
  }) async {
    final id = existingId ?? _uuid.v4();
    final config = DockerRegistryConfig(
      id: id,
      name: name,
      registryUrl: registryUrl,
      namespace: namespace,
      username: username ?? '',
    );

    if (password != null && password.isNotEmpty) {
      await _secrets.saveRegistryPassword(id, password);
    }

    final all = await list();
    final next = [
      ...all.where((r) => r.id != id),
      config,
    ]..sort((a, b) => a.name.compareTo(b.name));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(next.map((r) => r.toJson()).toList()),
    );
    return config;
  }

  Future<void> remove(String id) async {
    await _secrets.deleteRegistry(id);
    final all = await list();
    final next = all.where((r) => r.id != id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(next.map((r) => r.toJson()).toList()),
    );
  }

  Future<String?> getPassword(String id) => _secrets.registryPassword(id);
}
