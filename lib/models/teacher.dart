/// শিক্ষক-তালিকার এন্ট্রি — ক্লাস (ঐচ্ছিক ফরিক) প্রতি দায়িত্বপ্রাপ্ত শিক্ষক।
/// উৎস: `assets/Negran_Teacher_Name.xlsx` (Sheet: "Teacher Name")।
class TeacherInfo {
  final String className; // নরমালাইজ-করা ক্লাসের নাম
  final String forik; // খালি = পুরো ক্লাসের জন্য (ফরিক-উদাসীন)
  final String nameBn; // বাংলা নাম
  final String nameEn; // ইংরেজি নাম
  final String mobile; // শুধু ডিজিট (১০ ডিজিট হলে আগে 0 বসানো)

  const TeacherInfo({
    required this.className,
    required this.forik,
    required this.nameBn,
    required this.nameEn,
    required this.mobile,
  });

  /// ডিসপ্লে-বান্ধব নাম — বাংলা প্রাধান্য, না থাকলে ইংরেজি।
  String get displayName => nameBn.isNotEmpty ? nameBn : nameEn;

  /// DB-র `teachers` টেবিল স্কিমা (class_name + forik = natural key)।
  Map<String, dynamic> toMap() => {
        'class_name': className,
        'forik': forik,
        'name_bn': nameBn,
        'name_en': nameEn,
        'mobile': mobile,
      };

  factory TeacherInfo.fromMap(Map<String, dynamic> m) => TeacherInfo(
        className: (m['class_name'] as String?) ?? '',
        forik: (m['forik'] as String?) ?? '',
        nameBn: (m['name_bn'] as String?) ?? '',
        nameEn: (m['name_en'] as String?) ?? '',
        mobile: (m['mobile'] as String?) ?? '',
      );
}
