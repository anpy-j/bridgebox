import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/host_list_page.dart';
import 'services/host_repository.dart';
import 'services/secure_secrets.dart';

import 'theme/app_theme.dart';

import 'services/registry_repository.dart';

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
        Provider<RegistryRepository>(
          create: (_) => RegistryRepository(secrets: secrets),
        ),
      ],
      child: MaterialApp(
        title: '桥坞 Bridgebox',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: AppTheme.darkTheme,
        theme: AppTheme.darkTheme,
        home: const HostListPage(),
      ),
    );
  }
}
