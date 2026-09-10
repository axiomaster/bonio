import hilog from '@ohos.hilog';

export interface Point2D {
  x: number;
  y: number;
}

export interface CompBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
  centerX: number;
  centerY: number;
  width: number;
  height: number;
}

export interface ResolvedPoints {
  inputPoint?: Point2D;
  sendPoint?: Point2D;
}

/**
 * Parses MSDP OnscreenAwareness uiTree structure to dynamically locate
 * the chat input edit box and send button without requiring slow layout dumps.
 */
export class UiTreeParser {
  private static readonly DOMAIN = 0x3D00;
  private static readonly TAG = 'UiTreeParser';

  private static readonly INPUT_TYPES = [
    'RichEditor',
    'TextInput',
    'TextArea',
    'Search',
    'EditText'
  ];

  /**
   * Parses the bounding box of a component across various format variations
   * (8-point bbox, 4-point bbox, bounds string, rect object, top/left properties).
   */
  public static parseCompBounds(comp: Record<string, Object>): CompBounds | null {
    let left = -1;
    let top = -1;
    let right = -1;
    let bottom = -1;

    // 1. Check bbox array: [x1, y1, x2, y2, x3, y3, x4, y4] (8-point polygon) or [x1, y1, x2, y2]
    const bbox = comp['bbox'];
    if (Array.isArray(bbox) && bbox.length >= 4) {
      const nums: number[] = [];
      for (const item of bbox as Object[]) {
        if (typeof item === 'number' && Number.isFinite(item)) {
          nums.push(item as number);
        }
      }
      if (nums.length >= 8) {
        const xs = [nums[0], nums[2], nums[4], nums[6]];
        const ys = [nums[1], nums[3], nums[5], nums[7]];
        left = Math.min(...xs);
        right = Math.max(...xs);
        top = Math.min(...ys);
        bottom = Math.max(...ys);
      } else if (nums.length >= 4) {
        left = nums[0];
        top = nums[1];
        right = nums[2];
        bottom = nums[3];
      }
    }

    // 2. Check bounds string: "[x1, y1][x2, y2]" or "[x1,y1,x2,y2]"
    if (left < 0 && typeof comp['bounds'] === 'string') {
      const boundsStr = comp['bounds'] as string;
      const m = boundsStr.match(/\[(\d+),\s*(\d+)\]\[(\d+),\s*(\d+)\]/);
      if (m) {
        left = parseInt(m[1], 10);
        top = parseInt(m[2], 10);
        right = parseInt(m[3], 10);
        bottom = parseInt(m[4], 10);
      }
    }

    // 3. Check rect object: { left, top, width, height } or { x, y, width, height }
    if (left < 0 && typeof comp['rect'] === 'object' && comp['rect'] !== null) {
      const r = comp['rect'] as Record<string, Object>;
      const l = typeof r['left'] === 'number' ? (r['left'] as number) : (typeof r['x'] === 'number' ? (r['x'] as number) : -1);
      const t = typeof r['top'] === 'number' ? (r['top'] as number) : (typeof r['y'] === 'number' ? (r['y'] as number) : -1);
      const w = typeof r['width'] === 'number' ? (r['width'] as number) : (typeof r['w'] === 'number' ? (r['w'] as number) : 0);
      const h = typeof r['height'] === 'number' ? (r['height'] as number) : (typeof r['h'] === 'number' ? (r['h'] as number) : 0);
      if (l >= 0 && t >= 0 && w > 0 && h > 0) {
        left = l;
        top = t;
        right = l + w;
        bottom = t + h;
      }
    }

    // 4. Check direct top/left/width/height properties
    if (left < 0) {
      const l = typeof comp['left'] === 'number' ? (comp['left'] as number) : (typeof comp['x'] === 'number' ? (comp['x'] as number) : -1);
      const t = typeof comp['top'] === 'number' ? (comp['top'] as number) : (typeof comp['y'] === 'number' ? (comp['y'] as number) : -1);
      const w = typeof comp['width'] === 'number' ? (comp['width'] as number) : (typeof comp['w'] === 'number' ? (comp['w'] as number) : 0);
      const h = typeof comp['height'] === 'number' ? (comp['height'] as number) : (typeof comp['h'] === 'number' ? (comp['h'] as number) : 0);
      if (l >= 0 && t >= 0 && w > 0 && h > 0) {
        left = l;
        top = t;
        right = l + w;
        bottom = t + h;
      }
    }

    if (left >= 0 && top >= 0 && right > left && bottom > top) {
      return {
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        centerX: Math.round((left + right) / 2),
        centerY: Math.round((top + bottom) / 2),
        width: right - left,
        height: bottom - top
      };
    }
    return null;
  }

  /**
   * Extract all component records from the MSDP snapshot payload.
   */
  public static extractComponents(payloadJson: string): Record<string, Object>[] {
    if (!payloadJson || !payloadJson.trim()) return [];
    try {
      const parsed = JSON.parse(payloadJson) as Record<string, Object>;

      // 1. Check MSDP OnscreenAwarenessInfo items -> itemInfo -> uiTree
      const items = parsed['items'];
      if (Array.isArray(items)) {
        for (const it of items as Object[]) {
          if (typeof it !== 'object' || it === null) continue;
          const itObj = it as Record<string, Object>;
          const info = itObj['itemInfo'] as Record<string, Object> | undefined;
          const uiTreeVal = info?.['uiTree'];
          if (uiTreeVal) {
            let tree: Record<string, Object> | undefined = undefined;
            if (typeof uiTreeVal === 'string' && uiTreeVal.trim()) {
              try {
                tree = JSON.parse(uiTreeVal) as Record<string, Object>;
              } catch (_) {}
            } else if (typeof uiTreeVal === 'object') {
              tree = uiTreeVal as Record<string, Object>;
            }
            if (tree) {
              const comps = tree['components'] || tree['componments'];
              if (Array.isArray(comps) && comps.length > 0) {
                return UiTreeParser.toRecordList(comps as Object[]);
              }
            }
          }
        }
      }

      // 2. Direct uiTree property
      const directUiTree = parsed['uiTree'];
      if (directUiTree) {
        let tree: Record<string, Object> | undefined = undefined;
        if (typeof directUiTree === 'string' && directUiTree.trim()) {
          try {
            tree = JSON.parse(directUiTree) as Record<string, Object>;
          } catch (_) {}
        } else if (typeof directUiTree === 'object') {
          tree = directUiTree as Record<string, Object>;
        }
        if (tree) {
          const comps = tree['components'] || tree['componments'];
          if (Array.isArray(comps) && comps.length > 0) {
            return UiTreeParser.toRecordList(comps as Object[]);
          }
        }
      }

      // 3. Direct components property
      if (Array.isArray(parsed['components'])) {
        return UiTreeParser.toRecordList(parsed['components'] as Object[]);
      }
    } catch (e) {
      hilog.warn(UiTreeParser.DOMAIN, UiTreeParser.TAG, 'extractComponents JSON parse error: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
    return [];
  }

  private static toRecordList(items: Object[]): Record<string, Object>[] {
    const res: Record<string, Object>[] = [];
    for (const item of items) {
      if (typeof item === 'object' && item !== null) {
        res.push(item as Record<string, Object>);
      }
    }
    return res;
  }

  /**
   * Resolves input box and send button coordinates dynamically from the MSDP snapshot payload.
   */
  public static resolveUiTreePoints(payloadJson: string): ResolvedPoints {
    const components = UiTreeParser.extractComponents(payloadJson);
    if (components.length === 0) {
      hilog.info(UiTreeParser.DOMAIN, UiTreeParser.TAG, 'no components found in MSDP payload');
      return {};
    }

    // Step 1: Locate input edit box
    let bestInputBounds: CompBounds | null = null;
    let bestInputComp: Record<string, Object> | null = null;

    for (const comp of components) {
      const type = typeof comp['type'] === 'string' ? (comp['type'] as string) : '';
      const b = UiTreeParser.parseCompBounds(comp);
      if (!b) continue;

      const content = typeof comp['content'] === 'string' ? (comp['content'] as string) : '';
      const desc = typeof comp['description'] === 'string' ? (comp['description'] as string) : '';

      const isInputType = UiTreeParser.INPUT_TYPES.includes(type);
      const isInputDesc = /(输入|发送消息|说点什么|chat|message|input)/i.test(content) ||
                          /(输入|发送消息|说点什么|chat|message|input)/i.test(desc);

      // Input box must have reasonable width/height and sit in the lower area of the screen
      if ((isInputType || isInputDesc) && b.width >= 100 && b.height >= 20 && b.centerY > 300) {
        if (!bestInputBounds || b.centerY > bestInputBounds.centerY) {
          bestInputBounds = b;
          bestInputComp = comp;
        }
      }
    }

    if (!bestInputBounds) {
      hilog.info(UiTreeParser.DOMAIN, UiTreeParser.TAG, 'no input box found in components');
      return {};
    }

    const inputPoint: Point2D = {
      x: bestInputBounds.centerX,
      y: bestInputBounds.centerY
    };

    // Step 2: Locate send button
    let sendBounds: CompBounds | null = null;

    // Strategy 2A: Explicit send text / description
    const isSendText = (v: string): boolean => /^(发送|send|发送消息|点击发送)$/i.test(v.trim());
    for (const comp of components) {
      const content = typeof comp['content'] === 'string' ? (comp['content'] as string) : '';
      const desc = typeof comp['description'] === 'string' ? (comp['description'] as string) : '';
      if (isSendText(content) || isSendText(desc)) {
        const b = UiTreeParser.parseCompBounds(comp);
        if (b && b.centerY > 300) {
          sendBounds = b;
          break;
        }
      }
    }

    // Strategy 2B: Rightmost action button in the same bottom bar as the input box
    if (!sendBounds) {
      const inB = bestInputBounds;
      let rightmost: CompBounds | null = null;
      for (const comp of components) {
        const b = UiTreeParser.parseCompBounds(comp);
        if (!b) continue;
        // Ignore huge containers / full screen overlays
        if (b.width > 300 || b.height > 300) continue;
        if (b.width < 15 || b.height < 15) continue;
        // Must be located to the right of the input box
        if (b.left < inB.right - 40) continue;
        // Vertically aligned with the input box row (+/- 60px)
        if (Math.abs(b.centerY - inB.centerY) <= 60) {
          if (!rightmost || b.centerX > rightmost.centerX) {
            rightmost = b;
          }
        }
      }
      if (rightmost) {
        sendBounds = rightmost;
      }
    }

    let sendPoint: Point2D | undefined = undefined;
    if (sendBounds) {
      sendPoint = {
        x: sendBounds.centerX,
        y: sendBounds.centerY
      };
    }

    hilog.info(UiTreeParser.DOMAIN, UiTreeParser.TAG,
      'resolveUiTreePoints: inputPoint=(%{public}d, %{public}d), sendPoint=(%{public}d, %{public}d)',
      inputPoint.x, inputPoint.y, sendPoint ? sendPoint.x : -1, sendPoint ? sendPoint.y : -1);

    const result: ResolvedPoints = {
      inputPoint: inputPoint,
      sendPoint: sendPoint
    };
    return result;
  }
}
