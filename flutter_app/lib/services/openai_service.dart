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

  Map<String, List<String>> _keywordIndex = {};
  Map<String, String> _docCache = {};
  List<String> _regulatedAreas = [];
  bool _loaded = false;
  bool? _isPropertyRegulated;

  bool get hasApiKey => _apiKey.isNotEmpty;

  Future<void> loadKnowledgeBase() async {
    if (_loaded) return;

    final indexJson =
        await rootBundle.loadString('assets/tax_knowledge/00_index.json');
    final Map<String, dynamic> parsed = json.decode(indexJson);
    _keywordIndex = parsed.map(
      (key, value) => MapEntry(key, (value as List).cast<String>()),
    );

    final allFiles = <String>{};
    for (final files in _keywordIndex.values) {
      allFiles.addAll(files);
    }

    for (final file in allFiles) {
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

  List<String> _retrieveRelevantDocs(String query) {
    final matchedFiles = <String>{};

    for (final entry in _keywordIndex.entries) {
      if (query.contains(entry.key)) {
        matchedFiles.addAll(entry.value);
      }
    }

    if (matchedFiles.isEmpty) {
      return _docCache.values.toList();
    }

    return matchedFiles
        .map((f) => _docCache[f] ?? '')
        .where((d) => d.isNotEmpty)
        .toList();
  }

  String _buildSystemPrompt(List<String> docs) {
    final buffer = StringBuffer();

    buffer.writeln('당신은 한국 부동산 세금 전문가이자 경매 법률 상담사입니다.');
    buffer.writeln('주택임대차보호법, 권리분석, 대항력, 배당순위, 소액임차인 등 경매 관련 법률에 정통합니다.');
    buffer.writeln();
    buffer.writeln('## 규칙');
    buffer.writeln('- 항상 한국어로 응답하세요.');
    buffer.writeln('- 금액은 "만원" 또는 "억원" 단위로 읽기 쉽게 표시하세요.');
    buffer.writeln('- 세금 계산이 필요하면 반드시 제공된 계산기 함수를 호출하세요. 직접 계산하지 마세요.');
    buffer.writeln('- 계산기 결과의 breakdown을 활용하여 단계별 과정을 보여주세요.');
    buffer.writeln('- 각 세금 항목이 왜 그 금액인지 계산 로직을 설명하세요. (예: "낙찰가 9억은 6~9억 구간이므로 세율 (9×2/3-3)=3%")');
    buffer.writeln('- 적용된 세율, 공제, 과세표준 산출 근거를 함께 안내하세요.');
    buffer.writeln('- 가정이 필요한 경우 (주택 수 등) 명시적으로 안내하세요.');
    buffer.writeln('- 아래 제공된 세법 자료를 기반으로 정확하게 답변하세요.');
    buffer.writeln('- 확실하지 않은 내용은 전문가 상담을 권유하세요.');

    buffer.writeln();
    buffer.writeln('## 조정대상지역 (2025년 기준)');
    buffer.writeln('현재 조정대상지역: ${_regulatedAreas.join(", ")}');
    buffer.writeln('위 지역 외는 비조정지역입니다.');

    if (docs.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('## 참고 세법 자료');
      for (final doc in docs) {
        buffer.writeln(doc);
        buffer.writeln();
      }
    }

    if (_propertyContext != null) {
      buffer.writeln();
      buffer.writeln('## 현재 상담 중인 물건 정보');
      final p = _propertyContext!;
      if (p['아파트명'] != null) buffer.writeln('- 물건명: ${p['아파트명']}');
      if (p['동명'] != null) buffer.writeln('- 동: ${p['동명']}');
      final address = (p['주소'] ?? p['소재지'])?.toString();
      if (address != null) buffer.writeln('- 주소: $address');
      final usage = p['용도'] ?? p['물건종류'];
      if (usage != null) buffer.writeln('- 용도: $usage');
      if (p['전용면적'] != null) buffer.writeln('- 전용면적: ${p['전용면적']}㎡');
      if (p['감정가'] != null) {
        buffer.writeln('- 감정가: ${_formatWon(p['감정가'])}');
      }
      if (p['매각금액'] != null) {
        buffer.writeln('- 낙찰가(매각금액): ${_formatWon(p['매각금액'])}');
      }
      if (p['매각결과'] != null) buffer.writeln('- 매각결과: ${p['매각결과']}');
      if (p['사건번호'] != null) buffer.writeln('- 사건번호: ${p['사건번호']}');
      if (p['법원'] != null) buffer.writeln('- 법원: ${p['법원']}');

      if (_isPropertyRegulated != null) {
        buffer.writeln(
            '- 조정대상지역: ${_isPropertyRegulated! ? "✅ 해당 (중과세율 적용)" : "❌ 비해당 (일반세율 적용)"}');
      }

      buffer.writeln();
      buffer.writeln('사용자가 "이 물건"이라고 하면 위 물건을 기준으로 답변하세요.');
      if (_isPropertyRegulated != null) {
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
      List<Map<String, dynamic>> messages) async {
    final body = json.encode({
      'model': _model,
      'max_completion_tokens': _maxTokens,
      'temperature': 0.5,
      'messages': messages,
      'tools': TaxCalculator.toolDefinitions,
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

    final docs = _retrieveRelevantDocs(message);
    final systemPrompt = _buildSystemPrompt(docs);

    _history.add({'role': 'user', 'content': message});

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ..._history,
    ];

    try {
      var data = await _callApi(messages);
      var choice = data['choices'][0];
      var assistantMessage = choice['message'];

      int rounds = 0;
      while (choice['finish_reason'] == 'tool_calls' && rounds < 5) {
        rounds++;

        messages.add(assistantMessage);

        final toolCalls = assistantMessage['tool_calls'] as List<dynamic>;
        for (final toolCall in toolCalls) {
          final fnName = toolCall['function']['name'] as String;
          final fnArgs =
              json.decode(toolCall['function']['arguments'] as String)
                  as Map<String, dynamic>;

          final result = TaxCalculator.executeFunction(fnName, fnArgs);

          messages.add({
            'role': 'tool',
            'tool_call_id': toolCall['id'],
            'content': result,
          });
        }

        data = await _callApi(messages);
        choice = data['choices'][0];
        assistantMessage = choice['message'];
      }

      final text = assistantMessage['content'] as String? ?? '';
      _history.add({'role': 'assistant', 'content': text});
      return text;
    } catch (e) {
      _history.removeLast();
      if (e is Exception) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        if (msg.contains('API 오류')) return '⚠️ $msg';
      }
      return '⚠️ 네트워크 오류: 인터넷 연결을 확인해주세요.\n\n$e';
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
