/**
 * ActionBindingEngine
 * Synthesizes procedural sprite frames and complete 8x9 SpriteSheet
 * for all 10 Bonio Avatar action states based on a single pixel character sprite.
 */

import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FRAME_WIDTH, FRAME_HEIGHT } from './PixelArtEngine';

const DOMAIN = 0x3D00;
const TAG = 'ActionBindingEngine';

export const SHEET_COLS = 8;
export const SHEET_ROWS = 9;
export const SHEET_WIDTH = SHEET_COLS * FRAME_WIDTH;   // 1536
export const SHEET_HEIGHT = SHEET_ROWS * FRAME_HEIGHT; // 1872

export interface ActionInfo {
  key: string;
  name: string;
  row: number;
  frameCount: number;
  fps: number;
  description: string;
}

export const ACTION_LIST: ActionInfo[] = [
  { key: 'idle', name: '待机呼吸', row: 0, frameCount: 6, fps: 5, description: '轻微呼吸起伏，呆萌眨眼' },
  { key: 'runRight', name: '向右奔跑', row: 1, frameCount: 8, fps: 8, description: '前倾迈步，左右晃动' },
  { key: 'wave', name: '招手互动', row: 3, frameCount: 4, fps: 6, description: '举手致意，欢快跳动' },
  { key: 'jump', name: '庆祝跳跃', row: 4, frameCount: 5, fps: 6, description: '下蹲蓄力，高高弹跳' },
  { key: 'thinking', name: '烧脑思考', row: 8, frameCount: 6, fps: 5, description: '托腮沉思，头顶冒泡' },
  { key: 'working', name: '极速搬砖', row: 7, frameCount: 6, fps: 8, description: '高频冲刺，努力工作中' },
  { key: 'failed', name: '报错沮丧', row: 5, frameCount: 8, fps: 6, description: '沮丧跌坐，冒冷汗' }
];

interface RowDef {
  action: string;
  count: number;
}

export class ActionBindingEngine {
  private baseRgba: Uint8Array;

  constructor(baseBuffer: ArrayBuffer) {
    this.baseRgba = new Uint8Array(baseBuffer);
  }

  /**
   * Apply 2D procedural transformation (shift, stretch, mirror) to base frame.
   */
  private transformFrame(
    shiftX: number = 0,
    shiftY: number = 0,
    scaleY: number = 1.0,
    mirrorX: boolean = false,
    effectType: string = 'none'
  ): Uint8Array {
    const out = new Uint8Array(FRAME_WIDTH * FRAME_HEIGHT * 4);
    const pivotY = FRAME_HEIGHT - 12; // Anchor character near feet

    for (let y = 0; y < FRAME_HEIGHT; y++) {
      // Inverse scale for Y around pivot
      const origY = Math.round(pivotY - (pivotY - y + shiftY) / scaleY);
      if (origY < 0 || origY >= FRAME_HEIGHT) continue;

      for (let x = 0; x < FRAME_WIDTH; x++) {
        let origX = x - shiftX;
        if (mirrorX) {
          origX = FRAME_WIDTH - 1 - origX;
        }
        if (origX < 0 || origX >= FRAME_WIDTH) continue;

        const srcIdx = (origY * FRAME_WIDTH + origX) * 4;
        const destIdx = (y * FRAME_WIDTH + x) * 4;

        let r = this.baseRgba[srcIdx];
        let g = this.baseRgba[srcIdx + 1];
        let b = this.baseRgba[srcIdx + 2];
        let a = this.baseRgba[srcIdx + 3];

        if (a > 0) {
          // Effect: sweating / darkening for failed
          if (effectType === 'darken') {
            r = Math.round(r * 0.75);
            g = Math.round(g * 0.75);
            b = Math.round(b * 0.85 + 25);
          }
          out[destIdx] = r;
          out[destIdx + 1] = g;
          out[destIdx + 2] = b;
          out[destIdx + 3] = a;
        }
      }
    }

    // Effect: Draw decorative pixel elements (sweat, question mark, heart, sparkle)
    if (effectType === 'sweat') {
      // Blue sweat drop near top right of character
      const sx = Math.round(FRAME_WIDTH * 0.72);
      const sy = Math.round(FRAME_HEIGHT * 0.28);
      this.drawPixelDot(out, sx, sy, [92, 172, 238, 255], 3);
      this.drawPixelDot(out, sx - 1, sy - 2, [135, 206, 250, 255], 2);
    } else if (effectType === 'think_dot') {
      // Thinking light / sparkle above head
      const cx = Math.round(FRAME_WIDTH * 0.5);
      const cy = Math.round(FRAME_HEIGHT * 0.12);
      this.drawPixelDot(out, cx, cy, [255, 215, 0, 255], 4);
      this.drawPixelDot(out, cx, cy - 6, [255, 235, 120, 255], 2);
    } else if (effectType === 'jump_dust') {
      // Small dust puff at feet
      const fy = FRAME_HEIGHT - 6;
      this.drawPixelDot(out, 40, fy, [200, 200, 210, 200], 3);
      this.drawPixelDot(out, FRAME_WIDTH - 40, fy, [200, 200, 210, 200], 3);
    }

    return out;
  }

  private drawPixelDot(buf: Uint8Array, cx: number, cy: number, color: number[], radius: number): void {
    for (let dy = -radius; dy <= radius; dy++) {
      for (let dx = -radius; dx <= radius; dx++) {
        if (dx * dx + dy * dy <= radius * radius) {
          const x = cx + dx;
          const y = cy + dy;
          if (x >= 0 && x < FRAME_WIDTH && y >= 0 && y < FRAME_HEIGHT) {
            const idx = (y * FRAME_WIDTH + x) * 4;
            buf[idx] = color[0];
            buf[idx + 1] = color[1];
            buf[idx + 2] = color[2];
            buf[idx + 3] = color[3];
          }
        }
      }
    }
  }

  /**
   * Synthesizes the exact sequence of frames for any of the 10 Bonio avatar states.
   */
  public getFramesForAction(actionKey: string): Uint8Array[] {
    const frames: Uint8Array[] = [];

    switch (actionKey) {
      case 'idle': // Row 0: 6 frames
        frames.push(this.transformFrame(0, 0, 1.0));
        frames.push(this.transformFrame(0, 1, 0.98));
        frames.push(this.transformFrame(0, 2, 0.96)); // exhale squash
        frames.push(this.transformFrame(0, 1, 0.98));
        frames.push(this.transformFrame(0, -1, 1.02)); // inhale peak
        frames.push(this.transformFrame(0, 0, 1.0));
        break;

      case 'runRight': // Row 1: 8 frames
        frames.push(this.transformFrame(2, -2, 1.02)); // step up
        frames.push(this.transformFrame(3, 0, 1.0));
        frames.push(this.transformFrame(2, 2, 0.97)); // foot plant
        frames.push(this.transformFrame(0, 0, 1.0));
        frames.push(this.transformFrame(-2, -2, 1.02)); // other foot
        frames.push(this.transformFrame(-3, 0, 1.0));
        frames.push(this.transformFrame(-2, 2, 0.97));
        frames.push(this.transformFrame(0, 0, 1.0));
        break;

      case 'runLeft': // Row 2: 8 frames (mirrored runRight)
        const rFrames = this.getFramesForAction('runRight');
        for (const rf of rFrames) {
          const mirrored = new Uint8Array(FRAME_WIDTH * FRAME_HEIGHT * 4);
          for (let y = 0; y < FRAME_HEIGHT; y++) {
            for (let x = 0; x < FRAME_WIDTH; x++) {
              const srcIdx = (y * FRAME_WIDTH + (FRAME_WIDTH - 1 - x)) * 4;
              const dstIdx = (y * FRAME_WIDTH + x) * 4;
              mirrored[dstIdx] = rf[srcIdx];
              mirrored[dstIdx + 1] = rf[srcIdx + 1];
              mirrored[dstIdx + 2] = rf[srcIdx + 2];
              mirrored[dstIdx + 3] = rf[srcIdx + 3];
            }
          }
          frames.push(mirrored);
        }
        break;

      case 'wave': // Row 3: 4 frames
        frames.push(this.transformFrame(-2, 0, 1.0));
        frames.push(this.transformFrame(1, -3, 1.03));
        frames.push(this.transformFrame(3, -1, 1.02));
        frames.push(this.transformFrame(0, 1, 0.98));
        break;

      case 'jump': // Row 4: 5 frames
        frames.push(this.transformFrame(0, 4, 0.93)); // crouch squash
        frames.push(this.transformFrame(0, -6, 1.06)); // launch stretch
        frames.push(this.transformFrame(0, -12, 1.04, false, 'jump_dust')); // apex
        frames.push(this.transformFrame(0, -4, 1.0)); // fall
        frames.push(this.transformFrame(0, 3, 0.95)); // landing cushion
        break;

      case 'failed': // Row 5: 8 frames
        frames.push(this.transformFrame(0, 2, 0.97));
        frames.push(this.transformFrame(0, 4, 0.94, false, 'darken'));
        frames.push(this.transformFrame(-2, 5, 0.93, false, 'sweat'));
        frames.push(this.transformFrame(2, 5, 0.93, false, 'sweat'));
        frames.push(this.transformFrame(-1, 5, 0.93, false, 'darken'));
        frames.push(this.transformFrame(1, 5, 0.93, false, 'darken'));
        frames.push(this.transformFrame(0, 6, 0.92, false, 'darken'));
        frames.push(this.transformFrame(0, 4, 0.94, false, 'darken'));
        break;

      case 'waiting': // Row 6: 6 frames
        frames.push(this.transformFrame(0, 0, 1.0));
        frames.push(this.transformFrame(-2, 0, 1.0));
        frames.push(this.transformFrame(-2, 1, 0.99));
        frames.push(this.transformFrame(0, 0, 1.0));
        frames.push(this.transformFrame(2, 0, 1.0));
        frames.push(this.transformFrame(2, 1, 0.99));
        break;

      case 'working': // Row 7: 6 frames
        frames.push(this.transformFrame(2, 2, 0.97));
        frames.push(this.transformFrame(-1, -1, 1.01));
        frames.push(this.transformFrame(3, 1, 0.98));
        frames.push(this.transformFrame(-2, -2, 1.02));
        frames.push(this.transformFrame(2, 2, 0.97));
        frames.push(this.transformFrame(0, 0, 1.0));
        break;

      case 'thinking': // Row 8: 6 frames
        frames.push(this.transformFrame(0, 0, 1.0));
        frames.push(this.transformFrame(2, -1, 1.01, false, 'think_dot'));
        frames.push(this.transformFrame(3, -2, 1.02, false, 'think_dot'));
        frames.push(this.transformFrame(1, 0, 1.0));
        frames.push(this.transformFrame(-2, 1, 0.99));
        frames.push(this.transformFrame(0, 0, 1.0));
        break;

      default:
        frames.push(this.transformFrame());
        break;
    }

    return frames;
  }

  /**
   * Generates PixelMap array for live playback in UI dialog.
   */
  public async getActionPixelMaps(actionKey: string): Promise<image.PixelMap[]> {
    const rawFrames = this.getFramesForAction(actionKey);
    const pixelMaps: image.PixelMap[] = [];

    const initOpts: image.InitializationOptions = {
      size: { width: FRAME_WIDTH, height: FRAME_HEIGHT },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    };

    for (const rf of rawFrames) {
      const pm = await image.createPixelMap(rf.buffer as ArrayBuffer, initOpts);
      pixelMaps.push(pm);
    }

    return pixelMaps;
  }

  /**
   * Compiles all 9 rows x 8 columns = 72 frames into full 1536x1872 SpriteSheet.
   */
  public async buildFullSpriteSheet(): Promise<ArrayBuffer> {
    hilog.info(DOMAIN, TAG, 'Building full 8x9 SpriteSheet (1536 x 1872)...');

    const sheetBuffer = new ArrayBuffer(SHEET_WIDTH * SHEET_HEIGHT * 4);
    const sheetView = new Uint8Array(sheetBuffer);

    // Row definitions corresponding to Bonio 8x9 animation matrix
    const rowMapping: RowDef[] = [
      { action: 'idle', count: 6 },      // Row 0
      { action: 'runRight', count: 8 },  // Row 1
      { action: 'runLeft', count: 8 },   // Row 2
      { action: 'wave', count: 4 },      // Row 3
      { action: 'jump', count: 5 },      // Row 4
      { action: 'failed', count: 8 },    // Row 5
      { action: 'waiting', count: 6 },   // Row 6
      { action: 'working', count: 6 },   // Row 7
      { action: 'thinking', count: 6 }   // Row 8
    ];

    for (let rowIdx = 0; rowIdx < SHEET_ROWS; rowIdx++) {
      const def = rowMapping[rowIdx];
      const frames = this.getFramesForAction(def.action);

      for (let colIdx = 0; colIdx < SHEET_COLS; colIdx++) {
        // Wrap frames if action has fewer than 8 frames (or keep last)
        const frameRgba = frames[colIdx % frames.length];

        // Blit 192x208 frame into sheet at (colIdx * 192, rowIdx * 208)
        const startX = colIdx * FRAME_WIDTH;
        const startY = rowIdx * FRAME_HEIGHT;

        for (let fy = 0; fy < FRAME_HEIGHT; fy++) {
          const sy = startY + fy;
          const sheetRowOffset = sy * SHEET_WIDTH * 4;
          const frameRowOffset = fy * FRAME_WIDTH * 4;

          for (let fx = 0; fx < FRAME_WIDTH; fx++) {
            const sx = startX + fx;
            const destIdx = sheetRowOffset + sx * 4;
            const srcIdx = frameRowOffset + fx * 4;

            sheetView[destIdx] = frameRgba[srcIdx];
            sheetView[destIdx + 1] = frameRgba[srcIdx + 1];
            sheetView[destIdx + 2] = frameRgba[srcIdx + 2];
            sheetView[destIdx + 3] = frameRgba[srcIdx + 3];
          }
        }
      }
    }

    // Create PixelMap of the full 1536x1872 sheet
    const initOpts: image.InitializationOptions = {
      size: { width: SHEET_WIDTH, height: SHEET_HEIGHT },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    };
    const sheetPixelMap = await image.createPixelMap(sheetBuffer, initOpts);

    // Pack into PNG format
    const packer = image.createImagePacker();
    const packOpts: image.PackingOption = {
      format: 'image/png',
      quality: 100
    };
    const pngData = await packer.packing(sheetPixelMap, packOpts);
    sheetPixelMap.release();

    hilog.info(DOMAIN, TAG, 'SpriteSheet packed successfully (%{public}d bytes)', pngData.byteLength);
    return pngData;
  }
}
