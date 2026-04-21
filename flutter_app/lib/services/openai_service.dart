import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'tax_calculator.dart';

class OpenAIService {
  static const _model = 'gpt-5-nano';
  static const _apiUrl = 'https://api.openai.com/v1/chat/completions';

  static String get _apiKey => dotenv.env['OPENAI_API_KEY'] ?? '';

  final List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _propertyContext;

  Map<String, String> _docCache = {};
  List<String> _regulatedAreas = [];
  bool _loaded = false;
  bool? _isPropertyRegulated;

  static const _docDescriptions = {
    '01_취득세.md': '취득세 세율, 다주택 중과, 부가세, 인지세',
    '02_양도소득세.md': '양도소득세, 장기보유공제, 비과세',
    '03_경매절차.md': '입찰·낙찰·명도 절차, 권리분석',
    '04_주택임대차보호법.md': '대항력, 우선변제권, 소액임차인, 배당',
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

  // --- LLM 라우터: 질문에 맞는 문서 1개 선택 ---
  Future<String?> _routeDocument(String query) async {
    final docList = _docDescriptions.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');

    final data = await _callApi([
      {
        'role': 'system',
        'content': '문서 중 질문에 맞는 파일명 1개만 답하세요. 없으면 none.\n$docList',
      },
      {'role': 'user', 'content': query},
    ]);

    final text = _extractText(data);
    for (final file in _docDescriptions.keys) {
      if (text.contains(file)) return file;
    }
    if (text.contains('01')) return '01_취득세.md';
    if (text.contains('02')) return '02_양도소득세.md';
    if (text.contains('03')) return '03_경매절차.md';
    if (text.contains('04')) return '04_주택임대차보호법.md';
    return null;
  }

  // --- 시스템 프롬프트 ---
  String _buildSystemPrompt({String? ragDoc, bool withToolHint = false}) {
    final buffer = StringBuffer();

    buffer.writeln('당신은 한국 부동산 세금·경매 법률 전문 상담사입니다.');
    buffer.write('규칙: 한국어. 금액은 만원/억원 단위. 핵심만 간결하게. 반복 금지.');
    if (withToolHint) {
      buffer.writeln(' 세금 계산이 필요하면 제공된 계산기 함수를 호출하세요.');
    } else {
      buffer.writeln(' 계산 결과는 표 형태로 정리.');
    }

    if (ragDoc != null) {
      buffer.writeln();
      buffer.writeln('## 참고 자료');
      buffer.writeln(
          ragDoc.length > 1500 ? '${ragDoc.substring(0, 1500)}\n...' : ragDoc);
    }

    if (_propertyContext != null) {
      buffer.writeln();
      buffer.writeln('## 상담 물건');
      final p = _propertyContext!;
      if (p['아파트명'] != null) buffer.writeln('- 물건명: ${p['아파트명']}');
      final address = (p['주소'] ?? p['소재지'])?.toString();
      if (address != null) buffer.writeln('- 주소: $address');
      final usage = p['용도'] ?? p['물건종류'];
      if (usage != null) buffer.writeln('- 용도: $usage');
      if (p['전용면적'] != null) buffer.writeln('- 전용면적: ${p['전용면적']}㎡');
      if (p['감정가'] != null) buffer.writeln('- 감정가: ${_formatWon(p['감정가'])}');
      if (p['매각금액'] != null) buffer.writeln('- 낙찰가: ${_formatWon(p['매각금액'])}');

      if (_isPropertyRegulated != null) {
        final reg = _isPropertyRegulated!;
        buffer.writeln('- 조정대상지역: ${reg ? "해당" : "비해당"}');
        buffer.writeln(reg
            ? '  취득세: 2주택8%/3주택12%, 양도세: 2주택+20%p/3주택+30%p'
            : '  취득세: 2주택 일반(1~3%)/3주택8%, 양도세: 기본세율');
        if (withToolHint) {
          buffer.writeln('  계산기 호출 시 is_regulated_area=$reg');
        }
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

  // --- API 호출 ---
  Future<Map<String, dynamic>> _callApi(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    final payload = <String, dynamic>{
      'model': _model,
      'messages': messages,
    };
    if (tools != null) payload['tools'] = tools;

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: json.encode(payload),
    );

    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      final errorBody = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(
          'API ${response.statusCode}: ${errorBody['error']?['message'] ?? ''}');
    }
  }

  String _extractText(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices == null || (choices as List).isEmpty) return '';
    final msg = (choices as List)[0]['message'] as Map<String, dynamic>;
    return (msg['content'] as String?) ?? '';
  }

  Map<String, dynamic>? _extractToolCalls(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices == null || (choices as List).isEmpty) return null;
    final msg = (choices as List)[0]['message'] as Map<String, dynamic>;
    if (msg['tool_calls'] != null) return msg;
    return null;
  }

  // --- 메인 메시지 처리 ---
  Future<String> sendMessage(String message) async {
    if (!hasApiKey) {
      return '⚠️ API 키가 설정되지 않았습니다.\n'
          'flutter_app/.env 파일에 OPENAI_API_KEY=sk-... 를 입력해주세요.';
    }

    await loadKnowledgeBase();

    if (_propertyContext != null && _isPropertyRegulated == null) {
      final address =
          (_propertyContext!['주소'] ?? _propertyContext!['소재지'])?.toString();
      _isPropertyRegulated = _checkRegulatedArea(address);
    }

    // 1단계: LLM 라우터 → 문서 1개 선택
    String? ragDoc;
    try {
      final file = await _routeDocument(message);
      if (file != null) ragDoc = _docCache[file];
    } catch (_) {}

    _history.add({'role': 'user', 'content': message});

    try {
      // 2단계: RAG + Function Calling 시도
      var text = await _tryWithToolsAndRag(ragDoc);

      // 3단계: 실패 시 RAG만 (tools 없이)
      if (text.isEmpty) {
        text = await _tryPlain(ragDoc);
      }

      // 4단계: 그래도 실패 시 RAG도 제거
      if (text.isEmpty) {
        text = await _tryPlain(null);
      }

      if (text.isEmpty) {
        _history.removeLast();
        return '⚠️ AI 응답을 받지 못했습니다. 다시 시도해주세요.';
      }

      _history.add({'role': 'assistant', 'content': text});
      return text;
    } catch (e) {
      if (_history.isNotEmpty) _history.removeLast();
      return '⚠️ 오류: $e';
    }
  }

  // tools + RAG 시도
  Future<String> _tryWithToolsAndRag(String? ragDoc) async {
    try {
      final prompt = _buildSystemPrompt(ragDoc: ragDoc, withToolHint: true);
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': prompt},
        ..._history,
      ];

      var data = await _callApi(messages,
          tools: TaxCalculator.toolDefinitions.cast<Map<String, dynamic>>());

      // Function Calling 루프
      var toolMsg = _extractToolCalls(data);
      int rounds = 0;
      while (toolMsg != null && rounds < 3) {
        rounds++;
        messages.add(Map<String, dynamic>.from(toolMsg));

        final toolCalls = toolMsg['tool_calls'] as List<dynamic>;
        for (final tc in toolCalls) {
          final fn = tc['function'] as Map<String, dynamic>;
          final result = TaxCalculator.executeFunction(
            fn['name'] as String,
            json.decode(fn['arguments'] as String) as Map<String, dynamic>,
          );
          messages.add({
            'role': 'tool',
            'tool_call_id': tc['id'],
            'content': result,
          });
        }

        data = await _callApi(messages);
        toolMsg = _extractToolCalls(data);
      }

      return _extractText(data);
    } catch (_) {
      return '';
    }
  }

  // tools 없이 시도
  Future<String> _tryPlain(String? ragDoc) async {
    try {
      final prompt = _buildSystemPrompt(ragDoc: ragDoc);
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': prompt},
        ..._history,
      ];
      final data = await _callApi(messages);
      return _extractText(data);
    } catch (_) {
      return '';
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
