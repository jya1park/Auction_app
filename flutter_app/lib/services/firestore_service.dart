import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 실거래가 데이터 조회
  /// [regionCode] 법정동코드, [tradeType] 거래유형 (옵션)
  Future<List<Map<String, dynamic>>> getTrades({
    String? regionCode,
    String? tradeType,
    int limit = 100,
  }) async {
    Query query = _db.collection('trades');

    if (regionCode != null && regionCode.isNotEmpty) {
      query = query.where('_region_code', isEqualTo: regionCode);
    }
    if (tradeType != null && tradeType.isNotEmpty) {
      query = query.where('_trade_type', isEqualTo: tradeType);
    }

    query = query.orderBy('_uploaded_at', descending: true).limit(limit);

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id}).toList();
  }

  /// 실거래가 검색 (아파트명 기준)
  Future<List<Map<String, dynamic>>> searchTrades(String keyword) async {
    // Firestore는 full-text search를 지원하지 않으므로
    // 전체 조회 후 클라이언트에서 필터링
    final snapshot = await _db
        .collection('trades')
        .orderBy('_uploaded_at', descending: true)
        .limit(500)
        .get();

    final lowerKeyword = keyword.toLowerCase();
    return snapshot.docs
        .map((doc) => {...doc.data(), 'id': doc.id})
        .where((item) {
          final aptName = (item['아파트명'] ?? item['aptNm'] ?? '').toString().toLowerCase();
          final dong = (item['법정동'] ?? item['umdNm'] ?? '').toString().toLowerCase();
          final region = (item['_region_name'] ?? '').toString().toLowerCase();
          return aptName.contains(lowerKeyword) ||
              dong.contains(lowerKeyword) ||
              region.contains(lowerKeyword);
        })
        .toList();
  }

  /// 경매 데이터 조회
  Future<List<Map<String, dynamic>>> getAuctions({
    String? court,
    String? usage,
    int limit = 100,
  }) async {
    Query query = _db.collection('auctions');

    if (court != null && court.isNotEmpty) {
      query = query.where('_court', isEqualTo: court);
    }
    if (usage != null && usage.isNotEmpty) {
      query = query.where('_usage', isEqualTo: usage);
    }

    query = query.orderBy('_uploaded_at', descending: true).limit(limit);

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id}).toList();
  }

  /// 업로드 로그 조회
  Future<List<Map<String, dynamic>>> getUploadLog({int limit = 20}) async {
    final snapshot = await _db
        .collection('upload_log')
        .orderBy('uploaded_at', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  /// 실거래가 실시간 스트림
  Stream<QuerySnapshot> tradesStream({String? regionCode, int limit = 50}) {
    Query query = _db.collection('trades');
    if (regionCode != null) {
      query = query.where('_region_code', isEqualTo: regionCode);
    }
    return query.orderBy('_uploaded_at', descending: true).limit(limit).snapshots();
  }

  /// 경매 실시간 스트림
  Stream<QuerySnapshot> auctionsStream({int limit = 50}) {
    return _db
        .collection('auctions')
        .orderBy('_uploaded_at', descending: true)
        .limit(limit)
        .snapshots();
  }
}
