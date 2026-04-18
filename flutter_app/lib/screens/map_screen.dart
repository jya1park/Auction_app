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
  bool _showOngoing = true;
  bool _showSold = true;
  bool _showUnsold = true;

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
      ..setBackgroundColor(const Color(0xFFEEEEEE))
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (message) {
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            final event = data['__event'];
            if (event == 'map_ready') {
              debugPrint('[카카오맵] 지도 준비 완료');
              _mapReady = true;
              _sendDataToMap();
              return;
            }
            if (event == 'debug') {
              debugPrint('[WebView] ${data['msg']}');
              return;
            }
            // 마커 클릭
            _showDetail(data);
          } catch (e) {
            debugPrint('[WebView] 메시지 처리 실패: $e');
          }
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          debugPrint('[WebView] 페이지 로드 완료: $url');
        },
        onWebResourceError: (err) {
          debugPrint('[WebView] 에러: ${err.errorCode} ${err.description}');
        },
      ));

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
      debugPrint('[Firestore] ${items.length}건 로드됨');
      if (items.isNotEmpty) {
        debugPrint('[Firestore] 첫 항목 샘플: ${items.first.keys.join(", ")}');
      }
      setState(() {
        _items = items;
        _isLoading = false;
      });
      _sendDataToMap();
    } catch (e, stack) {
      debugPrint('[Firestore] 로드 실패: $e\n$stack');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로드 실패: $e')),
        );
      }
    }
  }

  void _sendDataToMap() {
    if (!_mapReady) {
      debugPrint('[지도] 아직 준비 안 됨, 대기 중');
      return;
    }
    if (_items.isEmpty) {
      debugPrint('[지도] 데이터 없음 (Firestore에 map_items가 비어 있거나 좌표가 0)');
      return;
    }
    debugPrint('[지도] ${_items.length}건 마커 전송');
    final json = jsonEncode(_items);
    final escaped = json.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    _webController.runJavaScript("loadMarkers('$escaped')");
  }

  void _toggleFilter(String type, bool value) {
    if (type == 'ongoing') _showOngoing = value;
    if (type == 'sold') _showSold = value;
    if (type == 'unsold') _showUnsold = value;
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
    final ongoingCount = _items.where((i) => i['경매상태'] == '경매중').length;
    final soldCount = _items.where((i) => i['경매상태'] == '낙찰').length;
    final unsoldCount = _items.where((i) => i['경매상태'] == '유찰').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webController),

          if (_isLoading)
            const Center(child: CircularProgressIndicator()),

          // 필터: 매각 / 유찰
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
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        avatar: CircleAvatar(
                          backgroundColor: Colors.blue.shade600,
                          radius: 6,
                        ),
                        label: Text('경매중 $ongoingCount',
                            style: const TextStyle(fontSize: 12)),
                        selected: _showOngoing,
                        onSelected: (v) => _toggleFilter('ongoing', v),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        avatar: CircleAvatar(
                          backgroundColor: Colors.green.shade600,
                          radius: 6,
                        ),
                        label: Text('낙찰 $soldCount',
                            style: const TextStyle(fontSize: 12)),
                        selected: _showSold,
                        onSelected: (v) => _toggleFilter('sold', v),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        avatar: CircleAvatar(
                          backgroundColor: Colors.orange.shade600,
                          radius: 6,
                        ),
                        label: Text('유찰 $unsoldCount',
                            style: const TextStyle(fontSize: 12)),
                        selected: _showUnsold,
                        onSelected: (v) => _toggleFilter('unsold', v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
