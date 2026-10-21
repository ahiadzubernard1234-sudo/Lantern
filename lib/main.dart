import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lantern/core/di/service_locator.dart';
import 'package:lantern/core/logging/app_log.dart';
import 'package:lantern/features/app/presentation/pages/app_shell.dart';
import 'package:lantern/core/theme/app_theme.dart';

void main() {
  AppLog.install();

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      AppLog.add('error', 'Flutter error: ${details.exceptionAsString()}');
      FlutterError.presentError(details);
    };

    await setupServiceLocator();
    runApp(const ProviderScope(child: LANternApp()));
  }, (error, stack) {
    AppLog.add('error', 'Uncaught error: $error');
  });
}

class LANternApp extends ConsumerWidget {
  const LANternApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'LANtern',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const AppShell(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en', 'US')],
    );
  }
}
