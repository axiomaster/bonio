import { image } from '@kit.ImageKit';

export interface JpegSizeLimiterResult {
  data: ArrayBuffer;
  width: number;
  height: number;
  quality: number;
}

export class JpegSizeLimiter {
  /**
   * Iteratively compress a JPEG to fit within maxBytes by reducing quality and resolution.
   *
   * @param imageSource - The original image source to compress
   * @param startQuality - Initial JPEG quality (0-100)
   * @param maxBytes - Maximum allowed byte size
   * @param minQuality - Minimum JPEG quality to try (default 20)
   * @param minSize - Minimum dimension size in pixels (default 256)
   * @param scaleStep - Scale factor per resize attempt (default 0.85)
   * @param maxScaleAttempts - Maximum number of downscale passes (default 6)
   * @param maxQualityAttempts - Maximum quality reduction attempts per size (default 6)
   * @returns JpegSizeLimiterResult with compressed data and metadata
   */
  static async compressToLimit(
    imageSource: image.ImageSource,
    startQuality: number,
    maxBytes: number,
    minQuality: number = 20,
    minSize: number = 256,
    scaleStep: number = 0.85,
    maxScaleAttempts: number = 6,
    maxQualityAttempts: number = 6
  ): Promise<JpegSizeLimiterResult> {
    const imgInfo = await imageSource.getImageInfo();
    let width = imgInfo.size.width;
    let height = imgInfo.size.height;

    if (width <= 0 || height <= 0) throw new Error('Invalid image size');
    if (maxBytes <= 0) throw new Error('Invalid maxBytes');

    const clampedStartQuality = Math.max(minQuality, Math.min(100, startQuality));

    // Helper to encode at given dimensions and quality
    const encode = async (w: number, h: number, q: number): Promise<ArrayBuffer> => {
      const packer = image.createImagePacker();
      const opts: image.PackingOption = { format: 'image/jpeg', quality: q };

      // If dimensions differ from original, create a PixelMap at desired size
      if (w !== imgInfo.size.width || h !== imgInfo.size.height) {
        const decodingOpts: image.DecodingOptions = {
          desiredSize: { width: w, height: h }
        };
        const pixelMap = await imageSource.createPixelMap(decodingOpts);
        const result = await packer.packing(pixelMap, opts);
        pixelMap.release();
        return result;
      }
      return await packer.packing(imageSource, opts);
    };

    // Initial attempt
    let bestData = await encode(width, height, clampedStartQuality);
    let best: JpegSizeLimiterResult = {
      data: bestData,
      width: width,
      height: height,
      quality: clampedStartQuality
    };
    if (best.data.byteLength <= maxBytes) return best;

    // Iterative compression
    for (let scaleAttempt = 0; scaleAttempt < maxScaleAttempts; scaleAttempt++) {
      let quality = clampedStartQuality;

      for (let qualAttempt = 0; qualAttempt < maxQualityAttempts; qualAttempt++) {
        const data = await encode(width, height, quality);
        best = { data: data, width: width, height: height, quality: quality };
        if (data.byteLength <= maxBytes) return best;
        if (quality <= minQuality) break;
        quality = Math.max(minQuality, Math.round(quality * 0.75));
      }

      // Downscale
      const minDim = Math.min(width, height);
      const minScale = Math.min(minSize / minDim, 1.0);
      const nextScale = Math.max(scaleStep, minScale);
      const nextWidth = Math.max(minSize, Math.round(width * nextScale));
      const nextHeight = Math.max(minSize, Math.round(height * nextScale));
      if (nextWidth === width && nextHeight === height) break;
      width = Math.min(nextWidth, width);
      height = Math.min(nextHeight, height);
    }

    if (best.data.byteLength > maxBytes) {
      throw new Error(`CAMERA_TOO_LARGE: ${best.data.byteLength} bytes > ${maxBytes} bytes`);
    }

    return best;
  }
}
