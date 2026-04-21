import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores user-customizable summary templates for the reading companion.
class ReadingTemplateStore {
  static const _key = 'reading_companion.templates';

  static const defaultTemplates = <String, String>{
    '知识学习': '''# {{title}}
> 来源: {{url}}
> 分类: {{category}}

## 摘要
{{summary}}

## 核心概念
{{core_concepts}}

## 要点
{{key_points}}

## 全文
{{full_text}}

## 我的笔记
''',
    '出游攻略': '''# {{title}}
> 来源: {{url}}
> 分类: {{category}}

## 摘要
{{summary}}

## 目的地
{{destinations}}

## 路线
{{routes}}

## 贴士
{{tips}}

## 全文
{{full_text}}

## 我的笔记
''',
    '美食探店': '''# {{title}}
> 来源: {{url}}
> 分类: {{category}}

## 摘要
{{summary}}

## 餐厅
{{restaurants}}

## 全文
{{full_text}}

## 我的笔记
''',
    '商品种草': '''# {{title}}
> 来源: {{url}}
> 分类: {{category}}

## 摘要
{{summary}}

## 商品
{{items}}

## 全文
{{full_text}}

## 我的笔记
''',
    '新闻资讯': '''# {{title}}
> 来源: {{url}}
> 分类: {{category}}

## 摘要
{{summary}}

## 关键信息
{{key_points}}

## 全文
{{full_text}}

## 我的笔记
''',
    '影视娱乐': '''# {{title}}
> 来源: {{url}}
> 分类: {{category}}

## 摘要
{{summary}}

## 亮点
{{highlights}}

## 全文
{{full_text}}

## 我的笔记
''',
    '生活感悟': '''# {{title}}
> 来源: {{url}}
> 分类: {{category}}

## 摘要
{{summary}}

## 感悟
{{key_points}}

## 全文
{{full_text}}

## 我的笔记
''',
    '其他': '''# {{title}}
> 来源: {{url}}
> 分类: {{category}}

## 摘要
{{summary}}

## 要点
{{key_points}}

## 全文
{{full_text}}

## 我的笔记
''',
  };

  static Future<Map<String, String>> loadTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return Map.from(defaultTemplates);
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return Map.from(defaultTemplates);
    }
  }

  static Future<void> saveTemplates(Map<String, String> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(templates));
  }

  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
