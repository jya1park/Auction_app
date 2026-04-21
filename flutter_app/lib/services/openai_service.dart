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

    final data = await _callApi(routerMessages, withTools: false, maxTokens: 50);
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
    buffer.writeln('한국어로 답변. 금액은 만원/억원 단위. 계산 근거를 단계별로 설명하세요.');

    if (docContent != null) {
      buffer.writeln();
      buffer.writeln('## 참고 자료');
      if (docContent.length > 4000) {
        buffer.writeln(docContent.substring(0, 4000));
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
        buffer.writeln(
            '- 조정대상지역: ${_isPropertyRegulated! ? "해당" : "비해당"}');
        buffer.writeln(
            '계산기 호출 시 is_regulated_area=${_isPropertyRegulated!}로 설정하세요.');
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
      List<Map<String, dynamic>> messages,
      {bool withTools = true, int? maxTokens}) async {
    final payload = <String, dynamic>{
      'model': _model,
      'max_completion_tokens': maxTokens ?? _maxTokens,
      'messages': messages,
    };
    if (withTools) {
      payload['tools'] = TaxCalculator.toolDefinitions;
    }
    final body = json.encode(payload);

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

    // 1단계: LLM 라우터 - 질문에 맞는 문서 1개 선택
    String? docContent;
    try {
      final selectedFile = await _routeDocument(message);
      if (selectedFile != null) {
        docContent = _docCache[selectedFile];
      }
    } catch (_) {
      // 라우터 실패 시 문서 없이 진행
    }

    // 2단계: 선택된 문서로 시스템 프롬프트 구성
    final systemPrompt = _buildSystemPrompt(docContent);

    _history.add({'role': 'user', 'content': message});

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ..._history,
    ];

    try {
      // 3단계: 메인 API 호출 (tools 포함)
      var data = await _callApi(messages);
      final choices = data['choices'];
      if (choices == null || (choices as List).isEmpty) {
        _history.removeLast();
        return '⚠️ API 응답이 비어있습니다.';
      }

      var assistantMessage =
          (choices as List)[0]['message'] as Map<String, dynamic>;

      // 4단계: Function Calling 루프
      int rounds = 0;
      while (assistantMessage['tool_calls'] != null && rounds < 5) {
        rounds++;
        messages.add(Map<String, dynamic>.from(assistantMessage));

        final toolCalls = assistantMessage['tool_calls'] as List<dynamic>;
        for (final toolCall in toolCalls) {
          final fn = toolCall['function'] as Map<String, dynamic>;
          final fnName = fn['name'] as String;
          final fnArgs =
              json.decode(fn['arguments'] as String) as Map<String, dynamic>;
          final result = TaxCalculator.executeFunction(fnName, fnArgs);
          messages.add({
            'role': 'tool',
            'tool_call_id': toolCall['id'],
            'content': result,
          });
        }

        data = await _callApi(messages);
        assistantMessage =
            (data['choices'] as List)[0]['message'] as Map<String, dynamic>;
      }

      var text = (assistantMessage['content'] as String?) ?? '';

      // 5단계: 빈 응답 시 tools 없이 재시도
      if (text.isEmpty) {
        final retryMessages = <Map<String, dynamic>>[
          {'role': 'system', 'content': systemPrompt},
          ..._history,
        ];
        final retryData = await _callApi(retryMessages, withTools: false);
        final retryMsg = (retryData['choices'] as List)[0]['message']
            as Map<String, dynamic>;
        text = (retryMsg['content'] as String?) ?? '';
      }

      if (text.isEmpty) {
        _history.removeLast();
        return '⚠️ AI 응답이 비어있습니다. 질문을 짧게 다시 해주세요.';
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
