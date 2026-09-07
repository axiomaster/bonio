/**
 * PixelArtEngine
 * Real client-side pixel art processing engine for Bonio Avatar.
 * Converts user photos into high-contrast, quantized, outlined pixel art sprites.
 */

import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x3D00;
const TAG = 'PixelArtEngine';

export const FRAME_WIDTH = 192;
export const FRAME_HEIGHT = 208;

export interface PixelStyleConfig {
  gridSize: number;       // 32 (Retro), 48 (Classic), 64 (HD)
  colorLevels: number;    // 4, 8, 16 color quantization steps
  enableOutline: boolean; // Add 1px dark edge
  removeBg: boolean;      // Auto-detect & remove solid/corner background
  bgTolerance: number;    // Background color distance threshold (0-100)
}

export const DEFAULT_PIXEL_STYLE: PixelStyleConfig = {
  gridSize: 48,
  colorLevels: 8,
  enableOutline: true,
  removeBg: true,
  bgTolerance: 36
};

export interface PixelArtResult {
  basePixelMap: image.PixelMap;
  rgbaBuffer: ArrayBuffer;
  width: number;
  height: number;
}

export class PixelArtEngine {
  /**
   * Process a local image URI into a standard 192x208 pixel-art character sprite.
   */
  public static async processImage(imageUri: string, config: PixelStyleConfig = DEFAULT_PIXEL_STYLE): Promise<PixelArtResult> {
    try {
      hilog.info(DOMAIN, TAG, 'Processing image from uri: %{public}s', imageUri);

      // 1. Read file into buffer
      const file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const fileBuf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, fileBuf);
      fs.closeSync(file.fd);

      // 2. Decode original image
      const imageSource = image.createImageSource(fileBuf);
      const imgInfo = await imageSource.getImageInfo();
      const origW = imgInfo.size.width;
      const origH = imgInfo.size.height;

      // 3. Downscale decoding directly to a manageable resolution (e.g. 256x256 max)
      const scale = Math.min(256 / origW, 256 / origH);
      const decodeW = Math.max(32, Math.round(origW * scale));
      const decodeH = Math.max(32, Math.round(origH * scale));

      const decodingOpts: image.DecodingOptions = {
        desiredSize: { width: decodeW, height: decodeH }
      };
      const decodedMap = await imageSource.createPixelMap(decodingOpts);
      const numBytes = decodedMap.getPixelBytesNumber();
      const decodeBuf = new ArrayBuffer(numBytes);
      await decodedMap.readPixelsToBuffer(decodeBuf);
      decodedMap.release();
      imageSource.release();

      const srcRgba = new Uint8Array(decodeBuf);

      // 5. Downsample to target pixel grid (gridSize x gridSize * (208/192))
      const gridW = config.gridSize;
      const gridH = Math.round(config.gridSize * (FRAME_HEIGHT / FRAME_WIDTH));
      const gridRgba = new Uint8Array(gridW * gridH * 4);

      for (let gy = 0; gy < gridH; gy++) {
        for (let gx = 0; gx < gridW; gx++) {
          const srcX = Math.min(decodeW - 1, Math.floor(gx * decodeW / gridW));
          const srcY = Math.min(decodeH - 1, Math.floor(gy * decodeH / gridH));
          const srcIdx = (srcY * decodeW + srcX) * 4;

          const gridIdx = (gy * gridW + gx) * 4;
          gridRgba[gridIdx] = srcRgba[srcIdx];
          gridRgba[gridIdx + 1] = srcRgba[srcIdx + 1];
          gridRgba[gridIdx + 2] = srcRgba[srcIdx + 2];
          gridRgba[gridIdx + 3] = srcRgba[srcIdx + 3];
        }
      }

      // 6. Perimeter BFS Flood Fill Background Segmentation
      if (config.removeBg) {
        const isBg = new Uint8Array(gridW * gridH);
        const queue: number[] = [];

        // Seed 4 outer borders
        for (let gx = 0; gx < gridW; gx++) {
          queue.push(gx);
          isBg[gx] = 1;
          const bIdx = (gridH - 1) * gridW + gx;
          queue.push(bIdx);
          isBg[bIdx] = 1;
        }
        for (let gy = 1; gy < gridH - 1; gy++) {
          const lIdx = gy * gridW;
          queue.push(lIdx);
          isBg[lIdx] = 1;
          const rIdx = gy * gridW + (gridW - 1);
          queue.push(rIdx);
          isBg[rIdx] = 1;
        }

        let head = 0;
        while (head < queue.length) {
          const currIdx = queue[head++];
          const cx = currIdx % gridW;
          const cy = Math.floor(currIdx / gridW);
          const cRgbaIdx = currIdx * 4;
          const cr = gridRgba[cRgbaIdx];
          const cg = gridRgba[cRgbaIdx + 1];
          const cb = gridRgba[cRgbaIdx + 2];

          const neighbors: number[][] = [
            [cx - 1, cy],
            [cx + 1, cy],
            [cx, cy - 1],
            [cx, cy + 1]
          ];

          for (let i = 0; i < 4; i++) {
            const nx = neighbors[i][0];
            const ny = neighbors[i][1];
            if (nx < 0 || nx >= gridW || ny < 0 || ny >= gridH) continue;
            const nIdx = ny * gridW + nx;
            if (isBg[nIdx]) continue;

            const nRgbaIdx = nIdx * 4;
            const nr = gridRgba[nRgbaIdx];
            const ng = gridRgba[nRgbaIdx + 1];
            const nb = gridRgba[nRgbaIdx + 2];

            const diff = Math.sqrt(
              Math.pow(cr - nr, 2) + Math.pow(cg - ng, 2) + Math.pow(cb - nb, 2)
            );

            // Relaxed on borders, conservative near central subject
            const isSubjectCore = (nx >= gridW * 0.22 && nx <= gridW * 0.78 && ny >= gridH * 0.15 && ny <= gridH * 0.85);
            const maxDiff = isSubjectCore ? 28 : 45;

            if (diff <= maxDiff) {
              isBg[nIdx] = 1;
              queue.push(nIdx);
            }
          }
        }

        // Clear alpha for background
        for (let i = 0; i < gridW * gridH; i++) {
          if (isBg[i] === 1) {
            gridRgba[i * 4 + 3] = 0;
          }
        }

        // Morphological speckle cleanup: remove isolated 1-pixel noise
        for (let gy = 0; gy < gridH; gy++) {
          for (let gx = 0; gx < gridW; gx++) {
            const idx = (gy * gridW + gx) * 4;
            if (gridRgba[idx + 3] > 0) {
              let fgNeighbors = 0;
              if (gx > 0 && gridRgba[(gy * gridW + gx - 1) * 4 + 3] > 0) fgNeighbors++;
              if (gx < gridW - 1 && gridRgba[(gy * gridW + gx + 1) * 4 + 3] > 0) fgNeighbors++;
              if (gy > 0 && gridRgba[((gy - 1) * gridW + gx) * 4 + 3] > 0) fgNeighbors++;
              if (gy < gridH - 1 && gridRgba[((gy + 1) * gridW + gx) * 4 + 3] > 0) fgNeighbors++;
              if (fgNeighbors === 0) {
                gridRgba[idx + 3] = 0;
              }
            }
          }
        }
      }

      // 7. Palette Color Quantization
      const colorStep = Math.max(1, Math.round(255 / config.colorLevels));
      for (let i = 0; i < gridW * gridH; i++) {
        const idx = i * 4;
        if (gridRgba[idx + 3] > 30) {
          gridRgba[idx] = Math.min(255, Math.round(gridRgba[idx] / colorStep) * colorStep);
          gridRgba[idx + 1] = Math.min(255, Math.round(gridRgba[idx + 1] / colorStep) * colorStep);
          gridRgba[idx + 2] = Math.min(255, Math.round(gridRgba[idx + 2] / colorStep) * colorStep);
          gridRgba[idx + 3] = 255;
        } else {
          gridRgba[idx] = 0;
          gridRgba[idx + 1] = 0;
          gridRgba[idx + 2] = 0;
          gridRgba[idx + 3] = 0;
        }
      }

      // 6. Find bounding box of non-transparent pixels to center the subject
      let minX = gridW, maxX = 0, minY = gridH, maxY = 0;
      let hasPixels = false;
      for (let gy = 0; gy < gridH; gy++) {
        for (let gx = 0; gx < gridW; gx++) {
          const idx = (gy * gridW + gx) * 4;
          if (gridRgba[idx + 3] > 0) {
            hasPixels = true;
            if (gx < minX) minX = gx;
            if (gx > maxX) maxX = gx;
            if (gy < minY) minY = gy;
            if (gy > maxY) maxY = gy;
          }
        }
      }

      if (!hasPixels) {
        minX = 0; maxX = gridW - 1; minY = 0; maxY = gridH - 1;
      }

      const charW = maxX - minX + 1;
      const charH = maxY - minY + 1;

      // 7. Upscale to canonical frame (FRAME_WIDTH x FRAME_HEIGHT = 192 x 208)
      // Fit character centered horizontally, aligned to bottom 92% of frame
      const targetScale = Math.min((FRAME_WIDTH * 0.82) / charW, (FRAME_HEIGHT * 0.86) / charH);
      const finalCharW = Math.round(charW * targetScale);
      const finalCharH = Math.round(charH * targetScale);
      const offsetX = Math.round((FRAME_WIDTH - finalCharW) / 2);
      const offsetY = Math.round(FRAME_HEIGHT * 0.94 - finalCharH);

      const frameRgba = new Uint8Array(FRAME_WIDTH * FRAME_HEIGHT * 4);

      for (let y = 0; y < finalCharH; y++) {
        const gy = minY + Math.floor(y / targetScale);
        if (gy < 0 || gy >= gridH) continue;
        const destY = offsetY + y;
        if (destY < 0 || destY >= FRAME_HEIGHT) continue;

        for (let x = 0; x < finalCharW; x++) {
          const gx = minX + Math.floor(x / targetScale);
          if (gx < 0 || gx >= gridW) continue;
          const destX = offsetX + x;
          if (destX < 0 || destX >= FRAME_WIDTH) continue;

          const gIdx = (gy * gridW + gx) * 4;
          const dIdx = (destY * FRAME_WIDTH + destX) * 4;

          frameRgba[dIdx] = gridRgba[gIdx];
          frameRgba[dIdx + 1] = gridRgba[gIdx + 1];
          frameRgba[dIdx + 2] = gridRgba[gIdx + 2];
          frameRgba[dIdx + 3] = gridRgba[gIdx + 3];
        }
      }

      // 8. 1px Dark Outline (描边强化) for authentic game sprite look
      if (config.enableOutline) {
        const outlinedRgba = new Uint8Array(frameRgba);
        const outlineR = 26, outlineG = 22, outlineB = 30; // Dark charcoal/navy outline

        for (let y = 1; y < FRAME_HEIGHT - 1; y++) {
          for (let x = 1; x < FRAME_WIDTH - 1; x++) {
            const idx = (y * FRAME_WIDTH + x) * 4;
            // If current pixel is transparent
            if (frameRgba[idx + 3] === 0) {
              // Check 4-connected neighbors
              const leftAlpha = frameRgba[(y * FRAME_WIDTH + (x - 1)) * 4 + 3];
              const rightAlpha = frameRgba[(y * FRAME_WIDTH + (x + 1)) * 4 + 3];
              const topAlpha = frameRgba[((y - 1) * FRAME_WIDTH + x) * 4 + 3];
              const bottomAlpha = frameRgba[((y + 1) * FRAME_WIDTH + x) * 4 + 3];

              if (leftAlpha > 100 || rightAlpha > 100 || topAlpha > 100 || bottomAlpha > 100) {
                outlinedRgba[idx] = outlineR;
                outlinedRgba[idx + 1] = outlineG;
                outlinedRgba[idx + 2] = outlineB;
                outlinedRgba[idx + 3] = 255;
              }
            }
          }
        }
        frameRgba.set(outlinedRgba);
      }

      // 9. Create PixelMap
      const initOpts: image.InitializationOptions = {
        size: { width: FRAME_WIDTH, height: FRAME_HEIGHT },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true
      };
      const resultPixelMap = await image.createPixelMap(frameRgba.buffer as ArrayBuffer, initOpts);

      hilog.info(DOMAIN, TAG, 'Pixel art generation successful (%{public}d x %{public}d)', FRAME_WIDTH, FRAME_HEIGHT);

      return {
        basePixelMap: resultPixelMap,
        rgbaBuffer: frameRgba.buffer as ArrayBuffer,
        width: FRAME_WIDTH,
        height: FRAME_HEIGHT
      };
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'PixelArtEngine error: %{public}s', String(err));
      throw new Error(`像素化处理失败: ${String(err)}`);
    }
  }
}
