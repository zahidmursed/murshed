import 'package:flutter/material.dart';

import '../services/case_notes_service.dart';

/// কেস নোট-এর PIN গার্ড — নোট খোলার আগে ডাকা হয়।
/// - পিন সেট করা না থাকলে → সেট-করার বাধ্যতামূলক ডায়ালগ (বাতিল = প্রবেশ নয়)
/// - সেশনে আগেই আনলক থাকলে → সরাসরি true
/// - নইলে → পিন জিজ্ঞেস করে
class CaseNotesGuard {
  CaseNotesGuard._();

  /// true = নোট দেখার অনুমতি।
  static Future<bool> ensureUnlocked(BuildContext context) async {
    if (!await CaseNotesService.isPinSet()) {
      if (!context.mounted) return false;
      return await _setPinDialog(
        context,
        title: 'কেস নোট সুরক্ষা',
        message: 'কেস নোট সংবেদনশীল তথ্য — প্রবেশের আগে একটি পিন সেট করুন '
            '(কমপক্ষে ৪ ডিজিট)। এটি পরে Settings থেকে বদলানো/সরানো যাবে।',
      );
    }
    if (CaseNotesService.isUnlocked) return true;
    if (!context.mounted) return false;
    return await _unlockDialog(context);
  }

  /// পিন সেট (pin + confirm)। সফল হলে true।
  static Future<bool> _setPinDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    final pinCtl = TextEditingController();
    final confirmCtl = TextEditingController();
    String? error;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtl,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'নতুন পিন',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setDialogState(() => error = null),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmCtl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'পিন আবার দিন',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () async {
                final pin = pinCtl.text.trim();
                if (pin.length < 4 || !RegExp(r'^\d+$').hasMatch(pin)) {
                  setDialogState(
                      () => error = 'পিন কমপক্ষে ৪ ডিজিটের সংখ্যা হতে হবে');
                  return;
                }
                if (pin != confirmCtl.text.trim()) {
                  setDialogState(() => error = 'দুটি পিন মিলছে না');
                  return;
                }
                await CaseNotesService.setPin(pin);
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              child: const Text('সেট করুন'),
            ),
          ],
        ),
      ),
    ).then((v) => v == true);
  }

  /// Settings-এর "কেস নোট PIN" — সেট/পরিবর্তন/সরানোর মেনু।
  static Future<void> manageFromSettings(BuildContext context) async {
    final pinSet = await CaseNotesService.isPinSet();
    if (!pinSet) {
      if (!context.mounted) return;
      await _setPinDialog(
        context,
        title: 'কেস নোট PIN সেট করুন',
        message: 'নোট খোলার সময় এই পিন চাওয়া হবে (কমপক্ষে ৪ ডিজিট)।',
      );
      return;
    }
    if (!context.mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('কেস নোট PIN'),
        content: const Text('পিন পরিবর্তন বা সরানোর জন্য বাছুন। '
            'পিন সরালে নোট লকহীন হয়ে যাবে।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'remove'),
            child: const Text('পিন সরান',
                style: TextStyle(color: Colors.redAccent)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'change'),
            child: const Text('পিন পরিবর্তন'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // আগের পিন যাচাই
    final oldOk = await _verifyDialog(context, 'বর্তমান পিন দিন');
    if (!oldOk || !context.mounted) return;
    if (action == 'remove') {
      await CaseNotesService.removePin();
      messenger.showSnackBar(
          const SnackBar(content: Text('পিন সরানো হয়েছে — নোট এখন লকহীন')));
      return;
    }
    await _setPinDialog(context,
        title: 'নতুন পিন', message: 'নতুন পিন দিন (কমপক্ষে ৪ ডিজিট)।');
    messenger.showSnackBar(const SnackBar(content: Text('✅ পিন পরিবর্তিত')));
  }

  /// পিন জিজ্ঞেস করে আনলক। সফল হলে true।
  static Future<bool> _unlockDialog(BuildContext context) {
    final pinCtl = TextEditingController();
    String? error;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('কেস নোট — পিন দিন'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinCtl,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'পিন',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: error,
                ),
                onSubmitted: (_) => _submit(dialogContext, pinCtl,
                    setDialogState, (e) => setDialogState(() => error = e)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () => _submit(dialogContext, pinCtl, setDialogState,
                  (e) => setDialogState(() => error = e)),
              child: const Text('খুলুন'),
            ),
          ],
        ),
      ),
    ).then((v) => v == true);
  }

  static Future<void> _submit(
    BuildContext dialogContext,
    TextEditingController pinCtl,
    void Function(void Function()) setDialogState,
    void Function(String) onError,
  ) async {
    if (await CaseNotesService.verifyPin(pinCtl.text.trim())) {
      CaseNotesService.unlock();
      if (dialogContext.mounted) Navigator.pop(dialogContext, true);
    } else {
      onError('ভুল পিন');
      setDialogState(() {});
    }
  }

  /// বর্তমান পিন যাচাই (পরিবর্তন/সরানোর আগে)। সফল হলে true।
  static Future<bool> _verifyDialog(BuildContext context, String label) {
    final pinCtl = TextEditingController();
    String? error;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(label),
          content: TextField(
            controller: pinCtl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'পিন',
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () async {
                if (await CaseNotesService.verifyPin(pinCtl.text.trim())) {
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } else {
                  setDialogState(() => error = 'ভুল পিন');
                }
              },
              child: const Text('ঠিক আছে'),
            ),
          ],
        ),
      ),
    ).then((v) => v == true);
  }
}
