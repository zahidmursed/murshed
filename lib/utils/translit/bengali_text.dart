/// বাংলা টেক্সট-ইউটিলিটি — ট্রান্সলিটারেশন ও নরমালাইজেশনের **একক সত্য-উৎস**।
///
/// ফিক্স-ইতিহাস: আগে এই লজিক `NameTransliterator.normalizeYaRa`-এ ছিল এবং
/// লিটারেলগুলো ৮-বিট ম anglিং-এ নষ্ট হয়ে (empty pattern + U+009C/9D/81/8C/8D)
/// পুরো নরমালাইজেশন নিষ্ক্রিয় করে দিয়েছিল → ৪২৩৮ নামের ৮৮৩টিতে En/Ar ঘরে
/// কাঁচা বাংলা ফাঁস করত। তাই এখানে **সব অক্ষর `\u` escape-এ** লেখা — ভবিষ্যতে
/// যেকোনো এনকোডিং-দুর্ঘটনায়ও কোড অটুট থাকবে।
class BengaliText {
  BengaliText._();

  /// precomposed → decomposed + অদৃশ্য জোড়ক বাদ + চন্দ্রবিন্দু → অনুস্বার।
  /// CLDR/ICU-ও ট্রান্সলিটারেশনের আগে ঠিক এই কাজটাই করে (`::NFD`)।
  static String normalize(String s) => s
      .replaceAll('\u09DF', '\u09AF\u09BC') // ় → য + ়
      .replaceAll('\u09DC', '\u09A1\u09BC') // ড় → ড + ়
      .replaceAll('\u09DD', '\u09A2\u09BC') // ঢ় → ঢ + ়
      .replaceAll('\u0981', '\u0982') // ঁ → 
      .replaceAll('\u200D', '') // ZWJ
      .replaceAll('\u200C', ''); // ZWNJ

  /// স্ট্রিং-এ বাংলা বর্ণ আছে কি না — ইংরেজি/আরবী ঘরে বাংলা ফাঁস শনাক্ত করতে।
  static bool containsBengali(String s) =>
      s.runes.any((c) => c >= 0x0980 && c <= 0x09FF);

  /// মাত্রা/চিহ্ন যেগুলোর কোনো En/Ar ম্যাপ নেই — নিয়ম-আউটপুটে ফাঁস করা চলবে না।
  static const Set<String> unmappedMarks = {
    '\u0981', // ঁ (নরমালাইজেশনের পর সাধারণত থাকে না)
    '\u09BC', //  একা পড়া নুকতা
    '\u09BD', // ঽ
    '\u09CD', // ্ এলোমেলো হসন্ত
    '\u09D7', // 
    '\u09E2',
    '\u09E3',
    '\u200C',
    '\u200D',
  };

  static bool isUnmappedMark(String ch) => unmappedMarks.contains(ch);
}