import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/firestore_service.dart';
import '../widgets/detail_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final FirestoreService _service = FirestoreService();
  GoogleMapController? _mapController;

  Set<Marker> _markers = {};
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  // 필터
  bool _showAuction = true;
  bool _showTrade = true;

  // 기본 위치: 서울 중심
  static const _defaultCenter = LatLng(37.5665, 126.9780);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final items = await _service.getMapItems(limit: 500);
      setState(() {
        _items = items;
        _buildMarkers();
        _isLoading = false;
      });

      // 데이터가 있으면 첫 번째 항목 위치로 이동
      if (items.isNotEmpty && _mapController != null) {
        final first = items.firstWhere(
          (i) => i['lat'] != null && i['lat'] != 0.0,
          orElse: () => items.first,
        );
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(
              (first['lat'] as num).toDouble(),
              (first['lng'] as num).toDouble(),
            ),
            13,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로드 실패: $e')),
        );
      }
    }
  }

  void _buildMarkers() {
    final markers = <Marker>{};

    for (final item in _items) {
      final type = item['_type'] ?? '';
      if (type == 'auction' && !_showAuction) continue;
      if (type == 'trade' && !_showTrade) continue;

      final lat = item['lat'];
      final lng = item['lng'];
      if (lat == null || lng == null || lat == 0.0 || lng == 0.0) continue;

      final isAuction = type == 'auction';
      final id = item['id'] ?? '${lat}_$lng';

      String title;
      String snippet;

      if (isAuction) {
        title = '🔨 ${item['사건번호'] ?? '경매'}';
        snippet = '최저가: ${item['최저매각가'] ?? '-'}';
      } else {
        final aptName = item['아파트명'] ?? item['aptNm'] ?? '-';
        final price = item['거래금액(만원)'] ?? item['dealAmount'] ?? '-';
        title = '📊 $aptName';
        snippet = '${_formatPrice(price.toString())}';
      }

      markers.add(Marker(
        markerId: MarkerId(id),
        position: LatLng(
          (lat as num).toDouble(),
          (lng as num).toDouble(),
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isAuction
              ? BitmapDescriptor.hueOrange
              : BitmapDescriptor.hueAzure,
        ),
        infoWindow: InfoWindow(
          title: title,
          snippet: snippet,
          onTap: () => _showDetail(item),
        ),
        onTap: () => _showDetail(item),
      ));
    }

    setState(() => _markers = markers);
  }

  void _showDetail(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DetailSheet(data: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final auctionCount = _items.where((i) => i['_type'] == 'auction').length;
    final tradeCount = _items.where((i) => i['_type'] == 'trade').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('부동산 지도'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 지도
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _defaultCenter,
              zoom: 12,
            ),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
            },
          ),

          // 로딩 인디케이터
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),

          // 필터 + 범례 (상단)
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    // 경매 필터
                    FilterChip(
                      avatar: const CircleAvatar(
                        backgroundColor: Colors.orange,
                        radius: 6,
                      ),
                      label: Text('경매 $auctionCount건',
                          style: const TextStyle(fontSize: 13)),
                      selected: _showAuction,
                      onSelected: (v) {
                        setState(() => _showAuction = v);
                        _buildMarkers();
                      },
                    ),
                    const SizedBox(width: 8),
                    // 실거래가 필터
                    FilterChip(
                      avatar: const CircleAvatar(
                        backgroundColor: Colors.blue,
                        radius: 6,
                      ),
                      label: Text('실거래가 $tradeCount건',
                          style: const TextStyle(fontSize: 13)),
                      selected: _showTrade,
                      onSelected: (v) {
                        setState(() => _showTrade = v);
                        _buildMarkers();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(String raw) {
    final cleaned = raw.replaceAll(',', '').trim();
    final n = int.tryParse(cleaned);
    if (n == null) return raw;
    if (n >= 10000) {
      final 억 = n ~/ 10000;
      final 만 = n % 10000;
      return 만 > 0 ? '$억억 $만만원' : '$억억원';
    }
    return '$n만원';
  }
}
