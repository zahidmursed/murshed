import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/case_notes_provider.dart';
import 'providers/student_provider.dart';
import 'providers/teacher_provider.dart';
import 'screens/list_screen.dart';
import 'screens/trial_expired_screen.dart';
import 'services/sync_service.dart';
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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StudentProvider(prefs: prefs)),
        ChangeNotifierProvider(create: (_) => TeacherProvider()),
        ChangeNotifierProvider(create: (_) => CaseNotesProvider()),
        // S2: অফলাইন-ফার্স্ট সিঙ্ক ইঞ্জিন। লগইন না থাকলেও ক্ষতি নেই —
        // ব্যাজ/হিসাব দেখায়, নেটওয়ার্ক-বাধ্যতা কিছুই তৈরি করে না।
        ChangeNotifierProvider(
            create: (_) => SyncService(prefs: prefs)..init()),
      ],
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
