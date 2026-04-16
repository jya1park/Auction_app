import 'package:flutter/material.dart';

/// 마커 탭 시 하단에서 올라오는 상세정보 시트
class DetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;

  const DetailSheet({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAuction = data['_type'] == 'auction';

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: ListView(
            controller: scrollController,
            children: [
              // 핸들
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 타입 배지
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isAuction
                          ? Colors.orange.shade100
                          : Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isAuction ? '🔨 경매' : '📊 실거래가',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isAuction
                            ? Colors.orange.shade900
                            : Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (isAuction) ..._buildAuctionDetail(colorScheme),
              if (!isAuction) ..._buildTradeDetail(colorScheme),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildAuctionDetail(ColorScheme cs) {
    return [
      _title(data['사건번호'] ?? '-'),
      const SizedBox(height: 12),
      _infoTile(Icons.location_on, '소재지', data['소재지'] ?? '-'),
      _infoTile(Icons.category, '물건종류', data['물건종류'] ?? '-'),
      const SizedBox(height: 12),

      // 금액 카드
      Card(
        color: cs.errorContainer.withAlpha(60),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('감정가', style: TextStyle(fontSize: 12, color: cs.outline)),
                    const SizedBox(height: 4),
                    Text(data['감정가'] ?? '-',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: cs.outlineVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('최저매각가',
                        style: TextStyle(fontSize: 12, color: cs.outline)),
                    const SizedBox(height: 4),
                    Text(data['최저매각가'] ?? '-',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: cs.error,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      _infoTile(Icons.event, '매각기일', data['매각기일'] ?? '-'),
      _infoTile(Icons.info_outline, '상태', data['상태'] ?? '-'),
    ];
  }

  List<Widget> _buildTradeDetail(ColorScheme cs) {
    final aptName = data['아파트명'] ?? data['aptNm'] ?? '-';
    final dong = data['법정동'] ?? data['umdNm'] ?? '';
    final area = data['전용면적(㎡)'] ?? data['excluUseAr'] ?? '';
    final floor = data['층'] ?? data['floor'] ?? '';
    final year = data['년'] ?? data['dealYear'] ?? '';
    final month = data['월'] ?? data['dealMonth'] ?? '';
    final day = data['일'] ?? data['dealDay'] ?? '';
    final buildYear = data['건축년도'] ?? data['buildYear'] ?? '';
    final regionName = data['_region_name'] ?? '';
    final price = data['거래금액(만원)'] ?? data['dealAmount'] ?? '-';

    return [
      _title(aptName),
      const SizedBox(height: 4),
      Text(regionName,
          style: TextStyle(fontSize: 14, color: cs.outline)),
      const SizedBox(height: 16),

      // 금액 카드
      Card(
        color: cs.primaryContainer.withAlpha(80),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              _formatPrice(price.toString()),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: cs.error,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _infoTile(Icons.location_on, '법정동', dong),
      _infoTile(Icons.square_foot, '전용면적', '$area㎡'),
      _infoTile(Icons.layers, '층', '$floor층'),
      _infoTile(Icons.calendar_today, '거래일', '$year.$month.$day'),
      if (buildYear.toString().isNotEmpty)
        _infoTile(Icons.home, '건축년도', '$buildYear년'),
    ];
  }

  Widget _title(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
