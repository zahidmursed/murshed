import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/student_provider.dart';
import 'screens/list_screen.dart';
import 'screens/trial_expired_screen.dart';
import 'services/trial_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final trialStatus = await TrialService.load(prefs);
  runApp(MyApp(prefs: prefs, trialStatus: trialStatus));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  final TrialStatus trialStatus;

  const MyApp({super.key, required this.prefs, required this.trialStatus});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StudentProvider(prefs: prefs),
      child: Consumer<StudentProvider>(
        builder: (_, provider, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Dakhila Camera',
          theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.dark,
            ),
          ),
          themeMode: provider.themeMode,
          home: trialStatus.isExpired
              ? TrialExpiredScreen(expiresAt: trialStatus.expiresAt!)
              : const ListScreen(),
        ),
      ),
    );
  }
}
