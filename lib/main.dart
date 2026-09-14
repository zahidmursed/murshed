import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/student_provider.dart';
import 'screens/list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StudentProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Dakhila Camera',
        theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
        home: const ListScreen(),
      ),
    );
  }
}
