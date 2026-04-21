import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Article category for the reading companion. Each category maps to a
/// different AI prompt template and output format.
enum ReadingCategory {
  auto('auto', '自动检测', ''),
  scienceTech('science_tech', '科技科普', 'ScienceTech.md'),
  currentAffairs('current_affairs', '时事新闻', 'CurrentAffairs.md'),
  fictionStory('fiction_story', '文学故事', 'FictionStory.md'),
  financeBusiness('finance_business', '金融商业', 'FinanceBusiness.md'),
  methodologyTutorials('methodology_tutorials', '方法教程', 'MethodologyTutorials.md');

  const ReadingCategory(this.key, this.label, this.assetFile);

  /// Stable string key used in IPC messages (not the enum name).
  final String key;

  /// Human-readable label shown in the UI dropdown.
  final String label;

  /// Asset filename under `assets/reading/`. Empty for [auto].
  final String assetFile;

  /// Parse from [key] string. Falls back to [auto].
  static ReadingCategory fromKey(String? key) {
    if (key == null) return ReadingCategory.auto;
    return ReadingCategory.values.firstWhere(
      (c) => c.key == key,
      orElse: () => ReadingCategory.auto,
    );
  }
}

/// Stores user-customizable summary template for the reading companion.
class ReadingTemplateStore {
  static const _key = 'reading_companion.template';

  // ---------- Prompt templates (loaded from bundled assets) ----------

  static final Map<ReadingCategory, String> _promptCache = {};

  /// Load a prompt template from the bundled assets directory.
  /// Returns the raw template text (Role + Task + Constraints + Format).
  static Future<String> loadPromptTemplate(ReadingCategory category) async {
    if (category == ReadingCategory.auto) {
      category = ReadingCategory.scienceTech;
    }
    final cached = _promptCache[category];
    if (cached != null) return cached;

    final assetFile = category.assetFile;
    if (assetFile.isEmpty) return '';
    final text = await rootBundle.loadString('assets/reading/$assetFile');
    _promptCache[category] = text;
    return text;
  }

  /// Extract the prompt portion (Role + Task + Constraints) from a template,
  /// stripping the `# Format` section which is only used for output rendering.
  static String extractPromptPart(String template) {
    final idx = template.indexOf('# Format:');
    if (idx < 0) return template.trim();
    return template.substring(0, idx).trim();
  }

  // ---------- Per-category output templates ----------

  /// Markdown output templates keyed by category. These match the `# Format`
  /// sections from each prompt template.
  static const outputTemplates = <ReadingCategory, String>{
    ReadingCategory.scienceTech: '''## {{title}}
{{author_line}}

## 内容摘要
{{summary}}

## 深度语义总结
{{paragraph_summaries}}

## 我的笔记
''',
    ReadingCategory.currentAffairs: '''## {{title}}
{{author_line}}

## 事件速递
{{summary}}

## 深度研判总结
{{paragraph_summaries}}

## 我的笔记
''',
    ReadingCategory.fictionStory: '''## {{title}}
{{author_line}}

## 故事梗概
{{summary}}

## 情节深度拆解
{{paragraph_summaries}}

## 我的笔记
''',
    ReadingCategory.financeBusiness: '''## {{title}}
{{author_line}}

## 核心观点摘要
{{summary}}

## 商业逻辑总结
{{paragraph_summaries}}

## 我的笔记
''',
    ReadingCategory.methodologyTutorials: '''## {{title}}
{{author_line}}

## 方案核心摘要
{{summary}}

## 行动清单总结
{{paragraph_summaries}}

## 我的笔记
''',
  };

  /// Get the output template for a category. Falls back to scienceTech.
  static String getOutputTemplate(ReadingCategory category) {
    return outputTemplates[category] ?? outputTemplates[ReadingCategory.scienceTech]!;
  }

  // ---------- User-customizable template (legacy, kept for compat) ----------

  static const defaultTemplate = '''## {{title}}
{{author_line}}

## 内容摘要
{{summary}}

## 深度语义总结
{{paragraph_summaries}}

## 我的笔记
''';

  static Future<String> loadTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? defaultTemplate;
  }

  static Future<void> saveTemplate(String template) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, template);
  }

  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
