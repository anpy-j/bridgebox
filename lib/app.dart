import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/host_list_page.dart';
import 'services/host_repository.dart';
import 'services/secure_secrets.dart';

class BridgeboxApp extends StatelessWidget {
  const BridgeboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    final secrets = SecureSecrets();
    return MultiProvider(
      providers: [
        Provider<SecureSecrets>.value(value: secrets),
        Provider<HostRepository>(
          create: (_) => HostRepository(secrets: secrets),
        ),
      ],
      child: MaterialApp(
        title: '桥坞',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1B4D6E),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF7EB6D6),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HostListPage(),
      ),
    );
  }
}
