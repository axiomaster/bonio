#include "paddle_ocr_wrapper.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

// ---------------------------------------------------------------------------
// ONNX Runtime C API — loaded dynamically from onnxruntime.dll
// ---------------------------------------------------------------------------

#ifdef _WIN32
#define ORT_API_CALL __stdcall
#else
#define ORT_API_CALL
#endif

typedef enum { ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT = 1 } ONNXTensorElementDataType;
typedef enum { ORT_LOGGING_LEVEL_WARNING = 2 } OrtLoggingLevel;
typedef enum { OrtDeviceAllocator = 0, OrtArenaAllocator = 1 } OrtAllocatorType;
typedef enum { OrtMemTypeDefault = 0 } OrtMemType;

struct OrtEnv;
struct OrtSession;
struct OrtSessionOptions;
struct OrtMemoryInfo;
struct OrtValue;
struct OrtRunOptions;
struct OrtStatus;
struct OrtTensorTypeAndShapeInfo;
struct OrtApi;
struct OrtApiBase {
  const OrtApi*(ORT_API_CALL* GetApi)(uint32_t version);
  const char*(ORT_API_CALL* GetVersionString)(void);
};

typedef const OrtApiBase*(ORT_API_CALL* PF_OrtGetApiBase)(void);

typedef OrtStatus*(ORT_API_CALL* PF_CreateEnv)(OrtLoggingLevel, const char*, OrtEnv**);
#ifdef _WIN32
typedef OrtStatus*(ORT_API_CALL* PF_CreateSession)(const OrtEnv*, const wchar_t*, const OrtSessionOptions*, OrtSession**);
#else
typedef OrtStatus*(ORT_API_CALL* PF_CreateSession)(const OrtEnv*, const char*, const OrtSessionOptions*, OrtSession**);
#endif
typedef OrtStatus*(ORT_API_CALL* PF_CreateMemoryInfo)(const char*, OrtAllocatorType, int, OrtMemType, OrtMemoryInfo**);
typedef OrtStatus*(ORT_API_CALL* PF_CreateRunOptions)(OrtRunOptions**);
typedef OrtStatus*(ORT_API_CALL* PF_CreateTensor)(const OrtMemoryInfo*, void*, size_t, const int64_t*, size_t, ONNXTensorElementDataType, OrtValue**);
typedef OrtStatus*(ORT_API_CALL* PF_Run)(OrtSession*, const OrtRunOptions*, const char* const*, const OrtValue* const*, size_t, const char* const*, size_t, OrtValue**);
typedef OrtStatus*(ORT_API_CALL* PF_GetTensorMutableData)(OrtValue*, void**);
typedef OrtStatus*(ORT_API_CALL* PF_GetTensorTypeAndShape)(const OrtValue*, OrtTensorTypeAndShapeInfo**);
typedef OrtStatus*(ORT_API_CALL* PF_GetDimensionsCount)(const OrtTensorTypeAndShapeInfo*, size_t*);
typedef OrtStatus*(ORT_API_CALL* PF_GetDimensions)(const OrtTensorTypeAndShapeInfo*, int64_t*, size_t);
typedef void(ORT_API_CALL* PF_ReleaseEnv)(OrtEnv*);
typedef void(ORT_API_CALL* PF_ReleaseSession)(OrtSession*);
typedef void(ORT_API_CALL* PF_ReleaseMemoryInfo)(OrtMemoryInfo*);
typedef void(ORT_API_CALL* PF_ReleaseValue)(OrtValue*);
typedef void(ORT_API_CALL* PF_ReleaseRunOptions)(OrtRunOptions*);
typedef void(ORT_API_CALL* PF_ReleaseTensorTypeAndShapeInfo)(OrtTensorTypeAndShapeInfo*);
typedef void(ORT_API_CALL* PF_ReleaseStatus)(OrtStatus*);
typedef const char*(ORT_API_CALL* PF_GetErrorMessage)(OrtStatus*);

struct OrtApi {
  void* CreateStatus;
  void* GetErrorCode;
  PF_GetErrorMessage GetErrorMessage;
  PF_CreateEnv CreateEnv;
  void* CreateEnvWithCustomLogger;
  void* EnableTelemetryEvents;
  void* DisableTelemetryEvents;
  PF_CreateSession CreateSession;
  void* CreateSessionFromArray;
  PF_Run Run;
  void* CreateSessionOptions;
  void* SetOptimizedModelFilePath;
  void* CloneSessionOptions;
  void* SetSessionExecutionMode;
  void* EnableProfiling;
  void* DisableProfiling;
  void* EnableMemPattern;
  void* DisableMemPattern;
  void* EnableCpuMemArena;
  void* DisableCpuMemArena;
  void* SetSessionLogId;
  void* SetSessionLogVerbosityLevel;
  void* SetSessionLogSeverityLevel;
  void* SetSessionGraphOptimizationLevel;
  void* SetIntraOpNumThreads;
  void* SetInterOpNumThreads;
  void* CreateCustomOpDomain;
  void* CustomOpDomain_Add;
  void* AddCustomOpDomain;
  void* RegisterCustomOpsLibrary;
  void* SessionGetInputCount;
  void* SessionGetOutputCount;
  void* SessionGetOverridableInitializerCount;
  void* SessionGetInputTypeInfo;
  void* SessionGetOutputTypeInfo;
  void* SessionGetOverridableInitializerTypeInfo;
  void* SessionGetInputName;
  void* SessionGetOutputName;
  void* SessionGetOverridableInitializerName;
  PF_CreateRunOptions CreateRunOptions;
  void* RunOptionsSetRunLogVerbosityLevel;
  void* RunOptionsSetRunLogSeverityLevel;
  void* RunOptionsSetRunTag;
  void* RunOptionsGetRunLogVerbosityLevel;
  void* RunOptionsGetRunLogSeverityLevel;
  void* RunOptionsGetRunTag;
  void* RunOptionsSetTerminate;
  void* RunOptionsUnsetTerminate;
  void* CreateTensorAsOrtValue;
  PF_CreateTensor CreateTensorWithDataAsOrtValue;
  void* IsTensor;
  PF_GetTensorMutableData GetTensorMutableData;
  void* FillStringTensor;
  void* GetStringTensorDataLength;
  void* GetStringTensorContent;
  void* CastTypeInfoToTensorInfo;
  void* GetOnnxTypeFromTypeInfo;
  void* CreateTensorTypeAndShapeInfo;
  void* SetTensorElementType;
  void* SetDimensions;
  void* GetTensorElementType;
  PF_GetDimensionsCount GetDimensionsCount;
  PF_GetDimensions GetDimensions;
  void* GetSymbolicDimensions;
  void* GetTensorShapeElementCount;
  PF_GetTensorTypeAndShape GetTensorTypeAndShape;
  void* GetTypeInfo;
  void* GetValueType;
  PF_CreateMemoryInfo CreateMemoryInfo;
  void* CreateCpuMemoryInfo;
  void* CompareMemoryInfo;
  void* MemoryInfoGetName;
  void* MemoryInfoGetId;
  void* MemoryInfoGetMemType;
  void* MemoryInfoGetType;
  void* AllocatorAlloc;
  void* AllocatorFree;
  void* AllocatorGetInfo;
  void* GetAllocatorWithDefaultOptions;
  void* AddFreeDimensionOverride;
  void* GetValue;
  void* GetValueCount;
  void* CreateValue;
  void* CreateOpaqueValue;
  void* GetOpaqueValue;
  void* KernelInfoGetAttribute_float;
  void* KernelInfoGetAttribute_int64;
  void* KernelInfoGetAttribute_string;
  void* KernelContext_GetInputCount;
  void* KernelContext_GetOutputCount;
  void* KernelContext_GetInput;
  void* KernelContext_GetOutput;
  PF_ReleaseEnv ReleaseEnv;
  PF_ReleaseStatus ReleaseStatus;
  PF_ReleaseMemoryInfo ReleaseMemoryInfo;
  PF_ReleaseSession ReleaseSession;
  PF_ReleaseValue ReleaseValue;
  PF_ReleaseRunOptions ReleaseRunOptions;
  void* ReleaseTypeInfo;
  PF_ReleaseTensorTypeAndShapeInfo ReleaseTensorTypeAndShapeInfo;
};

static PF_CreateEnv f_CreateEnv = nullptr;
static PF_CreateSession f_CreateSession = nullptr;
static PF_CreateMemoryInfo f_CreateMemoryInfo = nullptr;
static PF_CreateRunOptions f_CreateRunOptions = nullptr;
static PF_CreateTensor f_CreateTensor = nullptr;
static PF_Run f_Run = nullptr;
static PF_GetTensorMutableData f_GetTensorMutableData = nullptr;
static PF_GetTensorTypeAndShape f_GetTensorTypeAndShape = nullptr;
static PF_GetDimensionsCount f_GetDimensionsCount = nullptr;
static PF_GetDimensions f_GetDimensions = nullptr;
static PF_ReleaseEnv f_ReleaseEnv = nullptr;
static PF_ReleaseSession f_ReleaseSession = nullptr;
static PF_ReleaseMemoryInfo f_ReleaseMemoryInfo = nullptr;
static PF_ReleaseValue f_ReleaseValue = nullptr;
static PF_ReleaseRunOptions f_ReleaseRunOptions = nullptr;
static PF_ReleaseTensorTypeAndShapeInfo f_ReleaseTensorTypeAndShapeInfo = nullptr;
static PF_ReleaseStatus f_ReleaseStatus = nullptr;
static PF_GetErrorMessage f_GetErrorMessage = nullptr;

static OrtEnv* g_env = nullptr;
static OrtMemoryInfo* g_mem_info = nullptr;
static OrtSession* g_det_session = nullptr;
static OrtSession* g_rec_session = nullptr;
static bool g_initialized = false;
static std::vector<std::string> g_chars;

#ifdef _WIN32
static HMODULE g_ort_dll = nullptr;
#else
static void* g_ort_dll = nullptr;
#endif

static bool load_ort(const char* ort_path) {
#ifdef _WIN32
  int wide_len = MultiByteToWideChar(CP_UTF8, 0, ort_path, -1, nullptr, 0);
  if (wide_len > 0) {
    std::vector<wchar_t> wide(wide_len);
    MultiByteToWideChar(CP_UTF8, 0, ort_path, -1, wide.data(), wide_len);
    g_ort_dll = LoadLibraryW(wide.data());
  }
  if (!g_ort_dll) g_ort_dll = LoadLibraryW(L"onnxruntime.dll");
  if (!g_ort_dll) { fprintf(stderr, "ORT: failed to load onnxruntime.dll\n"); return false; }
#else
  g_ort_dll = dlopen(ort_path, RTLD_LAZY);
  if (!g_ort_dll) g_ort_dll = dlopen("libonnxruntime.so", RTLD_LAZY);
  if (!g_ort_dll) { fprintf(stderr, "ORT: failed to load libonnxruntime.so\n"); return false; }
#endif

#ifdef _WIN32
  PF_OrtGetApiBase get_api_base = (PF_OrtGetApiBase)GetProcAddress(g_ort_dll, "OrtGetApiBase");
#else
  PF_OrtGetApiBase get_api_base = (PF_OrtGetApiBase)dlsym(g_ort_dll, "OrtGetApiBase");
#endif
  if (!get_api_base) { fprintf(stderr, "ORT: missing export OrtGetApiBase\n"); return false; }

  const OrtApiBase* api_base = get_api_base();
  if (!api_base) { fprintf(stderr, "ORT: OrtGetApiBase returned null\n"); return false; }

  const OrtApi* api = nullptr;
  for (uint32_t version = 27; version >= 1; --version) {
    api = api_base->GetApi(version);
    if (api) break;
    if (version == 1) break;
  }
  if (!api) { fprintf(stderr, "ORT: no compatible C API version\n"); return false; }

  f_CreateEnv = api->CreateEnv;
  f_CreateSession = api->CreateSession;
  f_CreateMemoryInfo = api->CreateMemoryInfo;
  f_CreateRunOptions = api->CreateRunOptions;
  f_CreateTensor = api->CreateTensorWithDataAsOrtValue;
  f_Run = api->Run;
  f_GetTensorMutableData = api->GetTensorMutableData;
  f_GetTensorTypeAndShape = api->GetTensorTypeAndShape;
  f_GetDimensionsCount = api->GetDimensionsCount;
  f_GetDimensions = api->GetDimensions;
  f_ReleaseEnv = api->ReleaseEnv;
  f_ReleaseSession = api->ReleaseSession;
  f_ReleaseMemoryInfo = api->ReleaseMemoryInfo;
  f_ReleaseValue = api->ReleaseValue;
  f_ReleaseRunOptions = api->ReleaseRunOptions;
  f_ReleaseTensorTypeAndShapeInfo = api->ReleaseTensorTypeAndShapeInfo;
  f_ReleaseStatus = api->ReleaseStatus;
  f_GetErrorMessage = api->GetErrorMessage;

  if (!f_CreateEnv || !f_CreateSession || !f_CreateMemoryInfo ||
      !f_CreateRunOptions || !f_CreateTensor || !f_Run ||
      !f_GetTensorMutableData || !f_GetTensorTypeAndShape ||
      !f_GetDimensionsCount || !f_GetDimensions || !f_ReleaseEnv || !f_ReleaseSession ||
      !f_ReleaseMemoryInfo || !f_ReleaseValue || !f_ReleaseRunOptions ||
      !f_ReleaseTensorTypeAndShapeInfo ||
      !f_ReleaseStatus || !f_GetErrorMessage) {
    fprintf(stderr, "ORT: compatible C API is missing required functions\n");
    return false;
  }

  OrtStatus* st = f_CreateEnv(ORT_LOGGING_LEVEL_WARNING, "paddle_ocr", &g_env);
  if (st) { fprintf(stderr, "ORT: CreateEnv failed: %s\n", f_GetErrorMessage(st)); f_ReleaseStatus(st); return false; }
  st = f_CreateMemoryInfo("Cpu", OrtDeviceAllocator, 0, OrtMemTypeDefault, &g_mem_info);
  if (st) { fprintf(stderr, "ORT: CreateMemoryInfo failed\n"); f_ReleaseStatus(st); return false; }
  return true;
}

// ---------------------------------------------------------------------------
// Image preprocessing helpers
// ---------------------------------------------------------------------------

/// Resize BGRA image to 3-channel float, normalized to [0,1], CHW layout.
static std::vector<float> preprocess_det(const uint8_t* bgra, int w, int h, int target_w, int target_h) {
  std::vector<float> out(3 * target_h * target_w, 0.0f);
  float scale_x = (float)w / target_w;
  float scale_y = (float)h / target_h;
  for (int y = 0; y < target_h; y++) {
    for (int x = 0; x < target_w; x++) {
      int sx = (int)(x * scale_x);
      int sy = (int)(y * scale_y);
      sx = sx < 0 ? 0 : (sx >= w ? w - 1 : sx);
      sy = sy < 0 ? 0 : (sy >= h ? h - 1 : sy);
      const uint8_t* p = bgra + (sy * w + sx) * 4;
      // Match RapidOCR/PaddleOCR preprocessing:
      // RGB order, scale to [0,1], then normalize by mean/std=0.5.
      out[0 * target_h * target_w + y * target_w + x] = (p[2] / 255.0f - 0.5f) / 0.5f;
      out[1 * target_h * target_w + y * target_w + x] = (p[1] / 255.0f - 0.5f) / 0.5f;
      out[2 * target_h * target_w + y * target_w + x] = (p[0] / 255.0f - 0.5f) / 0.5f;
    }
  }
  return out;
}

static float estimate_border_gray(const uint8_t* bgra, int w, int h,
                                  int x0, int y0, int x1, int y1);

/// Crop a region from BGRA image, resize to recognition model input size,
/// return normalized float CHW data.
static std::vector<float> preprocess_rec(const uint8_t* bgra, int img_w, int img_h,
                                          int x0, int y0, int x1, int y1,
                                          int target_w, int target_h) {
  // Ensure coordinates are within bounds
  x0 = x0 < 0 ? 0 : (x0 >= img_w ? img_w - 1 : x0);
  y0 = y0 < 0 ? 0 : (y0 >= img_h ? img_h - 1 : y0);
  x1 = x1 < 0 ? 0 : (x1 >= img_w ? img_w - 1 : x1);
  y1 = y1 < 0 ? 0 : (y1 >= img_h ? img_h - 1 : y1);
  if (x1 <= x0 || y1 <= y0) {
    return std::vector<float>(3 * target_h * target_w, 0.0f);
  }
  int crop_w = x1 - x0;
  int crop_h = y1 - y0;
  const bool invert_for_dark_background =
      estimate_border_gray(bgra, img_w, img_h, x0, y0, x1, y1) < 128.0f;

  // Compute aspect-ratio-preserving resize
  float ratio = (float)crop_w / crop_h;
  int resized_w, resized_h;
  if (ratio > (float)target_w / target_h) {
    resized_w = target_w;
    resized_h = (int)(target_w / ratio);
  } else {
    resized_h = target_h;
    resized_w = (int)(target_h * ratio);
  }
  if (resized_w < 4) resized_w = 4;
  if (resized_h < 4) resized_h = 4;

  std::vector<float> out(3 * target_h * target_w, 0.0f); // zero-padded
  for (int y = 0; y < resized_h; y++) {
    float fy = (float)y / resized_h * crop_h;
    int sy = y0 + (int)fy;
    if (sy >= img_h) sy = img_h - 1;
    for (int x = 0; x < resized_w; x++) {
      float fx = (float)x / resized_w * crop_w;
      int sx = x0 + (int)fx;
      if (sx >= img_w) sx = img_w - 1;
      const uint8_t* p = bgra + (sy * img_w + sx) * 4;
      float r = (float)p[2];
      float g = (float)p[1];
      float b = (float)p[0];
      if (invert_for_dark_background) {
        r = 255.0f - r;
        g = 255.0f - g;
        b = 255.0f - b;
      }
      out[0 * target_h * target_w + y * target_w + x] = (r / 255.0f - 0.5f) / 0.5f;
      out[1 * target_h * target_w + y * target_w + x] = (g / 255.0f - 0.5f) / 0.5f;
      out[2 * target_h * target_w + y * target_w + x] = (b / 255.0f - 0.5f) / 0.5f;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// DB post-processing: threshold → connected components → boxes
// ---------------------------------------------------------------------------

struct TextBox {
  int x0, y0, x1, y1;
};

static inline uint8_t gray_at(const uint8_t* bgra, int img_w, int x, int y) {
  const uint8_t* p = bgra + (y * img_w + x) * 4;
  const float r = (float)p[2];
  const float g = (float)p[1];
  const float b = (float)p[0];
  return (uint8_t)(0.299f * r + 0.587f * g + 0.114f * b);
}

static float estimate_border_gray(const uint8_t* bgra, int w, int h,
                                  int x0, int y0, int x1, int y1) {
  x0 = std::max(0, std::min(w - 1, x0));
  y0 = std::max(0, std::min(h - 1, y0));
  x1 = std::max(0, std::min(w - 1, x1));
  y1 = std::max(0, std::min(h - 1, y1));
  if (x1 <= x0 || y1 <= y0) return 255.0f;

  double sum = 0.0;
  int count = 0;
  for (int x = x0; x <= x1; x++) {
    sum += gray_at(bgra, w, x, y0);
    sum += gray_at(bgra, w, x, y1);
    count += 2;
  }
  for (int y = y0 + 1; y < y1; y++) {
    sum += gray_at(bgra, w, x0, y);
    sum += gray_at(bgra, w, x1, y);
    count += 2;
  }
  return count > 0 ? (float)(sum / count) : 255.0f;
}

static bool is_text_pixel(uint8_t gray, bool dark_background) {
  return dark_background ? gray > 150 : gray < 220;
}

static std::vector<TextBox> segment_text_lines(const uint8_t* bgra, int w, int h) {
  std::vector<TextBox> lines;
  if (!bgra || w < 8 || h < 8) return lines;

  const bool dark_background = estimate_border_gray(bgra, w, h, 0, 0, w - 1, h - 1) < 128.0f;

  std::vector<int> dark_counts(h, 0);
  for (int y = 0; y < h; y++) {
    int count = 0;
    for (int x = 0; x < w; x++) {
      if (is_text_pixel(gray_at(bgra, w, x, y), dark_background)) count++;
    }
    dark_counts[y] = count;
  }

  const int min_dark_pixels = std::max(2, w / 80);
  int y = 0;
  while (y < h) {
    while (y < h && dark_counts[y] < min_dark_pixels) y++;
    if (y >= h) break;
    int y0 = y;
    while (y < h && dark_counts[y] >= min_dark_pixels) y++;
    int y1 = y - 1;

    if ((y1 - y0 + 1) < 6) continue;

    int x0 = w - 1;
    int x1 = 0;
    for (int yy = y0; yy <= y1; yy++) {
      for (int x = 0; x < w; x++) {
        if (is_text_pixel(gray_at(bgra, w, x, yy), dark_background)) {
          x0 = std::min(x0, x);
          x1 = std::max(x1, x);
        }
      }
    }
    if (x1 <= x0) continue;

    const int pad_x = std::max(4, (x1 - x0 + 1) / 30);
    const int pad_y = std::max(3, (y1 - y0 + 1) / 6);
    lines.push_back({
        std::max(0, x0 - pad_x),
        std::max(0, y0 - pad_y),
        std::min(w - 1, x1 + pad_x),
        std::min(h - 1, y1 + pad_y),
    });
  }

  return lines;
}

static std::vector<TextBox> db_postprocess(const float* prob, int h, int w,
                                            float thresh = 0.3f, float unclip_ratio = 1.5f) {
  // Threshold probability map
  std::vector<uint8_t> mask(h * w, 0);
  for (int i = 0; i < h * w; i++) {
    if (prob[i] > thresh) mask[i] = 255;
  }

  // Simple connected-component labeling (4-connected flood fill)
  std::vector<int> labels(h * w, 0);
  int next_label = 1;
  struct BoxAccum { int x0, y0, x1, y1, count; };
  std::vector<BoxAccum> boxes;
  boxes.push_back({0,0,0,0,0}); // dummy at index 0

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int idx = y * w + x;
      if (mask[idx] == 0 || labels[idx] != 0) continue;

      // Flood fill
      std::vector<int> stack;
      stack.push_back(idx);
      labels[idx] = next_label;
      BoxAccum acc = {x, y, x, y, 0};

      while (!stack.empty()) {
        int ci = stack.back(); stack.pop_back();
        int cx = ci % w, cy = ci / w;
        acc.x0 = std::min(acc.x0, cx);
        acc.y0 = std::min(acc.y0, cy);
        acc.x1 = std::max(acc.x1, cx);
        acc.y1 = std::max(acc.y1, cy);
        acc.count++;

        // 4-connected neighbors
        static const int dx[] = {0, 1, 0, -1};
        static const int dy[] = {-1, 0, 1, 0};
        for (int d = 0; d < 4; d++) {
          int nx = cx + dx[d], ny = cy + dy[d];
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
          int ni = ny * w + nx;
          if (mask[ni] && labels[ni] == 0) {
            labels[ni] = next_label;
            stack.push_back(ni);
          }
        }
      }

      if (acc.count >= 3) { // minimum box size
        // Unclip
        int bw = acc.x1 - acc.x0 + 1;
        int bh = acc.y1 - acc.y0 + 1;
        int dx_unclip = (int)(bw * (unclip_ratio - 1.0f) / 2);
        int dy_unclip = (int)(bh * (unclip_ratio - 1.0f) / 2);
        acc.x0 = std::max(0, acc.x0 - dx_unclip);
        acc.y0 = std::max(0, acc.y0 - dy_unclip);
        acc.x1 = std::min(w - 1, acc.x1 + dx_unclip);
        acc.y1 = std::min(h - 1, acc.y1 + dy_unclip);
        boxes.push_back(acc);
      }
      next_label++;
    }
  }

  // Sort boxes top-to-bottom, left-to-right
  std::vector<TextBox> result;
  for (size_t i = 1; i < boxes.size(); i++) {
    result.push_back({boxes[i].x0, boxes[i].y0, boxes[i].x1, boxes[i].y1});
  }
  std::sort(result.begin(), result.end(), [](const TextBox& a, const TextBox& b) {
    int ay = a.y0, by = b.y0;
    if (std::abs(ay - by) > 10) return ay < by;
    return a.x0 < b.x0;
  });

  return result;
}

#ifdef _WIN32
static std::wstring utf8_to_wide(const std::string& s) {
  int wide_len = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  if (wide_len <= 0) return std::wstring();
  std::vector<wchar_t> wide(wide_len);
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, wide.data(), wide_len);
  return std::wstring(wide.data());
}
#endif

// ---------------------------------------------------------------------------
// CTC greedy decode
// ---------------------------------------------------------------------------

// Remove consecutive duplicates, then remove blank (index 0).
static std::string ctc_decode(const float* logits, int time_steps, int num_classes,
                               const std::vector<std::string>& char_dict) {
  std::string result;
  int prev = -1;
  for (int t = 0; t < time_steps; t++) {
    const float* p = logits + t * num_classes;
    // argmax
    int best = 0;
    float best_val = p[0];
    for (int c = 1; c < num_classes; c++) {
      if (p[c] > best_val) { best_val = p[c]; best = c; }
    }
    if (best != prev && best > 0 && best < (int)char_dict.size()) {
      result += char_dict[best];
    }
    prev = best;
  }
  return result;
}

static bool get_tensor_shape(OrtValue* value, std::vector<int64_t>* dims) {
  if (!value || !dims) return false;
  OrtTensorTypeAndShapeInfo* info = nullptr;
  OrtStatus* st = f_GetTensorTypeAndShape(value, &info);
  if (st) {
    f_ReleaseStatus(st);
    return false;
  }
  size_t count = 0;
  st = f_GetDimensionsCount(info, &count);
  if (st) {
    f_ReleaseStatus(st);
    f_ReleaseTensorTypeAndShapeInfo(info);
    return false;
  }
  dims->assign(count, 0);
  st = f_GetDimensions(info, dims->data(), count);
  f_ReleaseTensorTypeAndShapeInfo(info);
  if (st) {
    f_ReleaseStatus(st);
    return false;
  }
  return true;
}

static std::string recognize_single_box(const uint8_t* bgra, int w, int h,
                                        const TextBox& b,
                                        int rec_w, int rec_h) {
  auto rec_input = preprocess_rec(bgra, w, h, b.x0, b.y0, b.x1, b.y1, rec_w, rec_h);

  int64_t rec_shape[] = {1, 3, rec_h, rec_w};
  OrtValue* rec_tensor = nullptr;
  f_CreateTensor(g_mem_info, rec_input.data(),
      rec_input.size() * sizeof(float), rec_shape, 4,
      ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &rec_tensor);

  OrtRunOptions* rec_opts = nullptr;
  f_CreateRunOptions(&rec_opts);

  const char* rec_input_names[] = {"x"};
  const char* rec_output_names[] = {"softmax_11.tmp_0"};
  OrtValue* rec_output = nullptr;
  OrtStatus* st = f_Run(g_rec_session, rec_opts, rec_input_names, &rec_tensor, 1,
                           rec_output_names, 1, &rec_output);
  f_ReleaseValue(rec_tensor);
  f_ReleaseRunOptions(rec_opts);
  if (st) {
    f_ReleaseStatus(st);
    return "";
  }

  float* rec_data = nullptr;
  f_GetTensorMutableData(rec_output, (void**)&rec_data);

  std::vector<int64_t> out_shape;
  if (!get_tensor_shape(rec_output, &out_shape) || out_shape.size() != 3) {
    f_ReleaseValue(rec_output);
    return "";
  }

  int time_steps = (int)out_shape[1];
  int num_classes = (int)out_shape[2];
  int dict_classes = (int)g_chars.size();
  int decode_classes = std::min(num_classes, dict_classes);
  std::string text = ctc_decode(rec_data, time_steps, decode_classes, g_chars);
  f_ReleaseValue(rec_output);
  return text;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

static std::string g_model_dir;

int paddle_ocr_init(const char* model_dir, const char* onnxruntime_path) {
  if (g_initialized) return 0;

  if (!load_ort(onnxruntime_path)) return -1;

  g_model_dir = model_dir;
  std::string base(model_dir);
  if (!base.empty() && base.back() != '/' && base.back() != '\\') base += "/";

  // Load detection model
  std::string det_path = base + "det.onnx";
#ifdef _WIN32
  std::wstring det_path_w = utf8_to_wide(det_path);
  OrtStatus* st = f_CreateSession(g_env, det_path_w.c_str(), nullptr, &g_det_session);
#else
  OrtStatus* st = f_CreateSession(g_env, det_path.c_str(), nullptr, &g_det_session);
#endif
  if (st) { fprintf(stderr, "ORT: failed to load det model: %s\n", f_GetErrorMessage(st)); f_ReleaseStatus(st); return -2; }

  // Load recognition model
  std::string rec_path = base + "rec.onnx";
#ifdef _WIN32
  std::wstring rec_path_w = utf8_to_wide(rec_path);
  st = f_CreateSession(g_env, rec_path_w.c_str(), nullptr, &g_rec_session);
#else
  st = f_CreateSession(g_env, rec_path.c_str(), nullptr, &g_rec_session);
#endif
  if (st) { fprintf(stderr, "ORT: failed to load rec model: %s\n", f_GetErrorMessage(st)); f_ReleaseStatus(st); return -3; }

  // Load dictionary
  std::string dict_path = base + "dict.txt";
  std::ifstream dict_file(dict_path);
  if (!dict_file.is_open()) { fprintf(stderr, "ORT: failed to open dict.txt\n"); return -4; }
  g_chars.clear();
  g_chars.push_back(""); // index 0 = blank
  std::string line;
  while (std::getline(dict_file, line)) {
    while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) line.pop_back();
    g_chars.push_back(line);
  }
  g_chars.push_back(" ");
  dict_file.close();

  g_initialized = true;
  return 0;
}

char* paddle_ocr_recognize(const uint8_t* bgra, int w, int h) {
  if (!g_initialized || !bgra || w < 10 || h < 10) return nullptr;

  std::string result;

  try {
    // The user has already selected the text region manually. For this
    // workflow, line segmentation over the selected crop is more stable than
    // our simplified detection pipeline and keeps behavior consistent across
    // platforms while still using PaddleOCR's recognition model.
    auto boxes = segment_text_lines(bgra, w, h);
    if (boxes.empty()) {
      boxes.push_back({0, 0, w - 1, h - 1});
    }

    const int rec_h = 48;

    for (size_t bi = 0; bi < boxes.size(); bi++) {
      const auto& b = boxes[bi];
      float ratio = (float)std::max(1, b.x1 - b.x0 + 1) /
          (float)std::max(1, b.y1 - b.y0 + 1);
      int rec_w = (int)std::ceil(rec_h * std::max(6.6667f, ratio));
      rec_w = ((rec_w + 31) / 32) * 32;
      rec_w = std::min(2048, std::max(320, rec_w));
      std::string text = recognize_single_box(bgra, w, h, b, rec_w, rec_h);
      if (!text.empty()) {
        if (!result.empty()) result += "\n";
        result += text;
      }
    }

    if (result.empty()) {
      const TextBox full_box{0, 0, w - 1, h - 1};
      float ratio = (float)w / (float)std::max(1, h);
      int rec_w = (int)std::ceil(rec_h * std::max(6.6667f, ratio));
      rec_w = ((rec_w + 31) / 32) * 32;
      rec_w = std::min(2048, std::max(320, rec_w));
      result = recognize_single_box(bgra, w, h, full_box, rec_w, rec_h);
    }

  } catch (...) {
    return nullptr;
  }

  if (result.empty()) return nullptr;

  char* out = (char*)malloc(result.size() + 1);
  if (out) {
    memcpy(out, result.c_str(), result.size() + 1);
  }
  return out;
}

void paddle_ocr_free_string(char* s) {
  free(s);
}

void paddle_ocr_destroy() {
  if (g_det_session) { f_ReleaseSession(g_det_session); g_det_session = nullptr; }
  if (g_rec_session) { f_ReleaseSession(g_rec_session); g_rec_session = nullptr; }
  if (g_mem_info) { f_ReleaseMemoryInfo(g_mem_info); g_mem_info = nullptr; }
  if (g_env) { f_ReleaseEnv(g_env); g_env = nullptr; }
  g_initialized = false;
  g_chars.clear();
#ifdef _WIN32
  if (g_ort_dll) { FreeLibrary(g_ort_dll); g_ort_dll = nullptr; }
#else
  if (g_ort_dll) { dlclose(g_ort_dll); g_ort_dll = nullptr; }
#endif
}
