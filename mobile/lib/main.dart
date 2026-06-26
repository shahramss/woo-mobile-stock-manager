import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authProvider = AuthProvider();
  await authProvider.loadSavedSession();

  runApp(
    ChangeNotifierProvider.value(
      value: authProvider,
      child: const WooMobileStockManagerApp(),
    ),
  );
}
