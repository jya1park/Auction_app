import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/firestore_service.dart';
import '../widgets/detail_sheet.dart';

/// 카카오맵 WebView 기반 지도 화면
/// - 경매: 별 마커 (주황)
/// - 실거래가: 기본 마커 (파랑)
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final FirestoreService _service = FirestoreService();
  late final WebViewController _webController;

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  bool _mapReady = false;
  bool _showAuction = true;
  bool _showTrade = true;

  // .env에서 읽을 수도 있지만, 빌드 시 교체됨
  static const _kakaoJsKey = String.fromEnvironment(
    'KAKAO_JS_KEY',
    defaultValue: '614ddc420a052c47f1b0a7eb2169d862',
  );

  @override
  void initState() {
    super.initState();
    _initWebView();
    _loadData();
  }

  void _initWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (message) {
          // 마커 클릭 시 상세정보 표시
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            _showDetail(data);
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          _mapReady = true;
          _sendDataToMap();
        },
      ));

    // HTML 로드 (JS 키 삽입)
    _loadMapHtml();
  }

  Future<void> _loadMapHtml() async {
    final html = await rootBundle.loadString('assets/kakao_map.html');
    final injected = html.replaceAll('KAKAO_JS_KEY_PLACEHOLDER', _kakaoJsKey);
    _webController.loadHtmlString(injected);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final items = await _service.getMapItems(limit: 500);
      setState(() {
        _items = items;
        _isLoading = false;
      });
      _sendDataToMap();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로드 실패: $e')),
        );
      }
    }
  }

  void _sendDataToMap() {
    if (!_mapReady || _items.isEmpty) return;
    final json = jsonEncode(_items);
    // 작은따옴표 이스케이프
    final escaped = json.replaceAll("'", "\\'");
    _webController.runJavaScript("loadMarkers('$escaped')");
  }

  void _toggleFilter(String type, bool value) {
    if (type == 'auction') _showAuction = value;
    if (type == 'trade') _showTrade = value;
    setState(() {});
    _webController.runJavaScript("setFilter('$type', $value)");
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
          // 카카오맵 WebView
          WebViewWidget(controller: _webController),

          // 로딩
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),

          // 필터 칩 (상단)
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    FilterChip(
                      avatar: CircleAvatar(
                        backgroundColor: Colors.orange.shade600,
                        radius: 6,
                      ),
                      label: Text('경매 $auctionCount',
                          style: const TextStyle(fontSize: 13)),
                      selected: _showAuction,
                      onSelected: (v) => _toggleFilter('auction', v),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      avatar: CircleAvatar(
                        backgroundColor: Colors.blue.shade600,
                        radius: 6,
                      ),
                      label: Text('실거래가 $tradeCount',
                          style: const TextStyle(fontSize: 13)),
                      selected: _showTrade,
                      onSelected: (v) => _toggleFilter('trade', v),
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
}
