import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/openai_service.dart';
import '../widgets/chat_bubble.dart';

class TaxChatScreen extends StatefulWidget {
  final Map<String, dynamic>? property;

  const TaxChatScreen({super.key, this.property});

  @override
  State<TaxChatScreen> createState() => _TaxChatScreenState();
}

class _TaxChatScreenState extends State<TaxChatScreen> {
  final _aiService = OpenAIService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.property != null) {
      _aiService.setPropertyContext(widget.property!);
    }
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    final hasProperty = widget.property != null;
    String welcome;
    if (hasProperty) {
      final name = widget.property!['아파트명'] ?? '해당 물건';
      welcome = '안녕하세요! 부동산 세금 전문 상담사입니다.\n\n'
          '[$name]에 대해 궁금하신 세금 관련 질문을 해주세요.\n\n'
          '예) "이 물건 취득세 얼마야?", "다주택자인데 세금은?"';
    } else {
      welcome = '안녕하세요! 부동산 정책·경매 전문 상담사입니다.\n\n'
          '경매 절차, 권리분석, 부동산 정책, 세금 등 궁금한 점을 물어보세요.\n\n'
          '예) "경매 입찰 절차 알려줘", "조정대상지역 규제는?"';
    }
    _messages.add(_ChatMessage(text: welcome, isUser: false));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    _controller.clear();

    setState(() {
      _messages.add(_ChatMessage(text: text.trim(), isUser: true));
      _messages.add(_ChatMessage(text: '', isUser: false));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      await for (final partial in _aiService.sendMessageStream(text.trim())) {
        if (!mounted) return;
        setState(() {
          _messages.last = _ChatMessage(text: partial, isUser: false);
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _messages.last = _ChatMessage(text: '⚠️ 오류: $e', isUser: false);
      });
    }

    setState(() => _isLoading = false);
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('대화 초기화'),
        content: const Text('모든 대화 내용이 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _messages.clear();
                _aiService.clearHistory();
                _addWelcomeMessage();
              });
            },
            child: const Text('초기화'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.property != null ? '세금 상담' : '경매 상담'),
        actions: [
          IconButton(
            onPressed: _clearChat,
            icon: const Icon(Icons.delete_outline),
            tooltip: '대화 초기화',
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.property != null) _buildPropertyCard(colorScheme),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (_, index) {
                if (index == _messages.length && _isLoading) {
                  return const TypingIndicator();
                }
                final msg = _messages[index];
                return ChatBubble(message: msg.text, isUser: msg.isUser);
              },
            ),
          ),
          if (widget.property != null && _messages.length <= 1)
            _buildQuickChips(colorScheme),
          _buildInputBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildPropertyCard(ColorScheme colorScheme) {
    final p = widget.property!;
    final name = p['아파트명'] ?? '물건';
    final usage = p['용도'] ?? p['물건종류'] ?? '';
    final area = p['전용면적'];

    String priceInfo = '';
    if (p['감정가'] != null) {
      priceInfo += '감정 ${_formatWon(p['감정가'])}';
    }
    if (p['매각금액'] != null) {
      if (priceInfo.isNotEmpty) priceInfo += '  |  ';
      priceInfo += '낙찰 ${_formatWon(p['매각금액'])}';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (usage.isNotEmpty) usage,
              if (area != null) '${area}㎡',
              if (priceInfo.isNotEmpty) priceInfo,
            ].join('  |  '),
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChips(ColorScheme colorScheme) {
    final chips = [
      ('취득세는?', '이 물건의 취득세를 계산해주세요. 조정대상지역 여부와 1주택자 기준으로 부가세, 인지세까지 포함해서 알려주세요.'),
      ('양도세는?', '이 물건을 3년 후 시세 대비 20% 오른 가격에 매도한다고 가정하고, 양도소득세를 계산해주세요.'),
      ('총 비용은?', '이 물건을 낙찰받을 때 필요한 총 비용을 정리해주세요. 낙찰대금, 취득세, 부가세, 인지세, 법무사 비용, 예상 명도비까지 포함해주세요.'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Wrap(
        spacing: 8,
        children: chips.map((chip) {
          return ActionChip(
            label: Text(chip.$1, style: const TextStyle(fontSize: 13)),
            onPressed: _isLoading ? null : () => _sendMessage(chip.$2),
            backgroundColor: colorScheme.secondaryContainer,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputBar(ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: widget.property != null
                    ? '세금 관련 질문을 입력하세요'
                    : '경매·부동산 정책 관련 질문을 입력하세요',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: _isLoading ? null : _sendMessage,
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _isLoading
                ? null
                : () => _sendMessage(_controller.text),
            icon: const Icon(Icons.send, size: 20),
          ),
        ],
      ),
    );
  }

  String _formatWon(dynamic value) {
    if (value == null) return '';
    final num amount;
    if (value is num) {
      amount = value;
    } else {
      amount = num.tryParse(value.toString().replaceAll(',', '')) ?? 0;
    }
    final formatter = NumberFormat('#,###');
    if (amount >= 100000000) {
      final eok = amount / 100000000;
      final man = ((amount % 100000000) / 10000).round();
      if (man > 0) {
        return '${eok.floor()}억 ${formatter.format(man)}만';
      }
      return '${eok.floor()}억';
    } else if (amount >= 10000) {
      return '${formatter.format((amount / 10000).round())}만';
    }
    return '${formatter.format(amount.round())}원';
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;

  _ChatMessage({required this.text, required this.isUser});
}
