import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../screens/tax_chat_screen.dart';
import '../services/openai_service.dart';
import '../services/naver_search_service.dart';

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
      const SizedBox(height: 12),

      // 실거래가 섹션 (있으면)
      ..._buildEmbeddedTrades(cs),

      const SizedBox(height: 8),
      _infoTile(Icons.gavel, '사건번호', data['사건번호']?.toString() ?? '-'),
      _infoTile(Icons.location_on, '소재지', address),
      _infoTile(Icons.category, '용도', usage),
      if (area != null && area is num && area > 0)
        _infoTile(Icons.square_foot, '전용면적', '${area}㎡'),
      if (court.isNotEmpty) _infoTile(Icons.account_balance, '법원', court),
      _infoTile(Icons.event, '매각기일', saleDate),
      if (note.isNotEmpty) _infoTile(Icons.info_outline, '비고', note),

      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Builder(
              builder: (ctx) => ElevatedButton.icon(
                onPressed: () => _openCourtAuction(ctx),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('경매정보 보기'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Builder(
              builder: (ctx) => ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => TaxChatScreen(property: data),
                    ),
                  );
                },
                icon: const Icon(Icons.support_agent, size: 18),
                label: const Text('세금 상담'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Builder(
        builder: (ctx) => SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => _PropertyAnalysisScreen(property: data),
                ),
              );
            },
            icon: const Icon(Icons.analytics_outlined, size: 18),
            label: const Text('단지 분석 (장점/단점)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildEmbeddedTrades(ColorScheme cs) {
    final raw = data['실거래가목록'];
    if (raw is! List || raw.isEmpty) return const [];

    final widgets = <Widget>[];
    widgets.add(Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, size: 16, color: Colors.blue.shade900),
                const SizedBox(width: 6),
                Text('이 아파트 실거래가 (최근 6개월)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.blue.shade900)),
              ],
            ),
            const SizedBox(height: 10),
            ..._buildEmbeddedTradeRows(raw, cs),
          ],
        ),
      ),
    ));
    return widgets;
  }

  List<Widget> _buildEmbeddedTradeRows(List<dynamic> groups, ColorScheme cs) {
    final widgets = <Widget>[];
    for (final g in groups) {
      final group = g as Map<dynamic, dynamic>;
      final area = (group['전용면적'] ?? '').toString();
      final count = group['거래건수_6개월'] ?? 0;
      final trades = (group['최근거래'] is List)
          ? group['최근거래'] as List<dynamic>
          : <dynamic>[];
      if (trades.isEmpty) continue;

      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Row(
          children: [
            Text(area.isNotEmpty ? '${area}㎡' : '거래내역',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: cs.outline)),
            const SizedBox(width: 6),
            Text('· $count건',
                style: TextStyle(fontSize: 11, color: cs.outline)),
          ],
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
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Container(
                width: 50,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: isLatest ? Colors.blue.shade700 : Colors.white,
                  border: Border.all(color: Colors.blue.shade200),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$y.$m',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isLatest ? Colors.white : Colors.blue.shade900)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_formatPrice(price),
                    style: TextStyle(
                        fontSize: isLatest ? 16 : 14,
                        fontWeight: FontWeight.w800,
                        color: isLatest ? Colors.blue.shade900 : cs.onSurface)),
              ),
              if (floor.isNotEmpty)
                Text('${floor}층',
                    style: TextStyle(fontSize: 11, color: cs.outline)),
            ],
          ),
        ));
      }
    }
    return widgets;
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
      final eok = n ~/ 100000000;
      final man = (n % 100000000) ~/ 10000;
      return man > 0
          ? '$eok억 ${_numberFormat(man.toInt())}만원'
          : '$eok억원';
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
    final buildYear = data['건축년도'] ?? data['buildYear'] ?? '';
    final regionName = data['_region_name'] ?? '';
    final tradeCount = data['거래건수_6개월'];
    final recentRaw = data['최근거래'];
    final recentTrades = (recentRaw is List) ? recentRaw : <dynamic>[];

    return [
      _title(aptName),
      const SizedBox(height: 4),
      Text(regionName, style: TextStyle(fontSize: 14, color: cs.outline)),
      const SizedBox(height: 12),

      if (tradeCount != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '최근 6개월 $tradeCount건 거래',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSecondaryContainer,
            ),
          ),
        ),
      const SizedBox(height: 12),

      // 최근 거래 3건
      if (recentTrades.isNotEmpty)
        Card(
          color: cs.primaryContainer.withAlpha(60),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('최근 거래 (최대 3건)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.outline)),
                const SizedBox(height: 10),
                ..._buildRecentTradeRows(recentTrades, cs),
              ],
            ),
          ),
        )
      else
        // 구버전 호환: 최근거래 배열이 없으면 단건 표시
        Card(
          color: cs.primaryContainer.withAlpha(80),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                _formatPrice((data['거래금액(만원)'] ?? data['dealAmount'] ?? '-')
                    .toString()),
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
      _infoTile(Icons.location_on, '법정동', dong.toString()),
      if (area.toString().isNotEmpty)
        _infoTile(Icons.square_foot, '전용면적', '$area㎡'),
      if (buildYear.toString().isNotEmpty)
        _infoTile(Icons.home, '건축년도', '$buildYear년'),
    ];
  }

  List<Widget> _buildRecentTradeRows(List<dynamic> recentTrades, ColorScheme cs) {
    final rows = <Widget>[];
    for (var i = 0; i < recentTrades.length; i++) {
      final t = recentTrades[i] as Map<dynamic, dynamic>;
      final price = (t['거래금액'] ?? '').toString();
      final y = t['년'] ?? '';
      final m = t['월'] ?? '';
      final floor = (t['층'] ?? '').toString();
      final isLatest = i == 0;

      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: isLatest ? cs.primary : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$y.$m',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isLatest ? cs.onPrimary : cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _formatPrice(price),
                style: TextStyle(
                  fontSize: isLatest ? 17 : 15,
                  fontWeight: FontWeight.w800,
                  color: isLatest ? cs.error : cs.onSurface,
                ),
              ),
            ),
            if (floor.isNotEmpty)
              Text('${floor}층',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
          ],
        ),
      ));
    }
    return rows;
  }

  void _openCourtAuction(BuildContext context) {
    final caseNo = (data['사건번호'] ?? '').toString().trim();
    if (caseNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사건번호 정보가 없습니다.')),
      );
      return;
    }

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CourtAuctionScreen(
          caseNo: caseNo,
          court: (data['법원'] ?? '').toString().trim(),
        ),
      ),
    );
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
      final eok = n ~/ 10000;
      final man = n % 10000;
      return man > 0 ? '$eok억 $man만원' : '$eok억원';
    }
    return '$n만원';
  }
}

class _PropertyAnalysisScreen extends StatefulWidget {
  final Map<String, dynamic> property;

  const _PropertyAnalysisScreen({required this.property});

  @override
  State<_PropertyAnalysisScreen> createState() =>
      _PropertyAnalysisScreenState();
}

class _PropertyAnalysisScreenState extends State<_PropertyAnalysisScreen> {
  String? _analysis;
  bool _loading = true;
  List<SearchResult> _sources = [];

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
  }

  Future<void> _loadAnalysis() async {
    final p = widget.property;
    final aptName = p['아파트명'] ?? '';
    final address = p['주소'] ?? p['소재지'] ?? '';
    final dong = p['동명'] ?? '';
    final usage = p['용도'] ?? p['물건종류'] ?? '';
    final area = p['전용면적'] ?? '';
    final structure = p['건물구조'] ?? '';
    final appraisal = p['감정가'];
    final saleAmount = p['매각금액'];
    final court = p['법원'] ?? '';
    final note = p['비고'] ?? '';

    // 실거래가 정보
    String tradeInfo = '';
    final tradeList = p['실거래가목록'];
    if (tradeList is List && tradeList.isNotEmpty) {
      for (final g in tradeList) {
        final gArea = g['전용면적'] ?? '';
        final trades = g['최근거래'];
        if (trades is List && trades.isNotEmpty) {
          final t = trades[0];
          tradeInfo += '${gArea}㎡ 최근거래: ${t['년']}.${t['월']} ${t['거래금액']}만원 ${t['층'] ?? ''}층\n';
        }
      }
    }

    final info = StringBuffer();
    info.writeln('물건: $aptName');
    info.writeln('주소: $address');
    if (dong.isNotEmpty) info.writeln('법정동: $dong');
    info.writeln('용도: $usage');
    if (area != null && area.toString().isNotEmpty) info.writeln('전용면적: ${area}㎡');
    if (structure.isNotEmpty) info.writeln('건물구조: $structure');
    if (appraisal != null) info.writeln('감정가: $appraisal원');
    if (saleAmount != null && saleAmount != 0) info.writeln('낙찰가: $saleAmount원');
    if (court.isNotEmpty) info.writeln('법원: $court');
    if (note.isNotEmpty) info.writeln('비고: $note');
    if (tradeInfo.isNotEmpty) info.writeln('실거래가:\n$tradeInfo');

    // 네이버 검색으로 실제 후기/하자/임장 정보 수집 + 본문 크롤링
    String searchResults = '';
    if (NaverSearchService.hasKeys && aptName.isNotEmpty) {
      if (mounted) setState(() { _analysis = '🔍 네이버에서 후기 검색 중...'; });
      try {
        final reviewResults = await NaverSearchService.searchResults('$aptName 후기 거주 장단점', display: 4);
        if (mounted) setState(() { _analysis = '🔍 하자/시공 정보 검색 중...'; });
        final defectResults = await NaverSearchService.searchResults('$aptName 하자 시공 결로 누수', display: 3);
        if (mounted) setState(() { _analysis = '🔍 임장 후기 검색 중...'; });
        final visitResults = await NaverSearchService.searchResults('$aptName 임장 후기 현장 방문', display: 3);
        _sources = [...reviewResults, ...defectResults, ...visitResults];

        // 블로그 본문 크롤링
        if (mounted) setState(() { _analysis = '📄 블로그 본문 수집 중 (${_sources.length}건)...'; });
        await NaverSearchService.fetchBodies(_sources, maxChars: 800);

        for (final r in reviewResults) {
          final content = r.body.isNotEmpty ? r.body : r.description;
          searchResults += '### ${r.title}\n$content\n\n';
        }
        for (final r in defectResults) {
          final content = r.body.isNotEmpty ? r.body : r.description;
          searchResults += '### ${r.title}\n$content\n\n';
        }
        for (final r in visitResults) {
          final content = r.body.isNotEmpty ? r.body : r.description;
          searchResults += '### ${r.title}\n$content\n\n';
        }
      } catch (_) {}
      if (mounted) setState(() { _analysis = '🤖 AI 분석 중...'; });
    }

    final prompt = '''아래 아파트의 실제 거주 관점 분석을 해줘.

${info.toString()}
${searchResults.isNotEmpty ? '## 웹 검색 결과 (실제 후기 기반으로 분석할 것)\n$searchResults' : ''}
분석 기준:
- 교통 (지하철/버스 접근성, 주요 도심 출퇴근)
- 학군 (초중고 배정, 학원가)
- 생활편의 (마트, 병원, 공원, 상가)
- 단지환경 (동간 거리, 주차, 소음, 채광, 조경)
- 건물상태 (건축년도 추정, 구조, 리모델링/재건축 여부)
- 시공/하자 (시공사 평판, 알려진 하자 이력, 결로/누수/균열 등 공통 하자, 하자보수 이력)

형식:

👍 긍정적 피드백
1. [교통/학군/편의/단지/건물/시공 중 택1] 구체적 내용
2. ...
3. ...
4. ...
5. ...

👎 부정적 피드백
1. [교통/학군/편의/단지/건물/시공 중 택1] 구체적 내용
2. ...
3. ...
4. ...
5. ...

각 항목은 한 줄로 간결하게. 거주·시공·하자를 모두 포함. 해당 단지에 특화된 내용만. 모르는 정보는 '확인 필요'로 표기.''';

    try {
      final service = (await _getService());
      await for (final partial in service.sendMessageStream(prompt)) {
        if (!mounted) return;
        setState(() { _analysis = partial; });
      }
      setState(() { _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _analysis = '⚠️ 분석 실패: $e'; _loading = false; });
    }
  }

  Future<OpenAIService> _getService() async {
    final service = OpenAIService();
    await service.loadKnowledgeBase();
    return service;
  }

  @override
  Widget build(BuildContext context) {
    final aptName = widget.property['아파트명'] ?? '물건';

    return Scaffold(
      appBar: AppBar(title: Text('$aptName 단지 분석')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_analysis != null && _analysis!.isNotEmpty)
              SelectableText(
                _analysis!,
                style: const TextStyle(fontSize: 15, height: 1.7),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('분석 중...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            if (!_loading && _sources.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '📎 분석 근거 (${_sources.length}건)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              ..._sources.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => launchUrl(
                      Uri.parse(s.link),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ',
                            style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                s.description,
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _CourtAuctionScreen extends StatefulWidget {
  final String caseNo;
  final String court;

  const _CourtAuctionScreen({required this.caseNo, this.court = ''});

  @override
  State<_CourtAuctionScreen> createState() => _CourtAuctionScreenState();
}

class _CourtAuctionScreenState extends State<_CourtAuctionScreen> {
  late final WebViewController _controller;
  bool _injected = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _injectCaseNumber(),
      ))
      ..loadRequest(Uri.parse(
          'https://www.courtauction.go.kr/pgj/index.on?w2xPath=/pgj/ui/pgj100/PGJ159M00.xml'));
  }

  Future<void> _injectCaseNumber() async {
    if (_injected) return;
    _injected = true;

    final caseNo = widget.caseNo;
    final court = widget.court;

    final yearMatch = RegExp(r'(\d{4})').firstMatch(caseNo);
    final numMatch = RegExp(r'[가-힣]+(\d+)').firstMatch(caseNo);
    final year = yearMatch?.group(1) ?? '';
    final num = numMatch?.group(1) ?? '';

    await Future.delayed(const Duration(milliseconds: 2000));

    await _controller.runJavaScript('''
      (function() {
        function setVal(el, val) {
          if (!el) return;
          el.value = val;
          el.dispatchEvent(new Event('input', {bubbles:true}));
          el.dispatchEvent(new Event('change', {bubbles:true}));
        }

        function selectByValue(sel, val) {
          if (!sel || !val) return false;
          for (var i = 0; i < sel.options.length; i++) {
            if (sel.options[i].value == val || sel.options[i].text.trim() == val) {
              sel.selectedIndex = i;
              sel.dispatchEvent(new Event('change', {bubbles:true}));
              return true;
            }
          }
          return false;
        }

        function selectByKeyword(sel, keyword) {
          if (!sel || !keyword) return false;
          for (var i = 0; i < sel.options.length; i++) {
            if (sel.options[i].text.indexOf(keyword) >= 0) {
              sel.selectedIndex = i;
              sel.dispatchEvent(new Event('change', {bubbles:true}));
              return true;
            }
          }
          return false;
        }

        var selects = document.querySelectorAll('select');

        // 1. 법원 선택
        var court = '$court';
        if (court) {
          var courtKeyword = court.replace('지방법원', '').replace('지원', '').trim();
          for (var i = 0; i < selects.length; i++) {
            if (selectByKeyword(selects[i], courtKeyword)) break;
          }
        }

        // 2. 년도 셀렉트박스에서 선택
        var year = '$year';
        if (year) {
          for (var i = 0; i < selects.length; i++) {
            if (selectByValue(selects[i], year)) break;
          }
        }

        // 3. 사건번호(타경 뒤 숫자만) 입력칸에 입력
        var caseNum = '$num';
        var inputs = document.querySelectorAll('input[type="text"], input[type="number"], input:not([type])');
        var filled = false;
        for (var i = 0; i < inputs.length; i++) {
          var inp = inputs[i];
          if (inp.offsetParent === null) continue;
          var name = (inp.name || '').toLowerCase();
          var id = (inp.id || '').toLowerCase();
          var ph = (inp.placeholder || '');

          if (name.indexOf('no') >= 0 || name.indexOf('num') >= 0 ||
              id.indexOf('no') >= 0 || id.indexOf('num') >= 0 ||
              ph.indexOf('번호') >= 0 || ph.indexOf('호') >= 0) {
            setVal(inp, caseNum);
            filled = true;
            break;
          }
        }
        if (!filled) {
          for (var i = 0; i < inputs.length; i++) {
            if (inputs[i].value === '' && inputs[i].offsetParent !== null) {
              setVal(inputs[i], caseNum);
              break;
            }
          }
        }

        // 4. 검색 버튼 자동 클릭
        setTimeout(function() {
          var btns = document.querySelectorAll('button, input[type="submit"], input[type="button"], a, span');
          for (var i = 0; i < btns.length; i++) {
            var txt = (btns[i].textContent || btns[i].value || '').trim();
            if (txt === '검색' || txt === '조회' || txt === '찾기') {
              btns[i].click();
              return;
            }
          }
          var forms = document.querySelectorAll('form');
          if (forms.length > 0) forms[0].submit();
        }, 500);
      })();
    ''');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('경매정보 ${widget.caseNo}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '브라우저에서 열기',
            onPressed: () => launchUrl(
              Uri.parse(
                  'https://www.courtauction.go.kr/pgj/index.on?w2xPath=/pgj/ui/pgj100/PGJ159M00.xml'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
