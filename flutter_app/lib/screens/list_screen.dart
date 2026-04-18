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

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  String _filter = 'all'; // all, ongoing, sold, unsold, has_trade

  @override
  void initState() {
    super.initState();
    _load();
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
    switch (_filter) {
      case 'ongoing':
        return _items.where((i) => i['경매상태'] == '경매중').toList();
      case 'sold':
        return _items.where((i) => i['경매상태'] == '낙찰').toList();
      case 'unsold':
        return _items.where((i) => i['경매상태'] == '유찰').toList();
      case 'has_trade':
        return _items.where((i) {
          final list = i['실거래가목록'];
          return list is List && list.isNotEmpty;
        }).toList();
      default:
        return _items;
    }
  }

  @override
  Widget build(BuildContext context) {
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
          const Text('해당 조건의 데이터가 없습니다',
              style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('PC에서 python upload_csv.py 로 데이터를 업로드하세요',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}
