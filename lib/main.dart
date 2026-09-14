import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/student_provider.dart';
import 'screens/list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(prefs: prefs));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;

  const MyApp({super.key, required this.prefs});

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
          home: const ListScreen(),
        ),
      ),
    );
  }
}
