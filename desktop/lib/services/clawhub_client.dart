import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../models/clawhub_models.dart';

class ClawHubClient {
  static const _baseUrl = 'https://clawhub.ai';

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30);

  Future<List<ClawHubSearchResult>> search(String query,
      {int limit = 20}) async {
    final encoded = Uri.encodeQueryComponent(query);
    final body = await _fetch('$_baseUrl/api/search?q=$encoded&limit=$limit');
    final json = jsonDecode(body) as Map<String, dynamic>;
    final results = json['results'] as List<dynamic>? ?? [];
    return results
        .map((e) => ClawHubSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ClawHubSkillDetail> getSkillDetail(String slug) async {
    final encoded = Uri.encodeComponent(slug);
    final body = await _fetch('$_baseUrl/api/v1/skills/$encoded');
    final json = jsonDecode(body) as Map<String, dynamic>;
    return ClawHubSkillDetail.fromJson(json);
  }

  Future<String> downloadSkillContent(String slug, String version) async {
    final encodedSlug = Uri.encodeComponent(slug);
    final encodedVer = Uri.encodeComponent(version);

    // Try version zip download first
    final zipContent = await _tryDownloadZip(
        '$_baseUrl/api/v1/skills/$encodedSlug/versions/$encodedVer/download');
    if (zipContent != null) return zipContent;

    // Try /content endpoint
    final content =
        await _tryFetchText('$_baseUrl/api/v1/skills/$encodedSlug/content');
    if (content != null) return content;

    // Try legacy download
    final legacy = await _tryFetchText(
        '$_baseUrl/api/download?slug=$encodedSlug&version=$encodedVer');
    if (legacy != null) return legacy;

    throw Exception(
        'Could not download SKILL.md. Visit https://clawhub.ai/$slug to copy content manually.');
  }

  Future<String?> _tryDownloadZip(String url) async {
    try {
      final bytes = await _fetchBytes(url);
      if (bytes == null) return null;
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (file.isFile &&
            file.name.toLowerCase().endsWith('skill.md')) {
          return utf8.decode(file.content as List<int>);
        }
      }
      return null;
    } catch (e) {
      debugPrint('ClawHub: zip download failed: $e');
      return null;
    }
  }

  Future<String?> _tryFetchText(String url) async {
    try {
      final text = await _fetch(url);
      if (text.trim().isEmpty) return null;
      if (text.trimLeft().startsWith('{')) return null;
      return text;
    } catch (e) {
      debugPrint('ClawHub: text fetch failed: $e');
      return null;
    }
  }

  Future<String> _fetch(String url) async {
    final uri = Uri.parse(url);
    final request = await _client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return response.transform(utf8.decoder).join();
  }

  Future<Uint8List?> _fetchBytes(String url) async {
    try {
      final uri = Uri.parse(url);
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
