import 'dart:convert';
import 'dart:io';

import 'package:dakhila_camera/utils/name_transliterator.dart';
import 'package:dakhila_camera/utils/translit/bengali_interindic.dart';
import 'package:dakhila_camera/utils/translit/interindic_arabic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NameTransliterator', () {
    test('dictionary hits: full match (abbreviation + dict tokens)', () {
      // কর্পাস-মান (২১k ভোট): Hossain (৮৫১), Ayesha (২০৯), Begum-AR بيجوم
      final r = NameTransliterator.transliterate('মোঃ আব্দুল্লাহ হোসেন');
      expect(r.english, 'Md. Abdullah Hossain');
      expect(r.arabic, 'محمد عبد الله حسين');
      expect(r.allKnown, isTrue);
      expect(r.unknown, 0);
    });

    test('abbreviation normalization: মোসা:/আয়েশা variants', () {
      final r = NameTransliterator.transliterate('মোসা: আয়েশা বেগম');
      expect(r.english, 'Mst. Ayesha Begum');
      expect(r.arabic, 'مسماة عائشة بيجوم');
      expect(r.allKnown, isTrue);
    });

    test('prefix without space: মোঃআব্দুল্লাহ splits into two tokens', () {
      final r = NameTransliterator.transliterate('মোঃআব্দুল্লাহ');
      expect(r.english, 'Md. Abdullah');
      expect(r.allKnown, isTrue);
    });

    test('rule fallback marks unknown tokens', () {
      final r = NameTransliterator.transliterate('জগদীশ চন্দ্র');
      expect(r.english, isNotEmpty);
      expect(r.arabic, isNotEmpty);
      expect(r.allKnown, isFalse);
      expect(r.unknown, 2);
      expect(r.tokens, 2);
    });

    test('rule fallback produces readable latin for cluster words', () {
      // আব্দুল-ধাঁচের যুক্তবর্ণ — নিয়ম থেকেই পড়া যায় এমন ফল
      final r = NameTransliterator.transliterate('শুভ্র');
      expect(r.english, 'shuvr');
      // CLDR: ভ → به, হসন্ত বাদ → শ+ু+ভ+্+র = ش+و+به+ر (পুরনো হাতের ম্যাপে ছিল ڤ)
      // প্রত্যাশা \u escape-এ — এনকোডিং-দুর্ঘটনায় টেস্টটি নিজেই ভাঙবে না।
      expect(r.arabic, '\u0634\u0648\u0628\u0647\u0631');
    });

    test('empty input returns empty result', () {
      final r = NameTransliterator.transliterate('   ');
      expect(r.isEmpty, isTrue);
      expect(r.english, '');
      expect(r.arabic, '');
    });

    test('single person auto-fill text: father/mother style', () {
      final r = NameTransliterator.transliterate('মৃত আব্দুল হক');
      expect(r.english, 'Late Abdul Haque');
      expect(r.allKnown, isTrue);
    });

    // --- রিগ্রেশন (২০২৬-০৯-১৮ ফিক্স) -------------------------------------
    // normalizeYaRa-এর লিটারেলগুলো ৮-বিট ম anglিং-এ নষ্ট হয়ে (empty pattern +
    // U+009C/9D/81/8C/8D কন্ট্রোল ক্যারেক্টার) নরমালাইজেশন পুরোপুরি বন্ধ ছিল,
    // আর ফাংশনটি কোথাও কলও হত না → ডেটাসেটের ৮৮৩/৪২৩৮ নামে En/Ar ঘরে কাঁচা
    // বাংলা অক্ষর ফাঁস করত।

    test('normalizeYaRa: precomposed য়/ড়/ঢ় -> decomposed, no injection',
        () {
      const input = '\u09DF\u09DC\u09DD'; // precomposed য় ড় ঢ়
      final out = NameTransliterator.normalizeYaRa(input);
      expect(out, '\u09AF\u09BC\u09A1\u09BC\u09A2\u09BC');
      expect(out.length, 6); // আগের বাগে প্রতি অক্ষরের মাঝে 'য়' বসত
      expect(NameTransliterator.normalizeYaRa('রহিম'), 'রহিম');
    });

    test('normalizeYaRa: chandrabindu -> anusvara, ZWJ/ZWNJ stripped', () {
      expect(NameTransliterator.normalizeYaRa('\u0981'), '\u0982');
      expect(NameTransliterator.normalizeYaRa('র\u200Dাসেল'), 'রাসেল');
      expect(NameTransliterator.normalizeYaRa('র\u200Cাসেল'), 'রাসেল');
    });

    test('precomposed ড় token: dictionary hit + no Bengali leak', () {
      // 'গ\u09DCাই' (precomposed) ও 'গ\u09A1\u09BCাই' (decomposed) একই ফলা পাবে
      final pre = NameTransliterator.transliterate('মোঃ গ\u09DCাই হোসেন');
      final dec = NameTransliterator.transliterate('মোঃ গ\u09A1\u09BCাই হোসেন');
      expect(pre.english, dec.english);
      expect(pre.english, 'Md. garai Hossain'); // নিয়ম-ফলব্যাক (ডিকশনারিতে নেই)
      expect(pre.arabic, dec.arabic);
      expect(NameTransliterator.containsBengali(pre.english), isFalse);
      expect(NameTransliterator.containsBengali(pre.arabic), isFalse);
      expect(pre.tokens, 3);
      expect(pre.unknown, 1);
    });

    test('chandrabindu name: no raw Bengali leaks into En/Ar', () {
      final r = NameTransliterator.transliterate('চ\u0981দ মিয়া');
      expect(NameTransliterator.containsBengali(r.english), isFalse);
      expect(NameTransliterator.containsBengali(r.arabic), isFalse);
      expect(r.english, 'changd Miah'); // ঁ -> ং -> 'ng' (নিয়ম) + no raw leak
    });

    test('stray marks (ZWJ/ZWNJ/hasanta/nukta) never reach the output', () {
      for (final name in <String>[
        'র\u200Dাসেল',
        'র\u200Cাসেল',
        'আ\u09BCখি',
        'ম\u09CDম',
      ]) {
        final r = NameTransliterator.transliterate(name);
        expect(NameTransliterator.containsBengali(r.english), isFalse,
            reason: 'EN leaked for $name');
        expect(NameTransliterator.containsBengali(r.arabic), isFalse,
            reason: 'AR leaked for $name');
      }
    });

    test('cacheKey: script variants of the same name collapse', () {
      expect(
        NameTransliterator.cacheKey('গ\u09DCাই'),
        NameTransliterator.cacheKey('গ\u09A1\u09BCাই'),
      );
      expect(
        NameTransliterator.cacheKey('র\u200Dাসেল'),
        NameTransliterator.cacheKey('রাসেল'),
      );
    });

    test('dataset sweep: bundled names never leak Bengali into En/Ar', () {
      final raw = File('assets/Data_basic.json').readAsStringSync();
      final list = json.decode(raw) as List<dynamic>;
      var names = 0;
      var leaked = 0;
      for (final e in list) {
        final map = e as Map<String, dynamic>;
        final name = (map['STU_NAME'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        names++;
        final r = NameTransliterator.transliterate(name);
        if (NameTransliterator.containsBengali(r.english) ||
            NameTransliterator.containsBengali(r.arabic)) {
          leaked++;
        }
      }
      expect(names, greaterThan(4000));
      expect(leaked, 0); // ফিক্সের আগে ছিল ৮৮৩
    });

    // --- CLDR/ICU আরবী পোর্ট — গোল্ডেন টেস্ট (২০২৬-০৯-১৯) ------------------
    // সূত্র: icu4c/source/data/translit/{Bengali_InterIndic,InterIndic_Arabic}.txt

    test('CLDR Bengali_InterIndic: table integrity + key pairs', () {
      expect(BengaliInterIndic.tableSize, greaterThan(80));
      expect(BengaliInterIndic.mapsTo(0x0995, 0xE015), isTrue); // ক
      expect(BengaliInterIndic.mapsTo(0x09AD, 0xE02D), isTrue); // ভ
      expect(BengaliInterIndic.mapsTo(0x09CD, 0xE04D), isTrue); // ্
      expect(BengaliInterIndic.mapsTo(0x09B0, 0xE030), isTrue); // র
    });

    test('CLDR InterIndic_Arabic: consonants / anusvara / ই context / alif collapse',
        () {
      // ক→ك গ→ج প→ব (পুরনো হাতের ম্যাপে گ/پ — উর্দু-ঘেঁষা; CLDR নিকটতম আরবী)
      expect(InterIndicArabic.transliterate('ক'), '\u0643');
      expect(InterIndicArabic.transliterate('গ'), '\u062C');
      expect(InterIndicArabic.transliterate('প'), '\u0628');
      // চাঁদ → (নরমালাইজ ঁ→ং) → চ(tsh)=ت+ش +া=ا + ং=ن + দ=د = تشاند
      expect(InterIndicArabic.transliterate('চাঁদ'), '\u062A\u0634\u0627\u0646\u062F');
      // শব্দের শুরুতে ই → إ, শব্দ-মধ্যে → ي
      expect(InterIndicArabic.transliterate('ইদ'), '\u0625\u062F');
      expect(InterIndicArabic.transliterate('কাই'), '\u0643\u0627\u064A');
      // ICU ($alif) $alif+ → $1 — একাধিক alif সংকুচিত
      expect(InterIndicArabic.transliterate('আআ'), '\u0627\u0653');
      // private-use (InterIndic) অক্ষর কখনো আউটপুটে ফাঁস করতে পারে না
      final out = InterIndicArabic.transliterate('শুভ্র জগদীশ');
      expect(out.runes.any((c) => c >= 0xE000 && c <= 0xE0FF), isFalse);
      expect(NameTransliterator.containsBengali(out), isFalse);
    });

    test('CLDR end-to-end: unknown name gets standard Arabic, zero leak', () {
      final r = NameTransliterator.transliterate('জগদীশ চন্দ্র');
      expect(NameTransliterator.containsBengali(r.arabic), isFalse);
      expect(r.arabic, isNotEmpty);
      // জগদীশ = জ(ج) গ(ج) দ(د) ী(ي) শ(ش) — CLDR-মতে দুটোই ج (আরবীতে g নেই)
      expect(r.arabic, startsWith('\u062C\u062C\u062F'));
    });
    // --- টপ-unknown ডিকশনারি সম্প্রসারণ (২০২৬-০৯-১৯) -------------------------
    // Data_basic.json স্ক্যান: শুরুতে ১৩৩৯ distinct / ৩১৮৪ occurrence unknown;
    // তিন ধাপে dict+alias যোগের পরে ১০০২ distinct / ১১৯৯ occurrence (−৬২%)।
    test('top-unknown tokens are now dictionary-known', () {
      const added = [
        'মোহাম্মাদ', 'মুহাম্মাদ', 'আবির', 'নাহিদ', 'ইয়ামিন', 'খাংন',
        'সামিউল', 'হামিম', 'হুরায়রা', 'রাহাত', 'আরিফুল', 'নোমান',
        'জায়েদ', 'আলিফ', 'মুস্তাকিম', 'ইবনে', 'রাইয়ান', 'লাবিব',
        'সাকিব', 'সাজ্জাদ', 'তাহসিন', 'শাহরিয়ার', 'আনাস', 'সাদ',
        'আবরার', 'নিরব', 'আশরাফুল', 'জামিল', 'আহসান', 'সুফিয়ান',
        'আদনান', 'মুরসালিন', 'উসামা', 'ফয়সাল', 'রিয়াদ', 'মিনহাজ',
        'শুয়াইব', 'মুজাহিদ', 'মুয়াজ', 'রাকিব', 'জিসান', 'ইমন',
        'ইমাম', 'হাসিব', 'আতাউল্লাহ', 'ইয়াকুব', 'সোহান', 'সুলাইমান',
        'শিহাব', 'তাওহিদ', 'মুশফিকুর', 'হাবিব', 'কাওসার', 'ওয়ালিদ',
        'রহমাতুল্লাহ', 'ফারহান', 'এনামুল', 'খলিল', 'হযরত', 'মাহবুব',
        'রমজান', 'হানজালা', 'গনি', 'হানিফ', 'সৈয়দ', 'দেওয়ান',
        'ইসরাফিল', 'পারভেজ', 'সাইফ', 'ইসহাক', 'জাওয়াদ', 'মিরাজুল',
        'রিদওয়ান', 'শাকিব', 'তানজিম', 'আশরাফ', 'তাহের', 'মুসা',
        'আহনাফ', 'মুবিন', 'গালিব', 'সাইদুর', 'ফজলুল', 'মুহিব্বুল্লাহ',
        'তারেক', 'খাইরুল', 'আসিফ', 'সাগর', 'আতিকুর', 'সালিম',
        'হামিদুল', 'খালেদ', 'সাফওয়ান', 'রনি', 'তাসকিন', 'সাবিত',
        'নবী', 'আকন্দ', 'জামান', 'মিসবাহ', 'রিয়ান', 'হাকিম',
        'জহিরুল', 'রাতুল', 'হামিদ', 'আসাদ', 'ভূইয়া', 'আলভী',
        'রাইসুল', 'মাজহারুল', 'শাওন', 'সিদ্দিকী', 'এমদাদুল', 'কামরুল',
        'শামীম', 'আহমাদুল্লাহ', 'মুহাম্মাদুল্লাহ', 'আসাদুল্লাহ',
        'জিহাদুল', 'তাওহিদুল', 'মুজাহিদুল', 'সাকিবুল', 'হাসিবুল',
        'আশিকুর', 'রিয়াজুল', 'সাজিদুর', 'সাজিদ',
        // খণ্ড ২ (রিস্ক্যানের বাকি টপ-টোকেন)
        'বাইজিদ', 'আরিয়ান', 'তামজিদ', 'মাহফুজ', 'নাবিল', 'মন্ডল',
        'রিয়াজ', 'সালাউদ্দিন', 'দাউদ', 'জয়', 'সাখাওয়াত', 'আকাশ',
        'সজীব', 'বাশার', 'ইকরাম', 'মোস্তাফিজুর', 'সালেহ', 'আমার',
        'ফুয়াদ', 'আসলাম', 'হৃদয়', 'সাদিক', 'মুতাসিম', 'ইয়াসির',
        'সরকার', 'মিনহাজুল', 'মাহাবুব', 'আয়ান', 'এহসান', 'সৌরভ',
        'আমান', 'মমিন', 'তাহা', 'সাদ্দাম', 'ফরিদ', 'নেয়ামতুল্লাহ',
        'উবাইদা', 'ব্যাপারী', 'আবেদীন', 'শাকিল', 'মুহসিন', 'নাহিদুল',
        'নাফিস', 'মঈন',
      ];
      for (final t in added) {
        expect(NameTransliterator.isKnownToken(t), isTrue, reason: t);
      }
      // অ্যালিয়াস-শৃঙ্খল: রূপভেদগুলো মূল টোকেনে পৌঁছায়
      const variants = [
        'মোহা:', 'আবদুল্লাহ', 'আহম্মাদ', 'সেখ', 'ত্বলহা', 'শামিম',
        'ছিদ্দিক', 'বায়েজিদ', 'হুরাইরা', 'মুরছালিন', 'মোস্তাকিম',
        'ছামিউল', 'সাহাদাত', 'মাসউদ', 'সায়েম', 'মাহাদী', 'জুনায়েত',
        'নাইম', 'গণি', 'সাঈদ', 'হাফিজ', 'তামীম', 'উসমান', 'মুছা',
        'মুহা', 'মোহাঃ', 'তলহা', 'ফারসী', 'কাজি', 'মুস্তাফিজুর',
        'তারিকুল', 'নূরুল', 'বক্কার', 'আছাদ', 'হুজায়ফা', 'সজিব',
        'লাবীব', 'ভুইয়া', 'মণ্ডল', 'ত্বহা', 'বায়জিদ',
      ];
      for (final t in variants) {
        expect(NameTransliterator.isKnownToken(t), isTrue, reason: t);
      }
      // ইচ্ছাকৃতভাবে dict-বাইরে রাখা (নাম নয়) — অজানা হিসেবেই থাকবে
      for (final t in const ['কে', 'খা']) {
        expect(NameTransliterator.isKnownToken(t), isFalse, reason: t);
      }
    });

    test('new dict entries translate end-to-end, zero leak', () {
      final r = NameTransliterator.transliterate('মোহাম্মাদ আবির');
      expect(r.english, contains('Mohammad'));
      expect(r.english, contains('Abir'));
      expect(r.arabic, contains('محمد'));
      expect(NameTransliterator.containsBengali(r.english), isFalse);
      expect(NameTransliterator.containsBengali(r.arabic), isFalse);

      final r2 = NameTransliterator.transliterate('মুহাম্মাদ রাইয়ান');
      expect(r2.english, contains('Mohammad'));
      expect(r2.english, contains('Rayan'));
      expect(r2.arabic, contains('ريان'));
      expect(NameTransliterator.containsBengali(r2.arabic), isFalse);
    });

  });
}
