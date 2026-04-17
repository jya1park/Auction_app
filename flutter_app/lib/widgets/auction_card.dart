import 'package:flutter/material.dart';

class AuctionCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const AuctionCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final aptName = (data['아파트명'] ?? '').toString();
    final dongName = (data['동명'] ?? '').toString();
    final caseNo = data['사건번호']?.toString() ?? '-';
    final location = (data['주소'] ?? data['소재지'] ?? '-').toString();
    final itemType = (data['용도'] ?? data['물건종류'] ?? '-').toString();
    final appraisalRaw = data['감정가'];
    final saleAmountRaw = data['매각금액'];
    final saleDate = data['매각기일']?.toString() ?? '-';
    final saleResult = (data['매각결과'] ?? '').toString();
    final discountRatio = data['할인율'];
    final tradeGroups = (data['실거래가목록'] is List)
        ? (data['실거래가목록'] as List)
        : <dynamic>[];

    final isSold = saleResult == '매각';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: Colors.amber.shade700, width: 4),
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 아파트명 + 결과 배지
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        aptName.isNotEmpty ? aptName : caseNo,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      if (dongName.isNotEmpty)
                        Text(dongName,
                            style: TextStyle(
                                fontSize: 12, color: colorScheme.outline)),
                    ],
                  ),
                ),
                if (saleResult.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: isSold ? Colors.green.shade100 : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      saleResult,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSold ? Colors.green.shade900 : Colors.orange.shade900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // 소재지
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on, size: 14, color: colorScheme.outline),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(location,
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 경매 금액 (감정가 vs 매각금액)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.gavel, size: 14, color: Colors.amber.shade900),
                      const SizedBox(width: 4),
                      Text('경매 정보',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.amber.shade900)),
                      const Spacer(),
                      if (discountRatio is num && discountRatio > 0)
                        Text('낙찰률 ${discountRatio.toStringAsFixed(1)}%',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _miniPrice('감정가', _formatWon(appraisalRaw),
                            colorScheme.outline),
                      ),
                      Expanded(
                        child: _miniPrice(
                          isSold ? '매각금액' : '최저매각가',
                          saleAmountRaw is num && saleAmountRaw > 0
                              ? _formatWon(saleAmountRaw)
                              : '-',
                          colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('매각기일: $saleDate · $itemType',
                      style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                ],
              ),
            ),

            // 실거래가 섹션 (있을 때만)
            if (tradeGroups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timeline,
                            size: 14, color: Colors.blue.shade900),
                        const SizedBox(width: 4),
                        Text('실거래가 (최근 6개월)',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.blue.shade900)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ..._buildTradeGroups(tradeGroups, colorScheme),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniPrice(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: valueColor)),
      ],
    );
  }

  List<Widget> _buildTradeGroups(List<dynamic> groups, ColorScheme cs) {
    final widgets = <Widget>[];
    for (final g in groups) {
      final group = g as Map<dynamic, dynamic>;
      final area = (group['전용면적'] ?? '').toString();
      final trades = (group['최근거래'] is List)
          ? group['최근거래'] as List<dynamic>
          : <dynamic>[];
      if (trades.isEmpty) continue;

      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(
          area.isNotEmpty ? '${area}㎡' : '거래내역',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: cs.outline),
        ),
      ));

      for (var i = 0; i < trades.length; i++) {
        final t = trades[i] as Map<dynamic, dynamic>;
        final price = (t['거래금액'] ?? '').toString();
        final y = t['년'] ?? '';
        final m = t['월'] ?? '';
        final floor = (t['층'] ?? '').toString();
        final isLatest = i == 0;
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 50,
                child: Text('$y.$m',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: isLatest ? FontWeight.w700 : FontWeight.w400,
                        color: cs.outline)),
              ),
              Expanded(
                child: Text(_formatWon10k(price),
                    style: TextStyle(
                        fontSize: isLatest ? 14 : 13,
                        fontWeight: FontWeight.w700,
                        color: isLatest ? Colors.blue.shade800 : cs.onSurface)),
              ),
              if (floor.isNotEmpty)
                Text('${floor}층',
                    style: TextStyle(fontSize: 10, color: cs.outline)),
            ],
          ),
        ));
      }
    }
    return widgets;
  }

  // 원 단위 → 억/만원
  String _formatWon(dynamic raw) {
    if (raw == null) return '-';
    final n = raw is num
        ? raw
        : (int.tryParse(raw.toString().replaceAll(',', '').trim()) ?? 0);
    if (n == 0) return '-';
    if (n >= 100000000) {
      final eok = n ~/ 100000000;
      final man = (n % 100000000) ~/ 10000;
      return man > 0
          ? '$eok억${man.toString().replaceAllMapped(RegExp(r"(\d)(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}'
          : '$eok억';
    } else if (n >= 10000) {
      return '${(n ~/ 10000).toString().replaceAllMapped(RegExp(r"(\d)(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}만';
    }
    return '$n원';
  }

  // 만원 단위 → 억/만원 (실거래가 API는 만원 단위)
  String _formatWon10k(String raw) {
    final n = int.tryParse(raw.replaceAll(',', '').trim()) ?? 0;
    if (n == 0) return '-';
    if (n >= 10000) {
      final eok = n ~/ 10000;
      final man = n % 10000;
      return man > 0
          ? '$eok억${man.toString().replaceAllMapped(RegExp(r"(\d)(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}만원'
          : '$eok억원';
    }
    return '${n.toString().replaceAllMapped(RegExp(r"(\d)(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}만원';
  }
}
