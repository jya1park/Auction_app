import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class SearchResult {
  final String title;
  final String description;
  final String link;

  SearchResult({required this.title, required this.description, required this.link});
}

class NaverSearchService {
  static String get _clientId => dotenv.env['NAVER_CLIENT_ID'] ?? '';
  static String get _clientSecret => dotenv.env['NAVER_CLIENT_SECRET'] ?? '';

  static bool get hasKeys => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  static Future<List<SearchResult>> searchResults(String query, {int display = 3}) async {
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

    return items.map((item) => SearchResult(
      title: _stripHtml(item['title'] ?? ''),
      description: _stripHtml(item['description'] ?? ''),
      link: item['link'] ?? '',
    )).where((r) => r.title.isNotEmpty).toList();
  }

  static Future<String> search(String query, {int display = 3}) async {
    final results = await searchResults(query, display: display);
    final buffer = StringBuffer();
    for (final r in results) {
      buffer.writeln('- ${r.title}: ${r.description}');
    }
    return buffer.toString();
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
