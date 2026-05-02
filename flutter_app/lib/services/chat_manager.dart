import 'dart:async';
import '../services/openai_service.dart';

class ChatMessage {
  String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatManager {
  ChatManager._();
  static final instance = ChatManager._();

  final OpenAIService _service = OpenAIService();
  final List<ChatMessage> messages = [];
  bool isLoading = false;
  String? _systemOverride;
  Map<String, dynamic>? _property;

  final _listeners = <VoidCallback>[];

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  void _notify() {
    for (final l in _listeners) {
      l();
    }
  }

  void init({Map<String, dynamic>? property, String? systemOverride}) {
    _systemOverride = systemOverride;
    if (property != _property) {
      _property = property;
      if (property != null) {
        _service.setPropertyContext(property);
      }
    }
    if (messages.isEmpty) {
      _addWelcome();
    }
  }

  void _addWelcome() {
    String welcome;
    if (_property != null) {
      final name = _property!['아파트명'] ?? '해당 물건';
      welcome = '안녕하세요! 부동산 세금 전문 상담사입니다.\n\n'
          '[$name]에 대해 궁금하신 세금 관련 질문을 해주세요.\n\n'
          '예) "이 물건 취득세 얼마야?", "다주택자인데 세금은?"';
    } else {
      welcome = '안녕하세요! 부동산 정책·경매 전문 상담사입니다.\n\n'
          '경매 절차, 권리분석, 부동산 정책, 세금 등 궁금한 점을 물어보세요.\n\n'
          '예) "경매 입찰 절차 알려줘", "조정대상지역 규제는?"';
    }
    messages.add(ChatMessage(text: welcome, isUser: false));
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || isLoading) return;

    messages.add(ChatMessage(text: text.trim(), isUser: true));
    messages.add(ChatMessage(text: '', isUser: false));
    isLoading = true;
    _notify();

    try {
      final stream = _service.sendMessageStream(
        text.trim(),
        systemOverride: _systemOverride,
      );
      await for (final partial in stream) {
        messages.last.text = partial;
        _notify();
      }
    } catch (e) {
      messages.last.text = '⚠️ 오류: $e';
    }

    isLoading = false;
    _notify();
  }

  void clear() {
    messages.clear();
    _service.clearHistory();
    _addWelcome();
    _notify();
  }
}

typedef VoidCallback = void Function();
