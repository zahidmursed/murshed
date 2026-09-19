/// ছাত্র-প্রতি কেস নোট — DB-র `case_notes` টেবিল (স্তর: নোট সিস্টেম)।
/// দাখিলা-কী দিয়ে যুক্ত; JSON/Excel ইমপোর্ট বা ডাটা রিসেটে নোট হারায় না
/// (আলাদা টেবিল, students-এর সাথে delete হয় না)।
class CaseNote {
  final int? id;
  final String dakhila;
  final String noteDate; // ঘটনার তারিখ (DD-MM-YYYY)
  final String category; // শৃঙ্খলা / অনুপস্থিতি / মামলা / অন্যান্য
  final String title; // সংক্ষিপ্ত শিরোনাম
  final String details; // বিস্তারিত
  final String? createdAt; // ISO timestamp
  final String? updatedAt;

  const CaseNote({
    this.id,
    required this.dakhila,
    required this.noteDate,
    this.category = '',
    this.title = '',
    required this.details,
    this.createdAt,
    this.updatedAt,
  });

  factory CaseNote.fromRow(Map<String, dynamic> r) => CaseNote(
        id: r['id'] as int?,
        dakhila: (r['dakhila'] as String?) ?? '',
        noteDate: (r['note_date'] as String?) ?? '',
        category: (r['category'] as String?) ?? '',
        title: (r['title'] as String?) ?? '',
        details: (r['details'] as String?) ?? '',
        createdAt: r['created_at'] as String?,
        updatedAt: r['updated_at'] as String?,
      );

  /// INSERT OR REPLACE (id থাকলে সেই রো replace, না থাকলে নতুন)।
  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'dakhila': dakhila,
        'note_date': noteDate,
        'category': category,
        'title': title,
        'details': details,
        'created_at': createdAt ?? DateTime.now().toIso8601String(),
        'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
      };
}
