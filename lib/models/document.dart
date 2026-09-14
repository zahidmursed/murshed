import 'student.dart';

// doc_type DB CHECK constraint-এ SCREAMING_CASE (PHOTO/BIRTH/FORM) — তাই নাম এভাবেই
// ignore_for_file: constant_identifier_names
enum DocType { PHOTO, BIRTH, FORM }

extension DocTypeLabel on DocType {
  String get label => switch (this) {
        DocType.PHOTO => 'ছবি',
        DocType.BIRTH => 'জন্মসনদ',
        DocType.FORM => 'আবেদন ফরম',
      };
}

/// documents টেবিলের একটি রো।
class StudentDocument {
  final int? id;
  final String dakhila;
  final DocType type;
  final String filePath;
  final String ext;
  final String? mimeType;
  final int? fileSize;
  final int status;
  final String? updatedAt;

  const StudentDocument({
    this.id,
    required this.dakhila,
    required this.type,
    required this.filePath,
    required this.ext,
    this.mimeType,
    this.fileSize,
    this.status = 1,
    this.updatedAt,
  });

  factory StudentDocument.fromRow(Map<String, dynamic> r) {
    return StudentDocument(
      id: r['id'] as int?,
      dakhila: (r['dakhila'] as String?) ?? '',
      type: DocType.values.firstWhere(
        (t) => t.name == (r['doc_type'] as String?),
        orElse: () => DocType.PHOTO,
      ),
      filePath: (r['file_path'] as String?) ?? '',
      ext: (r['file_ext'] as String?) ?? 'jpg',
      mimeType: r['mime_type'] as String?,
      fileSize: r['file_size'] as int?,
      status: (r['status'] as int?) ?? 1,
      updatedAt: r['updated_at'] as String?,
    );
  }

  /// INSERT/REPLACE-এর জন্য (id ছাড়া)।
  Map<String, dynamic> toRow() {
    return {
      'dakhila': dakhila,
      'doc_type': type.name,
      'file_path': filePath,
      'file_ext': ext,
      'mime_type': mimeType,
      'file_size': fileSize,
      'status': status,
      'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
    };
  }
}

/// ছাত্র + তার ডকুমেন্ট স্লট (PHOTO/BIRTH/FORM) — UI-র জন্য।
class StudentWithDocs {
  final Student student;
  final Map<DocType, StudentDocument?> docs;

  const StudentWithDocs({required this.student, required this.docs});

  int get completedCount => docs.values.where((d) => d != null).length;

  double get progress => completedCount / 3;

  bool hasDoc(DocType type) => docs[type] != null;
}

/// Bulk import: `281_BIRTH.pdf` নাম থেকে (দাখিলা, DocType) বের করে —
/// ফরম্যাট না মিললে null। হেডার কেস-ইনসেনসিটিভ।
(String, DocType)? parseBulkDocName(String fileName) {
  final m = RegExp(
    r'^(\d+)_(PHOTO|BIRTH|FORM)\.(jpe?g|png|pdf)$',
    caseSensitive: false,
  ).firstMatch(fileName.trim());
  if (m == null) return null;
  final type =
      DocType.values.firstWhere((t) => t.name == m.group(2)!.toUpperCase());
  return (m.group(1)!, type);
}
