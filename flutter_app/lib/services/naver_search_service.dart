import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class SearchResult {
  final String title;
  final String description;
  final String link;
  String body;

  SearchResult({
    required this.title,
    required this.description,
    required this.link,
    this.body = '',
  });
}

class NaverSearchService {
  static String get _clientId => dotenv.env['NAVER_CLIENT_ID'] ?? '';
  static String get _clientSecret => dotenv.env['NAVER_CLIENT_SECRET'] ?? '';

  static bool get hasKeys => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  static Future<List<SearchResult>> searchResults(String query,
      {int display = 3}) async {
    if (!hasKeys) return [];

    final url = Uri.parse(
        'https://openapi.naver.com/v1/search/blog.json'
        '?query=${Uri.encodeComponent(query)}&display=$display&sort=sim');

    final response = await http.get(url, headers: {
      'X-Naver-Client-Id': _clientId,
      'X-Naver-Client-Secret': _clientSecret,
    });

    if (response.statusCode != 200) return [];

    final data = json.decode(utf8.decode(response.bodyBytes));
    final items = data['items'] as List? ?? [];

    return items
        .map((item) => SearchResult(
              title: _stripHtml(item['title'] ?? ''),
              description: _stripHtml(item['description'] ?? ''),
              link: item['link'] ?? '',
            ))
        .where((r) => r.title.isNotEmpty)
        .toList();
  }

  /// 블로그 본문 크롤링 (각 SearchResult의 body 채우기)
  static Future<void> fetchBodies(List<SearchResult> results,
      {int maxChars = 1000}) async {
    for (final r in results) {
      if (r.link.isEmpty) continue;
      try {
        final response = await http
            .get(Uri.parse(r.link), headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            })
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final html = utf8.decode(response.bodyBytes, allowMalformed: true);
          final text = _extractBodyText(html);
          r.body = text.length > maxChars
              ? text.substring(0, maxChars)
              : text;
        }
      } catch (_) {}
    }
  }

  /// HTML에서 본문 텍스트 추출
  static String _extractBodyText(String html) {
    // 네이버 블로그 본문 영역 추출 시도
    var body = html;

    // 1) 네이버 블로그 본문 컨테이너
    final containers = [
      RegExp(r'class="se-main-container"[^>]*>(.*?)</div>\s*</div>\s*</div>',
          dotAll: true),
      RegExp(r'class="post_ct"[^>]*>(.*?)</div>', dotAll: true),
      RegExp(r'class="se-text-paragraph"[^>]*>(.*?)</p>', dotAll: true),
      RegExp(r'<article[^>]*>(.*?)</article>', dotAll: true),
    ];

    for (final pattern in containers) {
      final matches = pattern.allMatches(html);
      if (matches.isNotEmpty) {
        body = matches.map((m) => m.group(1) ?? '').join(' ');
        break;
      }
    }

    // 2) HTML 태그 제거
    body = body
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'&[a-zA-Z]+;'), ' ')
        .replaceAll(RegExp(r'&#\d+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return body;
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }
}
