/**
 * CustomSkinManager
 * Manages official preset avatar skins (Cat, Kun, Mario, Messi).
 * Note: Mobile Avatar Creator is currently suspended/not supported; only preset skins are provided.
 */

import { common } from '@kit.AbilityKit';

export interface SkinItem {
  id: string;              // 'cat' | 'kun' | 'mario' | 'messi'
  name: string;            // Display title
  subtitle: string;        // Short style description
  isBuiltin: boolean;      // Always true for preset skins
  rawfileName?: string;    // E.g. 'kun-spritesheet.webp'
  victoryQuote?: string;   // Optional completion voice/bubble quote
  createdAt: number;       // Display order index
}

export class CustomSkinManager {
  private static instance: CustomSkinManager | null = null;

  private constructor() {}

  public static getInstance(): CustomSkinManager {
    if (!CustomSkinManager.instance) {
      CustomSkinManager.instance = new CustomSkinManager();
    }
    return CustomSkinManager.instance;
  }

  public init(_context: common.Context): void {
    // Retained for interface compatibility with EntryAbility & SkillsTab
  }

  /**
   * Returns list of all official preset skins (Cat, Kun, Mario, Messi).
   */
  public getAllSkins(): SkinItem[] {
    return [
      {
        id: 'cat',
        name: 'Cat (像素小猫)',
        subtitle: '经典元气橘猫 HD像素',
        isBuiltin: true,
        rawfileName: 'cat-spritesheet.webp',
        victoryQuote: '喵~ 任务搞定啦！',
        createdAt: 0
      },
      {
        id: 'kun',
        name: 'Kun (小黄鸡)',
        subtitle: '经典高密度像素鸡伴侣',
        isBuiltin: true,
        rawfileName: 'kun-spritesheet.webp',
        victoryQuote: '完成啦！你干嘛~哎哟',
        createdAt: 1
      },
      {
        id: 'mario',
        name: 'Mario (马里奥)',
        subtitle: '任天堂经典水管工 HD像素',
        isBuiltin: true,
        rawfileName: 'mario-spritesheet.webp',
        victoryQuote: 'Here we go! 任务搞定！',
        createdAt: 2
      },
      {
        id: 'messi',
        name: 'Messi (球王梅西)',
        subtitle: '阿根廷10号队长 HD像素',
        isBuiltin: true,
        rawfileName: 'messi-spritesheet.webp',
        victoryQuote: 'Vamos! 胜利完成！',
        createdAt: 3
      }
    ];
  }

  public getSkinById(id: string): SkinItem | undefined {
    const all = this.getAllSkins();
    return all.find(item => item.id === id);
  }
}

