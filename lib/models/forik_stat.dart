/// ফরিক-ভিত্তিক প্রগ্রেস স্ট্যাট (GROUP BY forik_no কোয়েরির ফলাফল)।
class ForikStat {
  final String forik;
  final int total;
  final int captured;

  const ForikStat({
    required this.forik,
    required this.total,
    required this.captured,
  });

  int get remaining => total - captured;

  bool get isComplete => total > 0 && captured >= total;

  factory ForikStat.fromRow(Map<String, dynamic> r) {
    return ForikStat(
      forik: (r['forik_no'] as String?) ?? '',
      total: (r['total'] as int?) ?? 0,
      captured: (r['captured'] as int?) ?? 0,
    );
  }
}
