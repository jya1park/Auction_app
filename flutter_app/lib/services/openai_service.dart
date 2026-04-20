import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

class OpenAIService {
  static const _model = 'gpt-4o';
  static const _apiUrl = 'https://api.openai.com/v1/chat/completions';
  static const _apiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const _maxTokens = 2048;

  final List<Map<String, String>> _history = [];
  Map<String, dynamic>? _propertyContext;

  Map<String, List<String>> _keywordIndex = {};
  Map<String, String> _docCache = {};
  bool _loaded = false;

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

    _loaded = true;
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
    buffer.writeln();
    buffer.writeln('## 규칙');
    buffer.writeln('- 항상 한국어로 응답하세요.');
    buffer.writeln('- 금액은 "만원" 또는 "억원" 단위로 읽기 쉽게 표시하세요.');
    buffer.writeln('- 세금 계산 시 단계별로 과정을 보여주세요.');
    buffer.writeln('- 가정이 필요한 경우 (주택 수, 조정대상지역 여부 등) 명시적으로 안내하세요.');
    buffer.writeln('- 아래 제공된 세법 자료를 기반으로 정확하게 답변하세요.');
    buffer.writeln('- 확실하지 않은 내용은 전문가 상담을 권유하세요.');

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
      final address = p['주소'] ?? p['소재지'];
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
      buffer.writeln();
      buffer.writeln('사용자가 "이 물건"이라고 하면 위 물건을 기준으로 답변하세요.');
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

  Future<String> sendMessage(String message) async {
    if (!hasApiKey) {
      return '⚠️ API 키가 설정되지 않았습니다.\n\n'
          'flutter run --dart-define=OPENAI_API_KEY=sk-... 으로 실행해주세요.';
    }

    await loadKnowledgeBase();

    final docs = _retrieveRelevantDocs(message);
    final systemPrompt = _buildSystemPrompt(docs);

    _history.add({'role': 'user', 'content': message});

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ..._history,
    ];

    final body = json.encode({
      'model': _model,
      'max_tokens': _maxTokens,
      'messages': messages,
    });

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final text =
            data['choices'][0]['message']['content'] as String;
        _history.add({'role': 'assistant', 'content': text});
        return text;
      } else {
        _history.removeLast();
        final errorBody = json.decode(utf8.decode(response.bodyBytes));
        final errorMsg =
            errorBody['error']?['message'] ?? '알 수 없는 오류';
        return '⚠️ API 오류 (${response.statusCode}): $errorMsg';
      }
    } catch (e) {
      _history.removeLast();
      return '⚠️ 네트워크 오류: 인터넷 연결을 확인해주세요.\n\n$e';
    }
  }

  void setPropertyContext(Map<String, dynamic> property) {
    _propertyContext = property;
  }

  void clearHistory() {
    _history.clear();
  }

  void clearAll() {
    _history.clear();
    _propertyContext = null;
  }
}
