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
    '03_경매절차.md': '입찰·낙찰·명도, 권리분석',
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
    if (address == null || address.isEmpty || _regulatedAreas.isEmpty) {
      return false;
    }
    for (final area in _regulatedAreas) {
      // 전체 매칭: "서울특별시 강남구" in "서울특별시 강남구 역삼동 123"
      if (address.contains(area)) return true;

      final parts = area.split(' ');
      // 구/시 이름만 매칭: "강남구", "영통구", "과천시" 등
      final district = parts.last;
      if (address.contains(district)) return true;
    }
    return false;
  }

  Future<String?> _routeDocument(String query) async {
    final docList = _docDescriptions.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');

    final data = await _callApi([
      {
        'role': 'system',
        'content': '질문에 맞는 파일명 1개만 답하세요. 없으면 none.\n$docList',
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

  String _buildSystemPrompt(String? ragDoc) {
    final buffer = StringBuffer();

    buffer.writeln('한국 부동산 세금·경매 법률 전문 상담사.');
    buffer.writeln('규칙: 핵심만 간결하게. 금액은 만원/억원 단위. 표 형태로 정리. 계산 결과에는 적용 세율과 산출 근거를 한 줄씩 간단히 설명.');

    if (ragDoc != null && ragDoc.isNotEmpty) {
      final trimmed = ragDoc.length > 1500
          ? '${ragDoc.substring(0, 1500)}\n...'
          : ragDoc;
      buffer.writeln('\n## 참고\n$trimmed');
    }

    if (_propertyContext != null) {
      buffer.writeln('\n## 물건');
      final p = _propertyContext!;
      if (p['아파트명'] != null) buffer.writeln('- ${p['아파트명']}');
      final addr = (p['주소'] ?? p['소재지'])?.toString();
      if (addr != null) buffer.writeln('- 주소: $addr');
      final usage = p['용도'] ?? p['물건종류'];
      if (usage != null) buffer.writeln('- 용도: $usage');
      final area = _parseNum(p['전용면적']);
      if (area != null) buffer.writeln('- ${area}㎡');
      if (p['감정가'] != null) buffer.writeln('- 감정가: ${_formatWon(p['감정가'])}');
      final salePrice = _parseNum(p['매각금액']);
      if (salePrice != null) buffer.writeln('- 낙찰가: ${_formatWon(salePrice)}');

      final reg = _isPropertyRegulated ?? false;
      buffer.writeln('- 조정대상지역: ${reg ? "해당" : "비해당"}');

      // Dart 계산기로 미리 계산한 세금 결과
      if (salePrice != null && salePrice > 0) {
        final tax = TaxCalculator.calculateAcquisitionTax(
          price: salePrice.toInt(),
          isRegulatedArea: reg,
          areaSqm: area ?? 84.0,
        );
        buffer.writeln('\n## 1주택 기준 취득세 (계산기 산출, 정확한 값)');
        buffer.writeln(tax['breakdown']);

        final total = TaxCalculator.calculateTotalCost(
          salePrice: salePrice.toInt(),
          isRegulatedArea: reg,
          areaSqm: area ?? 84.0,
        );
        buffer.writeln('\n## 총 비용 (계산기 산출)');
        buffer.writeln(total['breakdown']);
      }

      if (reg) {
        buffer.writeln('\n※ 다주택 중과: 2주택 8%, 3주택 12% (조정대상지역)');
      }
    }

    return buffer.toString();
  }

  double? _parseNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', ''));
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
          'API ${response.statusCode}: ${errorBody['error']?['message'] ?? ''}');
    }
  }

  String _extractText(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices == null || (choices as List).isEmpty) return '';
    return ((choices as List)[0]['message']['content'] as String?) ?? '';
  }

  Future<String> sendMessage(String message) async {
    if (!hasApiKey) {
      return '⚠️ flutter_app/.env에 OPENAI_API_KEY를 입력해주세요.';
    }

    await loadKnowledgeBase();

    if (_propertyContext != null) {
      final address =
          (_propertyContext!['주소'] ?? _propertyContext!['소재지'])?.toString();
      _isPropertyRegulated = _checkRegulatedArea(address);
    }

    // 1. 라우터: 문서 선택
    String? ragDoc;
    try {
      final file = await _routeDocument(message);
      if (file != null) ragDoc = _docCache[file];
    } catch (_) {}

    // 2. 프롬프트 조립 + API 호출
    _history.add({'role': 'user', 'content': message});

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _buildSystemPrompt(ragDoc)},
      ..._history,
    ];

    try {
      final data = await _callApi(messages);
      final text = _extractText(data);

      if (text.isEmpty) {
        _history.removeLast();
        return '⚠️ 응답을 받지 못했습니다. 다시 시도해주세요.';
      }

      _history.add({'role': 'assistant', 'content': text});
      return text;
    } catch (e) {
      if (_history.isNotEmpty) _history.removeLast();
      return '⚠️ 오류: $e';
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
