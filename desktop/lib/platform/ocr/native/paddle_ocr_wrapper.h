#ifndef PADDLE_OCR_WRAPPER_H
#define PADDLE_OCR_WRAPPER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialize the OCR engine.
/// [model_dir] must contain:
///   - det.onnx   (PP-OCRv4 detection model)
///   - rec.onnx   (PP-OCRv4 recognition model)
///   - dict.txt   (character dictionary, one char per line)
/// Returns 0 on success, non-zero on error.
int paddle_ocr_init(const char* model_dir, const char* onnxruntime_path);

/// Recognize text from raw BGRA pixel data.
/// [bgra]  — BGRA pixel buffer (top-down)
/// [w], [h] — image dimensions
/// Returns a malloc'd UTF-8 string (caller must free with paddle_ocr_free).
char* paddle_ocr_recognize(const uint8_t* bgra, int w, int h);

/// Free a string returned by paddle_ocr_recognize.
void paddle_ocr_free_string(char* s);

/// Release all resources.
void paddle_ocr_destroy();

#ifdef __cplusplus
}
#endif

#endif // PADDLE_OCR_WRAPPER_H
