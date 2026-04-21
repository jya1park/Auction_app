import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'tax_calculator.dart';

class OpenAIService {
  static const _model = 'gpt-5-nano';
  static const _apiUrl = 'https://api.openai.com/v1/chat/completions';
  static const _maxTokens = 2048;

  static String get _apiKey => dotenv.env['OPENAI_API_KEY'] ?? '';

  final List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _propertyContext;

  Map<String, String> _docCache = {};
  List<String> _regulatedAreas = [];
  bool _loaded = false;
  bool? _isPropertyRegulated;

  static const _docDescriptions = {
    '01_취득세.md': '취득세 세율표, 다주택 중과, 경매 과세표준, 부가세, 인지세',
    '02_양도소득세.md': '양도소득세 세율, 장기보유공제, 비과세 요건, 경매 취득가액',
    '03_경매절차.md': '입찰·낙찰·잔금·등기·명도 절차, 권리분석, 배당순위',
    '04_주택임대차보호법.md': '대항력, 확정일자, 우선변제권, 소액임차인, 배당순위, 권리분석',
  };

  bool get hasApiKey => _apiKey.isNotEmpty;

  Future<void> loadKnowledgeBase() async {
    if (_loaded) return;

    for (final file in _docDescriptions.keys) {
      _docCache[file] =
          await rootBundle.loadString('assets/tax_knowledge/$file');
    }

    final regulatedJson = await rootBundle
        .loadString('assets/tax_knowledge/05_조정대상지역.json');
    final regulatedData = json.decode(regulatedJson) as Map<String, dynamic>;
    _regulatedAreas =
        (regulatedData['조정대상지역'] as List).cast<String>();

    _loaded = true;
  }

  bool _checkRegulatedArea(String? address) {
    if (address == null || address.isEmpty) return false;
    for (final area in _regulatedAreas) {
      if (address.contains(area)) return true;
      final parts = area.split(' ');
      if (parts.length >= 2) {
        final district = parts.last;
        if (address.contains(district) &&
            (address.contains(parts.first) ||
                address.contains(parts.first.replaceAll('특별시', '')))) {
          return true;
        }
      }
    }
    return false;
  }

  Future<String?> _routeDocument(String query) async {
    final docList = _docDescriptions.entries
        .map((e) => '- ${e.key}: ${e.value}')
        .join('\n');

    final routerMessages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            '사용자 질문에 가장 관련 있는 문서 파일명을 1개만 답하세요. 관련 없으면 "none"이라고 답하세요.\n\n문서 목록:\n$docList',
      },
      {'role': 'user', 'content': query},
    ];

    final data = await _callApi(routerMessages);
    final choices = data['choices'];
    if (choices == null || (choices as List).isEmpty) return null;

    final text =
        ((choices as List)[0]['message']['content'] as String?)?.trim() ?? '';

    for (final file in _docDescriptions.keys) {
      if (text.contains(file)) return file;
    }

    if (text.contains('01')) return '01_취득세.md';
    if (text.contains('02')) return '02_양도소득세.md';
    if (text.contains('03')) return '03_경매절차.md';
    if (text.contains('04')) return '04_주택임대차보호법.md';

    return null;
  }

  String _buildSystemPrompt(String? docContent) {
    final buffer = StringBuffer();

    buffer.writeln('당신은 한국 부동산 세금·경매 법률 전문 상담사입니다.');
    buffer.writeln('규칙: 한국어로 답변. 금액은 만원/억원 단위. 핵심만 간결하게 답변. 불필요한 설명이나 반복 금지. 계산 결과는 표 형태로 정리.');

    if (docContent != null) {
      buffer.writeln();
      buffer.writeln('## 참고 자료');
      if (docContent.length > 1500) {
        buffer.writeln(docContent.substring(0, 1500));
        buffer.writeln('...(이하 생략)');
      } else {
        buffer.writeln(docContent);
      }
    }

    if (_propertyContext != null) {
      buffer.writeln();
      buffer.writeln('## 상담 물건');
      final p = _propertyContext!;
      if (p['아파트명'] != null) buffer.writeln('- 물건명: ${p['아파트명']}');
      if (p['동명'] != null) buffer.writeln('- 동: ${p['동명']}');
      final address = (p['주소'] ?? p['소재지'])?.toString();
      if (address != null) buffer.writeln('- 주소: $address');
      final usage = p['용도'] ?? p['물건종류'];
      if (usage != null) buffer.writeln('- 용도: $usage');
      if (p['전용면적'] != null) buffer.writeln('- 전용면적: ${p['전용면적']}㎡');
      if (p['감정가'] != null) buffer.writeln('- 감정가: ${_formatWon(p['감정가'])}');
      if (p['매각금액'] != null) buffer.writeln('- 낙찰가: ${_formatWon(p['매각금액'])}');
      if (p['매각결과'] != null) buffer.writeln('- 매각결과: ${p['매각결과']}');
      if (p['사건번호'] != null) buffer.writeln('- 사건번호: ${p['사건번호']}');

      if (_isPropertyRegulated != null) {
        final reg = _isPropertyRegulated!;
        buffer.writeln('- 조정대상지역: ${reg ? "✅ 해당" : "❌ 비해당"}');
        if (reg) {
          buffer.writeln('  → 취득세: 2주택 8%, 3주택 12%');
          buffer.writeln('  → 양도세: 2주택 기본+20%p, 3주택 기본+30%p');
          buffer.writeln('  → 장기보유특별공제: 중과 시 적용 불가');
        } else {
          buffer.writeln('  → 취득세: 2주택 일반세율(1~3%), 3주택 8%');
          buffer.writeln('  → 양도세: 중과 미적용 (기본세율)');
        }
        buffer.writeln(
            '계산기 호출 시 is_regulated_area=$reg로 설정하세요.');
      }
    }

    return buffer.toString();
  }

  String _formatWon(dynamic value) {
    if (value == null) return '';
    final num amount;
    if (value is num) {
      amount = value;
    } else {
      amount = num.tryParse(value.toString().replaceAll(',', '')) ?? 0;
    }
    if (amount >= 100000000) {
      final eok = amount / 100000000;
      return '${eok.toStringAsFixed(eok.truncateToDouble() == eok ? 0 : 2)}억원';
    } else if (amount >= 10000) {
      return '${(amount / 10000).round()}만원';
    }
    return '${amount.round()}원';
  }

  Future<Map<String, dynamic>> _callApi(
      List<Map<String, dynamic>> messages) async {
    final body = json.encode({
      'model': _model,
      'messages': messages,
    });

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      final errorBody = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(
          'API 오류 (${response.statusCode}): ${errorBody['error']?['message'] ?? '알 수 없는 오류'}');
    }
  }

  Future<String> sendMessage(String message) async {
    if (!hasApiKey) {
      return '⚠️ API 키가 설정되지 않았습니다.\n\n'
          'flutter_app/.env 파일에 OPENAI_API_KEY=sk-... 를 입력해주세요.';
    }

    await loadKnowledgeBase();

    if (_propertyContext != null && _isPropertyRegulated == null) {
      final address =
          (_propertyContext!['주소'] ?? _propertyContext!['소재지'])?.toString();
      _isPropertyRegulated = _checkRegulatedArea(address);
    }

    _history.add({'role': 'user', 'content': message});

    // 시스템 프롬프트 (물건 정보 + 조정대상지역만, RAG 없음)
    final systemPrompt = _buildSystemPrompt(null);

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ..._history,
    ];

    try {
      final data = await _callApi(messages);
      final choices = data['choices'];
      if (choices == null || (choices as List).isEmpty) {
        _history.removeLast();
        return '⚠️ API 응답이 비어있습니다.\n\n$data';
      }

      final assistantMessage =
          (choices as List)[0]['message'] as Map<String, dynamic>;
      final text = (assistantMessage['content'] as String?) ?? '';

      if (text.isEmpty) {
        _history.removeLast();
        return '⚠️ AI 응답이 비어있습니다.\n\n전체: ${json.encode(data)}';
      }
      _history.add({'role': 'assistant', 'content': text});
      return text;
    } catch (e) {
      if (_history.isNotEmpty) _history.removeLast();
      return '⚠️ 오류 발생: $e';
    }
  }

  void setPropertyContext(Map<String, dynamic> property) {
    _propertyContext = property;
    final address =
        (property['주소'] ?? property['소재지'])?.toString();
    _isPropertyRegulated = _checkRegulatedArea(address);
  }

  void clearHistory() {
    _history.clear();
  }

  void clearAll() {
    _history.clear();
    _propertyContext = null;
    _isPropertyRegulated = null;
  }
}
