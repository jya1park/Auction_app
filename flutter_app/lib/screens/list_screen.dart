import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../widgets/auction_card.dart';

class ListScreen extends StatefulWidget {
  const ListScreen({super.key});

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  final FirestoreService _service = FirestoreService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  String _filter = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final auctions = await _service.getAuctions(limit: 500);
      setState(() => _items = auctions);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로드 실패: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var result = _items;

    // 상태 필터
    switch (_filter) {
      case 'ongoing':
        result = result.where((i) => i['경매상태'] == '경매중').toList();
        break;
      case 'sold':
        result = result.where((i) => i['경매상태'] == '낙찰').toList();
        break;
      case 'unsold':
        result = result.where((i) => i['경매상태'] == '유찰').toList();
        break;
      case 'has_trade':
        result = result.where((i) {
          final list = i['실거래가목록'];
          return list is List && list.isNotEmpty;
        }).toList();
        break;
    }

    // 검색 필터
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((i) {
        final aptName = (i['아파트명'] ?? '').toString().toLowerCase();
        final address = (i['주소'] ?? i['소재지'] ?? '').toString().toLowerCase();
        final dong = (i['동명'] ?? '').toString().toLowerCase();
        final caseNo = (i['사건번호'] ?? '').toString().toLowerCase();
        return aptName.contains(q) ||
            address.contains(q) ||
            dong.contains(q) ||
            caseNo.contains(q);
      }).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('List'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // 검색바
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '아파트명, 주소, 사건번호 검색',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // 필터 칩
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('전체 (${_items.length})', 'all'),
                  const SizedBox(width: 6),
                  _filterChip(
                      '경매중 (${_items.where((i) => i['경매상태'] == '경매중').length})',
                      'ongoing'),
                  const SizedBox(width: 6),
                  _filterChip(
                      '낙찰 (${_items.where((i) => i['경매상태'] == '낙찰').length})',
                      'sold'),
                  const SizedBox(width: 6),
                  _filterChip(
                      '유찰 (${_items.where((i) => i['경매상태'] == '유찰').length})',
                      'unsold'),
                ],
              ),
            ),
          ),
          // 검색 결과 수
          if (_searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '검색 결과: ${filtered.length}건',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          // 목록
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) =>
                              AuctionCard(data: filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
              _searchQuery.isNotEmpty
                  ? '"$_searchQuery" 검색 결과가 없습니다'
                  : '해당 조건의 데이터가 없습니다',
              style: const TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }
}
