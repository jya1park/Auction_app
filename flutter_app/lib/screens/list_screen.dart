import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../widgets/trade_card.dart';
import '../widgets/auction_card.dart';

class ListScreen extends StatefulWidget {
  const ListScreen({super.key});

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreService _service = FirestoreService();

  List<Map<String, dynamic>> _auctions = [];
  List<Map<String, dynamic>> _trades = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _service.getAuctions(),
        _service.getTrades(),
      ]);
      setState(() {
        _auctions = results[0];
        _trades = results[1];
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('목록'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '경매 (${_auctions.length})'),
            Tab(text: '실거래가 (${_trades.length})'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // 경매 탭
                _auctions.isEmpty
                    ? _emptyState('경매 데이터가 없습니다')
                    : RefreshIndicator(
                        onRefresh: _loadAll,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _auctions.length,
                          itemBuilder: (_, i) => AuctionCard(data: _auctions[i]),
                        ),
                      ),
                // 실거래가 탭
                _trades.isEmpty
                    ? _emptyState('실거래가 데이터가 없습니다')
                    : RefreshIndicator(
                        onRefresh: _loadAll,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _trades.length,
                          itemBuilder: (_, i) => TradeCard(data: _trades[i]),
                        ),
                      ),
              ],
            ),
    );
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('PC에서 upload.py run으로 데이터를 업로드하세요',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
