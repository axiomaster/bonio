import 'plugin_interface.dart';
import 'plugin_manifest.dart';

class NoteCapturePlugin implements BonioPlugin {
  @override
  PluginManifest get manifest => PluginManifest(
        id: 'builtin_note_capture',
        name: const I18nString(zh: '记一记', en: 'Quick Note'),
        version: '1.0.0',
        description: const I18nString(
            zh: '截取当前窗口并生成笔记',
            en: 'Capture current window and create a note'),
        author: 'Bonio',
        type: PluginType.builtin,
        menu: PluginMenuConfig(
          label: const I18nString(zh: '记一记', en: 'Quick Note'),
          icon: 'note_add',
          order: 10,
          requiresContext: MenuContextRequirement.anyWindow,
        ),
      );

  @override
  Future<void> activate() async {}
  @override
  Future<void> deactivate() async {}
  @override
  Future<void> onMenuAction(PluginMenuContext context) async {}
}

class AiLensPlugin implements BonioPlugin {
  @override
  PluginManifest get manifest => PluginManifest(
        id: 'builtin_ai_lens',
        name: const I18nString(zh: '圈一圈', en: 'AI Lens'),
        version: '1.0.0',
        description: const I18nString(
            zh: '在当前窗口上圈选区域进行AI分析',
            en: 'Annotate a region on the current window for AI analysis'),
        author: 'Bonio',
        type: PluginType.builtin,
        menu: PluginMenuConfig(
          label: const I18nString(zh: '圈一圈', en: 'AI Lens'),
          icon: 'crop',
          order: 20,
          requiresContext: MenuContextRequirement.anyWindow,
        ),
      );

  @override
  Future<void> activate() async {}
  @override
  Future<void> deactivate() async {}
  @override
  Future<void> onMenuAction(PluginMenuContext context) async {}
}

class SearchSimilarPlugin implements BonioPlugin {
  @override
  PluginManifest get manifest => PluginManifest(
        id: 'builtin_search_similar',
        name: const I18nString(zh: '搜同款', en: 'Search Similar'),
        version: '1.0.0',
        description: const I18nString(
            zh: '圈选图片区域搜索相似商品',
            en: 'Select a region to search for similar products'),
        author: 'Bonio',
        type: PluginType.builtin,
        menu: PluginMenuConfig(
          label: const I18nString(zh: '搜同款', en: 'Search Similar'),
          icon: 'image_search',
          order: 30,
          requiresContext: MenuContextRequirement.anyWindow,
        ),
      );

  @override
  Future<void> activate() async {}
  @override
  Future<void> deactivate() async {}
  @override
  Future<void> onMenuAction(PluginMenuContext context) async {}
}

class ReadingCompanionPlugin implements BonioPlugin {
  @override
  PluginManifest get manifest => PluginManifest(
        id: 'builtin_reading_companion',
        name: const I18nString(zh: '阅读搭子', en: 'Reading Companion'),
        version: '1.0.0',
        description: const I18nString(
            zh: '提取浏览器页面内容并生成阅读摘要',
            en: 'Extract browser page content and generate reading summary'),
        author: 'Bonio',
        type: PluginType.builtin,
        menu: PluginMenuConfig(
          label: const I18nString(zh: '阅读搭子', en: 'Reading Companion'),
          icon: 'auto_stories',
          order: 40,
          requiresContext: MenuContextRequirement.browserWindow,
        ),
      );

  @override
  Future<void> activate() async {}
  @override
  Future<void> deactivate() async {}
  @override
  Future<void> onMenuAction(PluginMenuContext context) async {}
}
