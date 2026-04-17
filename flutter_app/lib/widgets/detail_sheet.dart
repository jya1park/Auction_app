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
    final aptName = (data['아파트명'] ?? '').toString();
    final dongName = (data['동명'] ?? '').toString();
    final address = (data['주소'] ?? data['소재지'] ?? '-').toString();
    final usage = (data['용도'] ?? data['물건종류'] ?? '-').toString();
    final court = (data['법원'] ?? '').toString();
    final area = data['전용면적'];
    final appraisal = data['감정가'] ?? 0;
    final saleAmount = data['매각금액'] ?? 0;
    final saleResult = (data['매각결과'] ?? '-').toString();
    final discountRatio = data['할인율'];
    final saleDate = (data['매각기일'] ?? '-').toString();
    final note = (data['비고'] ?? '').toString();

    final isSold = saleResult == '매각';

    return [
      _title(aptName.isNotEmpty ? aptName : (data['사건번호'] ?? '-').toString()),
      if (dongName.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(dongName, style: TextStyle(fontSize: 14, color: cs.outline)),
      ],
      const SizedBox(height: 12),

      // 매각 결과 배지
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isSold ? Colors.green.shade100 : Colors.orange.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              saleResult,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isSold ? Colors.green.shade900 : Colors.orange.shade900,
              ),
            ),
          ),
          if (discountRatio != null && discountRatio is num && discountRatio > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '낙찰률 ${discountRatio.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),

      // 금액 카드 (감정가 vs 매각금액)
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
                    Text(_formatWon(appraisal),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: cs.outlineVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isSold ? '매각금액' : '최저매각가',
                        style: TextStyle(fontSize: 12, color: cs.outline)),
                    const SizedBox(height: 4),
                    Text(
                      saleAmount is num && saleAmount > 0
                          ? _formatWon(saleAmount)
                          : '-',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: cs.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      _infoTile(Icons.gavel, '사건번호', data['사건번호']?.toString() ?? '-'),
      _infoTile(Icons.location_on, '소재지', address),
      _infoTile(Icons.category, '용도', usage),
      if (area != null && area is num && area > 0)
        _infoTile(Icons.square_foot, '전용면적', '${area}㎡'),
      if (court.isNotEmpty) _infoTile(Icons.account_balance, '법원', court),
      _infoTile(Icons.event, '매각기일', saleDate),
      if (note.isNotEmpty) _infoTile(Icons.info_outline, '비고', note),
    ];
  }

  String _formatWon(dynamic raw) {
    if (raw == null) return '-';
    num n;
    if (raw is num) {
      n = raw;
    } else {
      final parsed = int.tryParse(raw.toString().replaceAll(',', '').trim());
      if (parsed == null) return raw.toString();
      n = parsed;
    }
    if (n == 0) return '-';
    // 원 단위 → 억/만원 단위 변환
    if (n >= 100000000) {
      final 억 = n ~/ 100000000;
      final 만 = (n % 100000000) ~/ 10000;
      return 만 > 0 ? '$억억 ${_numberFormat(만.toInt())}만원' : '$억억원';
    } else if (n >= 10000) {
      return '${_numberFormat((n ~/ 10000).toInt())}만원';
    }
    return '${_numberFormat(n.toInt())}원';
  }

  String _numberFormat(int n) {
    return n.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
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
