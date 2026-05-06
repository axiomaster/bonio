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

struct OrtEnv;
struct OrtSession;
struct OrtMemoryInfo;
struct OrtValue;
struct OrtRunOptions;
struct OrtStatus;

typedef OrtStatus*(ORT_API_CALL* PF_CreateEnv)(int, const char*, OrtEnv**);
typedef OrtStatus*(ORT_API_CALL* PF_CreateSession)(OrtEnv*, const char*, const void*, OrtSession**);
typedef OrtStatus*(ORT_API_CALL* PF_CreateMemoryInfo)(const char*, int, int, OrtMemoryInfo**);
typedef OrtStatus*(ORT_API_CALL* PF_CreateRunOptions)(OrtRunOptions**);
typedef OrtStatus*(ORT_API_CALL* PF_CreateTensor)(const OrtMemoryInfo*, void*, size_t, const int64_t*, size_t, int32_t, OrtValue**);
typedef OrtStatus*(ORT_API_CALL* PF_Run)(OrtSession*, const void*, const char* const*, const OrtValue* const*, size_t, const char* const*, size_t, OrtValue**);
typedef OrtStatus*(ORT_API_CALL* PF_GetTensorMutableData)(OrtValue*, void**);
typedef void(ORT_API_CALL* PF_ReleaseEnv)(OrtEnv*);
typedef void(ORT_API_CALL* PF_ReleaseSession)(OrtSession*);
typedef void(ORT_API_CALL* PF_ReleaseMemoryInfo)(OrtMemoryInfo*);
typedef void(ORT_API_CALL* PF_ReleaseValue)(OrtValue*);
typedef void(ORT_API_CALL* PF_ReleaseRunOptions)(OrtRunOptions*);
typedef void(ORT_API_CALL* PF_ReleaseStatus)(OrtStatus*);
typedef const char*(ORT_API_CALL* PF_GetErrorMessage)(OrtStatus*);

static PF_CreateEnv f_CreateEnv = nullptr;
static PF_CreateSession f_CreateSession = nullptr;
static PF_CreateMemoryInfo f_CreateMemoryInfo = nullptr;
static PF_CreateRunOptions f_CreateRunOptions = nullptr;
static PF_CreateTensor f_CreateTensor = nullptr;
static PF_Run f_Run = nullptr;
static PF_GetTensorMutableData f_GetTensorMutableData = nullptr;
static PF_ReleaseEnv f_ReleaseEnv = nullptr;
static PF_ReleaseSession f_ReleaseSession = nullptr;
static PF_ReleaseMemoryInfo f_ReleaseMemoryInfo = nullptr;
static PF_ReleaseValue f_ReleaseValue = nullptr;
static PF_ReleaseRunOptions f_ReleaseRunOptions = nullptr;
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
#define LOAD(fn) f_##fn = (PF_##fn)GetProcAddress(g_ort_dll, "Ort" #fn); if (!f_##fn) { fprintf(stderr, "ORT: missing export Ort%s\n", #fn); return false; }
#else
static void* g_ort_dll = nullptr;
#define LOAD(fn) f_##fn = (PF_##fn)dlsym(g_ort_dll, "Ort" #fn); if (!f_##fn) { fprintf(stderr, "ORT: missing export Ort%s\n", #fn); return false; }
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

  LOAD(CreateEnv);
  LOAD(CreateSession);
  LOAD(CreateMemoryInfo);
  LOAD(CreateRunOptions);
  LOAD(CreateTensor);
  LOAD(Run);
  LOAD(GetTensorMutableData);
  LOAD(ReleaseEnv);
  LOAD(ReleaseSession);
  LOAD(ReleaseMemoryInfo);
  LOAD(ReleaseValue);
  LOAD(ReleaseRunOptions);
  LOAD(ReleaseStatus);
  LOAD(GetErrorMessage);

  OrtStatus* st = f_CreateEnv(3, "paddle_ocr", &g_env);
  if (st) { fprintf(stderr, "ORT: CreateEnv failed: %s\n", f_GetErrorMessage(st)); f_ReleaseStatus(st); return false; }
  st = f_CreateMemoryInfo("Cpu", 0, 0, &g_mem_info);
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
      out[0 * target_h * target_w + y * target_w + x] = (p[2] / 255.0f - 0.5f) / 0.5f;
      out[1 * target_h * target_w + y * target_w + x] = (p[1] / 255.0f - 0.5f) / 0.5f;
      out[2 * target_h * target_w + y * target_w + x] = (p[0] / 255.0f - 0.5f) / 0.5f;
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

  int num_classes = (int)g_chars.size();
  int estimated_T = rec_w / 4;
  std::string text = ctc_decode(rec_data, estimated_T, num_classes, g_chars);
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
  OrtStatus* st = f_CreateSession(g_env, det_path.c_str(), nullptr, &g_det_session);
  if (st) { fprintf(stderr, "ORT: failed to load det model: %s\n", f_GetErrorMessage(st)); f_ReleaseStatus(st); return -2; }

  // Load recognition model
  std::string rec_path = base + "rec.onnx";
  st = f_CreateSession(g_env, rec_path.c_str(), nullptr, &g_rec_session);
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
    // --- Detection ---
    // PP-OCRv4 detection input: 3x736x736 dynamic (we use 960 max side)
    int det_max_side = 960;
    int det_w, det_h;
    if (w > h) { det_w = det_max_side; det_h = (int)((float)h / w * det_max_side); }
    else        { det_h = det_max_side; det_w = (int)((float)w / h * det_max_side); }
    if (det_w < 32) det_w = 32;
    if (det_h < 32) det_h = 32;
    // Align to multiples of 32 (DB requirement)
    det_w = ((det_w + 31) / 32) * 32;
    det_h = ((det_h + 31) / 32) * 32;

    auto det_input = preprocess_det(bgra, w, h, det_w, det_h);

    OrtRunOptions* run_opts = nullptr;
    f_CreateRunOptions(&run_opts);

    int64_t det_shape[] = {1, 3, (int64_t)det_h, (int64_t)det_w};
    OrtValue* det_tensor = nullptr;
    f_CreateTensor(g_mem_info, det_input.data(),
        det_input.size() * sizeof(float), det_shape, 4,
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &det_tensor);

    const char* det_input_names[] = {"x"};
    const char* det_output_names[] = {"sigmoid_0.tmp_0"};
    OrtValue* det_output = nullptr;
    OrtStatus* st = f_Run(g_det_session, run_opts, det_input_names, &det_tensor, 1,
                             det_output_names, 1, &det_output);
    f_ReleaseValue(det_tensor);
    f_ReleaseRunOptions(run_opts);
    if (st) {
      fprintf(stderr, "ORT: det inference failed: %s\n", f_GetErrorMessage(st));
      f_ReleaseStatus(st);
      return nullptr;
    }

    // Get detection output (probability map)
    float* det_data = nullptr;
    f_GetTensorMutableData(det_output, (void**)&det_data);

    // DB post-processing
    auto boxes = db_postprocess(det_data, det_h, det_w);
    f_ReleaseValue(det_output);

    bool used_detected_boxes = !boxes.empty();
    if (boxes.empty()) {
      // The user already manually selected the text region. If detection fails,
      // fall back to recognizing the whole crop as a single line so simple
      // standard-font selections still work.
      boxes.push_back({0, 0, w - 1, h - 1});
    }

    if (used_detected_boxes) {
      // Scale detected boxes back to original image coordinates.
      float scale_x = (float)w / det_w;
      float scale_y = (float)h / det_h;
      for (auto& b : boxes) {
        b.x0 = (int)(b.x0 * scale_x);
        b.y0 = (int)(b.y0 * scale_y);
        b.x1 = (int)(b.x1 * scale_x);
        b.y1 = (int)(b.y1 * scale_y);
      }
    }

    // --- Recognition ---
    // PP-OCRv4 rec input: 3x48x320 dynamic
    int rec_h = 48, rec_w = 320;

    for (size_t bi = 0; bi < boxes.size(); bi++) {
      const auto& b = boxes[bi];
      std::string text = recognize_single_box(bgra, w, h, b, rec_w, rec_h);
      if (!text.empty()) {
        if (!result.empty()) result += "\n";
        result += text;
      }
    }

    if (result.empty()) {
      const TextBox full_box{0, 0, w - 1, h - 1};
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
