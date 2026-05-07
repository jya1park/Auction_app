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
  String _lastUpdate = '';
  List<Map<String, dynamic>> _todayNewSold = [];
  bool _showNewBanner = true;

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
      String latest = '';
      for (final item in items) {
        final uploaded = (item['_uploaded_at'] ?? '').toString();
        if (uploaded.isNotEmpty && uploaded.compareTo(latest) > 0) {
          latest = uploaded;
        }
      }
      if (latest.length >= 10) latest = latest.substring(0, 10);

      final today = DateTime.now().toIso8601String().substring(0, 10);
      final newSold = items.where((i) =>
          i['경매상태'] == '낙찰' &&
          (i['_uploaded_at'] ?? '').toString().startsWith(today)
      ).toList();

      setState(() {
        _items = items;
        _lastUpdate = latest;
        _todayNewSold = newSold;
        _showNewBanner = newSold.isNotEmpty;
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Map', style: TextStyle(fontSize: 18)),
            if (_lastUpdate.isNotEmpty)
              Text('업데이트: $_lastUpdate',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
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

          // 당일 신규 낙찰 배너
          if (_showNewBanner && _todayNewSold.isNotEmpty)
            Positioned(
              top: 72,
              left: 12,
              right: 12,
              child: GestureDetector(
                onTap: () {
                  setState(() => _showNewBanner = false);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => _buildNewSoldSheet(),
                  );
                },
                child: Card(
                  elevation: 2,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.notification_important, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '오늘 신규 낙찰 ${_todayNewSold.length}건',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _showNewBanner = false),
                          child: const Icon(Icons.close, size: 18),
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

  Widget _buildNewSoldSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.7,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('오늘 신규 낙찰 ${_todayNewSold.length}건',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _todayNewSold.length,
                  itemBuilder: (_, i) {
                    final item = _todayNewSold[i];
                    final name = item['아파트명'] ?? item['사건번호'] ?? '-';
                    final addr = item['주소'] ?? item['소재지'] ?? '';
                    final amount = item['매각금액'];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.shade100,
                        radius: 16,
                        child: Icon(Icons.gavel, size: 16, color: Colors.green.shade900),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(addr, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: amount is num && amount > 0
                          ? Text(_formatWonShort(amount),
                              style: TextStyle(fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.error))
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        _showDetail(item);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatWonShort(num n) {
    if (n >= 100000000) {
      final eok = (n / 100000000).toStringAsFixed(1);
      return '$eok억';
    } else if (n >= 10000) {
      return '${(n / 10000).round()}만';
    }
    return '$n';
  }
}
