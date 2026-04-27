import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore Timestamp → 문자열 등 JSON 인코딩 가능한 값으로 변환
dynamic _sanitize(dynamic value) {
  if (value is Timestamp) {
    return value.toDate().toIso8601String();
  }
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), _sanitize(v)));
  }
  if (value is Iterable) {
    return value.map(_sanitize).toList();
  }
  return value;
}

Map<String, dynamic> _sanitizeDoc(Map<String, dynamic> data) {
  return data.map((k, v) => MapEntry(k, _sanitize(v)));
}

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 지도용 전체 데이터 조회 (경매 + 실거래가)
  /// 좌표가 있는 항목만 반환
  Future<List<Map<String, dynamic>>> getMapItems({int limit = 300}) async {
    final snapshot = await _db
        .collection('map_items')
        .orderBy('_uploaded_at', descending: true)
        .limit(limit)
        .get(const GetOptions(source: Source.server));

    return snapshot.docs
        .map((doc) => {..._sanitizeDoc(doc.data()), 'id': doc.id})
        .where((item) {
          final lat = item['lat'];
          final lng = item['lng'];
          return lat != null && lng != null && lat != 0.0 && lng != 0.0;
        })
        .toList();
  }

  /// 경매 데이터만 조회 (복합 인덱스 회피: 클라이언트에서 정렬)
  Future<List<Map<String, dynamic>>> getAuctions({int limit = 200}) async {
    final snapshot = await _db
        .collection('map_items')
        .where('_type', isEqualTo: 'auction')
        .limit(limit)
        .get(const GetOptions(source: Source.server));

    final items = snapshot.docs
        .map((doc) => {..._sanitizeDoc(doc.data()), 'id': doc.id})
        .toList();
    items.sort((a, b) {
      final at = (a['_uploaded_at'] ?? '').toString();
      final bt = (b['_uploaded_at'] ?? '').toString();
      return bt.compareTo(at);
    });
    return items;
  }

  /// 실거래가 데이터만 조회 (복합 인덱스 회피)
  Future<List<Map<String, dynamic>>> getTrades({int limit = 200}) async {
    final snapshot = await _db
        .collection('map_items')
        .where('_type', isEqualTo: 'trade')
        .limit(limit)
        .get();

    final items = snapshot.docs
        .map((doc) => {..._sanitizeDoc(doc.data()), 'id': doc.id})
        .toList();
    items.sort((a, b) {
      final at = (a['_uploaded_at'] ?? '').toString();
      final bt = (b['_uploaded_at'] ?? '').toString();
      return bt.compareTo(at);
    });
    return items;
  }

  /// 업로드 로그
  Future<List<Map<String, dynamic>>> getUploadLog({int limit = 20}) async {
    final snapshot = await _db
        .collection('upload_log')
        .orderBy('uploaded_at', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => _sanitizeDoc(doc.data())).toList();
  }
}
