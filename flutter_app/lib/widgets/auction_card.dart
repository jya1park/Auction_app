import 'package:flutter/material.dart';

class AuctionCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const AuctionCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final caseNo = data['사건번호']?.toString() ?? '-';
    final location = data['소재지']?.toString() ?? '-';
    final itemType = data['물건종류']?.toString() ?? '-';
    final appraisal = data['감정가']?.toString() ?? '-';
    final minPrice = data['최저매각가']?.toString() ?? '-';
    final saleDate = data['매각기일']?.toString() ?? '-';
    final status = data['상태']?.toString() ?? '-';

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
            // 사건번호 + 상태
            Row(
              children: [
                Expanded(
                  child: Text(
                    caseNo,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.amber.shade900,
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
                Icon(Icons.location_on, size: 16, color: colorScheme.outline),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    location,
                    style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 물건종류
            Row(
              children: [
                Icon(Icons.category_outlined, size: 14, color: colorScheme.outline),
                const SizedBox(width: 4),
                Text(itemType, style: TextStyle(fontSize: 13, color: colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 10),

            // 금액 정보
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(80),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('감정가',
                            style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                        const SizedBox(height: 2),
                        Text(appraisal,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 30, color: colorScheme.outlineVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('최저매각가',
                            style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                        const SizedBox(height: 2),
                        Text(
                          minPrice,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 매각기일
            Row(
              children: [
                Icon(Icons.event_outlined, size: 14, color: colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  '매각기일: $saleDate',
                  style: TextStyle(fontSize: 13, color: colorScheme.outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
