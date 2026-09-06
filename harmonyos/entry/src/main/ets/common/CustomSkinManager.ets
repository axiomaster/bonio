/**
 * CustomSkinManager
 * Manages built-in and user-created custom pixel skins.
 * Stores custom skins in application sandbox: <filesDir>/avatar_skins/<skin_id>/
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x3D00;
const TAG = 'CustomSkinManager';

export interface SkinItem {
  id: string;              // 'cat' | 'kun' | 'mario' | 'messi' | 'custom_<timestamp>'
  name: string;            // Display title
  subtitle: string;        // Short style description
  isBuiltin: boolean;      // True if stored in 
  rawfileName?: string;    // E.g. 'mario-spritesheet.webp'
  fileUri?: string;        // E.g. 'file:///data/storage/el2/base/haps/entry/files/avatar_skins/custom_xxx/spritesheet.png'
  victoryQuote?: string;   // Optional completion voice/bubble quote
  createdAt: number;       // Creation timestamp
}

export class CustomSkinManager {
  private static instance: CustomSkinManager | null = null;
  private context: common.Context | null = null;
  private skinsDir: string = '';

  private constructor() {}

  public static getInstance(): CustomSkinManager {
    if (!CustomSkinManager.instance) {
      CustomSkinManager.instance = new CustomSkinManager();
    }
    return CustomSkinManager.instance;
  }

  public init(context: common.Context): void {
    this.context = context;
    try {
      this.skinsDir = context.filesDir + '/avatar_skins';
      if (!fs.accessSync(this.skinsDir)) {
        fs.mkdirSync(this.skinsDir);
        hilog.info(DOMAIN, TAG, 'Created avatar_skins dir: %{public}s', this.skinsDir);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to init skinsDir: %{public}s', String(err));
    }
  }

  /**
   * Returns list of all available skins (built-in + user-generated).
   */
  public getAllSkins(): SkinItem[] {
    const builtinSkins: SkinItem[] = [
      {
        id: 'cat',
        name: 'Cat (小猫)',
        subtitle: 'Lottie 矢量动效猫咪',
        isBuiltin: true,
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

    const customSkins = this.loadCustomSkins();
    return builtinSkins.concat(customSkins);
  }

  public getSkinById(id: string): SkinItem | undefined {
    const all = this.getAllSkins();
    return all.find(item => item.id === id);
  }

  /**
   * Load custom skins persisted in sandbox.
   */
  public loadCustomSkins(): SkinItem[] {
    if (!this.skinsDir) return [];
    try {
      const indexPath = this.skinsDir + '/index.json';
      if (!fs.accessSync(indexPath)) {
        return [];
      }
      const file = fs.openSync(indexPath, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file.fd);

      const decoder = new util.TextDecoder('utf-8');
      const jsonStr = decoder.decode(new Uint8Array(buf));
      const list = JSON.parse(jsonStr) as SkinItem[];
      return list || [];
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to load custom skins index: %{public}s', String(err));
      return [];
    }
  }

  /**
   * Register a newly created skin from local image buffer or copied file.
   */
  public async saveCustomSkin(name: string, subtitle: string, imageBuffer: ArrayBuffer, victoryQuote?: string): Promise<SkinItem> {
    if (!this.skinsDir && this.context) {
      this.init(this.context);
    }
    const timestamp = Date.now();
    const skinId = 'custom_' + timestamp;
    const skinFolder = this.skinsDir + '/' + skinId;
    if (!fs.accessSync(skinFolder)) {
      fs.mkdirSync(skinFolder);
    }

    const imagePath = skinFolder + '/spritesheet.png';
    const imgFile = fs.openSync(imagePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    fs.writeSync(imgFile.fd, imageBuffer);
    fs.closeSync(imgFile.fd);

    const fileUri = 'file://' + imagePath;
    const newSkin: SkinItem = {
      id: skinId,
      name: name.trim() || ('自定义皮肤 ' + skinId.slice(-4)),
      subtitle: subtitle.trim() || 'AI 皮肤工厂创作',
      isBuiltin: false,
      fileUri: fileUri,
      victoryQuote: victoryQuote || '任务搞定啦！',
      createdAt: timestamp
    };

    // Update index.json
    const existing = this.loadCustomSkins();
    existing.unshift(newSkin);
    this.saveIndex(existing);

    hilog.info(DOMAIN, TAG, 'Custom skin saved: %{public}s -> %{public}s', skinId, fileUri);
    return newSkin;
  }

  /**
   * Delete a custom skin.
   */
  public deleteCustomSkin(skinId: string): boolean {
    if (!skinId.startsWith('custom_') || !this.skinsDir) return false;
    try {
      const skinFolder = this.skinsDir + '/' + skinId;
      if (fs.accessSync(skinFolder)) {
        // Remove files
        const imgPath = skinFolder + '/spritesheet.png';
        if (fs.accessSync(imgPath)) fs.unlinkSync(imgPath);
        fs.rmdirSync(skinFolder);
      }
      const existing = this.loadCustomSkins().filter(s => s.id !== skinId);
      this.saveIndex(existing);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to delete custom skin %{public}s: %{public}s', skinId, String(err));
      return false;
    }
  }

  private saveIndex(skins: SkinItem[]): void {
    if (!this.skinsDir) return;
    try {
      const indexPath = this.skinsDir + '/index.json';
      const jsonStr = JSON.stringify(skins);
      const encoder = new util.TextEncoder();
      const bytes = encoder.encodeInto(jsonStr);
      const file = fs.openSync(indexPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, bytes.buffer);
      fs.closeSync(file.fd);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save skins index: %{public}s', String(err));
    }
  }
}
