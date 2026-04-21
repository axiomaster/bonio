import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Reading summary JSON parsing', () {
    /// Simulates what note_service.summarizeReading does before returning.
    String sanitizeResult(String result) {
      return result.replaceAll(RegExp(r'[\x00-\x1f]'), '');
    }

    /// Simulates extracting JSON block from potentially wrapped response.
    String extractJson(String resultJson) {
      final start = resultJson.indexOf('{');
      final end = resultJson.lastIndexOf('}');
      if (start >= 0 && end > start) {
        resultJson = resultJson.substring(start, end + 1);
      }
      return sanitizeResult(resultJson);
    }

    test('parses clean JSON from LLM', () {
      const input = '''
{
  "title": "从生物学角度分析",
  "author": "张三",
  "summary": "这是一篇关于生物学的文章摘要。",
  "paragraph_summaries": [
    {"subtitle": "外观特征", "content": "详细描述了外观。"}
  ]
}''';
      final cleaned = extractJson(input);
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      expect(json['title'], '从生物学角度分析');
      expect(json['author'], '张三');
      expect(json['summary'], isNotEmpty);
    });

    test('handles control characters inside string values', () {
      // Simulates LLM inserting literal newline inside a JSON string value
      final input = '{\n'
          '  "title": "测试文章",\n'
          '  "author": "",\n'
          '  "summary": "摘要中包含换行符\x0a会导致解析失败",\n'
          '  "paragraph_summaries": [\n'
          '    {"subtitle": "标题", "content": "内容中有\x0b控制字符"}\n'
          '  ]\n'
          '}';
      final cleaned = extractJson(input);
      // Should not throw
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      expect(json['title'], '测试文章');
      expect(json['summary'], contains('摘要中包含换行符'));
    });

    test('handles JSON wrapped in markdown code block', () {
      const input = '```json\n'
          '{\n'
          '  "title": "测试",\n'
          '  "author": "",\n'
          '  "summary": "摘要",\n'
          '  "paragraph_summaries": []\n'
          '}\n'
          '```';
      final cleaned = extractJson(input);
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      expect(json['title'], '测试');
    });

    test('handles mixed control characters throughout', () {
      // Simulates streaming corruption with various control chars
      final input = '{\x0a'
          '  "title": "标题\x08中有\x0c控制符",\x0d\n'
          '  "author": "",\x0b\n'
          '  "summary": "摘要\x00内容",\n'
          '  "paragraph_summaries": [\x0e\n'
          '    {"subtitle": "小\x1f标题", "content": "内容\x01详情"}\n'
          '  ]\n'
          '}';
      final cleaned = extractJson(input);
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      expect(json['title'], '标题中有控制符');
      expect(json['summary'], '摘要内容');
    });

    test('handles real-world OpenClaw response', () {
      const input = '{\n'
          '  "title": "瞎扯 · 如何正确地吐槽",\n'
          '  "author": "",\n'
          '  "summary": "本文为知乎「瞎扯」栏目的幽默问答汇编。",\n'
          '  "paragraph_summaries": [\n'
          '    {\n'
          '      "subtitle": "亲密关系的吐槽",\n'
          '      "content": "以自嘲方式调侃夫妻关系。"\n'
          '    },\n'
          '    {\n'
          '      "subtitle": "冷知识反转",\n'
          '      "content": "植物大战僵尸中巨人僵尸背小僵尸不是父子而是兄弟，且小的是大哥。"\n'
          '    }\n'
          '  ]\n'
          '}';
      final cleaned = extractJson(input);
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      expect(json['title'], '瞎扯 · 如何正确地吐槽');
      final summaries = json['paragraph_summaries'] as List;
      expect(summaries.length, 2);
    });
  });
}
