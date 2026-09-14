import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../models/models.dart';
import 'secure_secrets.dart';

class SshSession {
  SshSession({
    required this.profile,
    required SecureSecrets secrets,
  }) : _secrets = secrets;

  final HostProfile profile;
  final SecureSecrets _secrets;

  SSHClient? _client;

  bool get isConnected => _client != null;

  Future<void> connect() async {
    await disconnect();
    final socket = await SSHSocket.connect(
      profile.host,
      profile.port,
      timeout: const Duration(seconds: 15),
    );

    List<SSHKeyPair>? identities;
    FutureOr<String?> Function()? onPasswordRequest;

    if (profile.authKind == AuthKind.privateKey) {
      final pem = await _secrets.privateKey(profile.id);
      if (pem == null || pem.trim().isEmpty) {
        throw StateError('未找到该主机的私钥，请重新导入');
      }
      final pass = await _secrets.keyPassphrase(profile.id);
      identities = SSHKeyPair.fromPem(pem, pass);
    } else {
      final password = await _secrets.password(profile.id);
      if (password == null || password.isEmpty) {
        throw StateError('未找到该主机的密码');
      }
      onPasswordRequest = () => password;
    }

    _client = SSHClient(
      socket,
      username: profile.username,
      identities: identities,
      onPasswordRequest: onPasswordRequest,
    );
  }

  Future<CommandResult> run(
    String command, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('尚未连接');
    }
    final session = await client.execute(command);
    try {
      final stdoutFuture = utf8.decoder.bind(session.stdout).join();
      final stderrFuture = utf8.decoder.bind(session.stderr).join();
      final results = await Future.wait([
        stdoutFuture,
        stderrFuture,
        session.done,
      ]).timeout(timeout);
      return CommandResult(
        exitCode: session.exitCode ?? 1,
        stdout: results[0] as String,
        stderr: results[1] as String,
      );
    } finally {
      session.close();
    }
  }

  Future<void> disconnect() async {
    _client?.close();
    _client = null;
  }
}
