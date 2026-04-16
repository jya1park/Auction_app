import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../widgets/auction_card.dart';

class AuctionScreen extends StatefulWidget {
  const AuctionScreen({super.key});

  @override
  State<AuctionScreen> createState() => _AuctionScreenState();
}

class _AuctionScreenState extends State<AuctionScreen> {
  final FirestoreService _service = FirestoreService();

  List<Map<String, dynamic>> _auctions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAuctions();
  }

  Future<void> _loadAuctions() async {
    setState(() => _isLoading = true);
    try {
      final data = await _service.getAuctions();
      setState(() => _auctions = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('경매 데이터 로드 실패: $e')),
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
        title: const Text('경매'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _auctions.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.gavel_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('경매 데이터가 없습니다',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                      SizedBox(height: 4),
                      Text('PC에서 upload.py auction으로 데이터를 업로드하세요',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAuctions,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _auctions.length,
                    itemBuilder: (context, index) {
                      return AuctionCard(data: _auctions[index]);
                    },
                  ),
                ),
    );
  }
}
