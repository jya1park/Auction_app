import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../widgets/trade_card.dart';

class TradeScreen extends StatefulWidget {
  const TradeScreen({super.key});

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  final FirestoreService _service = FirestoreService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _trades = [];
  bool _isLoading = false;
  String _selectedType = '';

  final List<String> _tradeTypes = [
    '', '아파트매매', '아파트전월세', '오피스텔매매', '오피스텔전월세',
    '연립다세대매매', '연립다세대전월세', '단독다가구매매', '단독다가구전월세',
  ];

  @override
  void initState() {
    super.initState();
    _loadTrades();
  }

  Future<void> _loadTrades() async {
    setState(() => _isLoading = true);
    try {
      final data = await _service.getTrades(
        tradeType: _selectedType.isNotEmpty ? _selectedType : null,
      );
      setState(() => _trades = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로드 실패: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _search() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      _loadTrades();
      return;
    }

    setState(() => _isLoading = true);
    try {
      final data = await _service.searchTrades(keyword);
      setState(() => _trades = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('검색 실패: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실거래가'),
      ),
      body: Column(
        children: [
          // 검색바
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '아파트명, 지역명 검색',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _loadTrades();
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),

          // 거래유형 필터 칩
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _tradeTypes.map((type) {
                final label = type.isEmpty ? '전체' : type;
                final isSelected = _selectedType == type;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(label, style: const TextStyle(fontSize: 13)),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _selectedType = type);
                      _loadTrades();
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // 결과 수
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_trades.length}건',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          // 리스트
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _trades.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('데이터가 없습니다',
                                style: TextStyle(color: Colors.grey, fontSize: 16)),
                            SizedBox(height: 4),
                            Text('PC에서 upload.py로 데이터를 업로드하세요',
                                style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTrades,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _trades.length,
                          itemBuilder: (context, index) {
                            return TradeCard(data: _trades[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
