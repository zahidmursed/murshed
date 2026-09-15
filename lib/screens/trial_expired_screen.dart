import 'package:flutter/material.dart';

class TrialExpiredScreen extends StatelessWidget {
  final DateTime expiresAt;

  const TrialExpiredScreen({super.key, required this.expiresAt});

  @override
  Widget build(BuildContext context) {
    final date = '${expiresAt.day.toString().padLeft(2, '0')}-'
        '${expiresAt.month.toString().padLeft(2, '0')}-${expiresAt.year}';
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock_outlined,
                  color: Colors.teal, size: 72),
              const SizedBox(height: 20),
              const Text('ট্রায়াল সময় শেষ হয়েছে',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(
                'এই অ্যাপের ট্রায়াল মেয়াদ $date পর্যন্ত ছিল।\n'
                'ব্যবহার চালিয়ে যেতে অ্যাপের পূর্ণ সংস্করণ নিন।',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
