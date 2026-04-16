import 'package:flutter/material.dart';

class TradeCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const TradeCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final aptName = _get('아파트명') ?? _get('aptNm') ?? '-';
    final dong = _get('법정동') ?? _get('umdNm') ?? '';
    final area = _get('전용면적(㎡)') ?? _get('excluUseAr') ?? '';
    final floor = _get('층') ?? _get('floor') ?? '';
    final year = _get('년') ?? _get('dealYear') ?? '';
    final month = _get('월') ?? _get('dealMonth') ?? '';
    final day = _get('일') ?? _get('dealDay') ?? '';
    final buildYear = _get('건축년도') ?? _get('buildYear') ?? '';
    final tradeType = _get('_trade_type') ?? '';
    final regionName = _get('_region_name') ?? '';

    final isRent = tradeType.contains('전월세');

    String priceText;
    if (isRent) {
      final deposit = _get('보증금(만원)') ?? _get('deposit') ?? '-';
      final monthly = _get('월세(만원)') ?? _get('monthlyRent') ?? '0';
      priceText = monthly == '0'
          ? '전세 ${_formatPrice(deposit)}'
          : '보증금 ${_formatPrice(deposit)} / 월세 ${_formatPrice(monthly)}';
    } else {
      final price = _get('거래금액(만원)') ?? _get('dealAmount') ?? '-';
      priceText = _formatPrice(price);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 4),
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 아파트명 + 지역명
            Row(
              children: [
                Expanded(
                  child: Text(
                    aptName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (regionName.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tradeType,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // 가격
            Text(
              priceText,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 10),

            // 상세 정보 그리드
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _infoChip(Icons.location_on_outlined, dong),
                _infoChip(Icons.square_foot, '$area㎡'),
                _infoChip(Icons.layers_outlined, '$floor층'),
                _infoChip(Icons.calendar_today_outlined, '$year.$month.$day'),
                if (buildYear.isNotEmpty)
                  _infoChip(Icons.home_outlined, '${buildYear}년 건축'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _get(String key) {
    final val = data[key];
    if (val == null) return null;
    final str = val.toString().trim();
    return str.isEmpty ? null : str;
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      ],
    );
  }

  String _formatPrice(String raw) {
    final cleaned = raw.replaceAll(',', '').trim();
    final num = int.tryParse(cleaned);
    if (num == null) return raw;

    if (num >= 10000) {
      final억 = num ~/ 10000;
      final 만 = num % 10000;
      if (만 > 0) {
        return '$억억 ${_numberFormat(만)}만원';
      }
      return '$억억원';
    }
    return '${_numberFormat(num)}만원';
  }

  String _numberFormat(int n) {
    return n.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
}
