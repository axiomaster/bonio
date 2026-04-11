#include "drop_target.h"

#include <codecvt>
#include <locale>
#include <fstream>
#include <sstream>
#include <vector>

// Base64 encoding table
static const char kBase64Table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static std::string Base64Encode(const uint8_t* data, size_t len) {
  std::string result;
  result.reserve(4 * ((len + 2) / 3));
  for (size_t i = 0; i < len; i += 3) {
    uint32_t n = static_cast<uint32_t>(data[i]) << 16;
    if (i + 1 < len) n |= static_cast<uint32_t>(data[i + 1]) << 8;
    if (i + 2 < len) n |= static_cast<uint32_t>(data[i + 2]);
    result.push_back(kBase64Table[(n >> 18) & 0x3F]);
    result.push_back(kBase64Table[(n >> 12) & 0x3F]);
    result.push_back(i + 1 < len ? kBase64Table[(n >> 6) & 0x3F] : '=');
    result.push_back(i + 2 < len ? kBase64Table[n & 0x3F] : '=');
  }
  return result;
}

static std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return "";
  int len = ::WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                  static_cast<int>(wide.size()), nullptr, 0,
                                  nullptr, nullptr);
  std::string utf8(len, 0);
  ::WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                        static_cast<int>(wide.size()), &utf8[0], len,
                        nullptr, nullptr);
  return utf8;
}

AvatarDropTarget::AvatarDropTarget(
    HWND hwnd,
    std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel)
    : hwnd_(hwnd), channel_(channel) {}

AvatarDropTarget::~AvatarDropTarget() = default;

HRESULT AvatarDropTarget::QueryInterface(REFIID riid, void** ppvObject) {
  if (riid == IID_IUnknown || riid == IID_IDropTarget) {
    *ppvObject = static_cast<IDropTarget*>(this);
    AddRef();
    return S_OK;
  }
  *ppvObject = nullptr;
  return E_NOINTERFACE;
}

ULONG AvatarDropTarget::AddRef() { return ++ref_count_; }

ULONG AvatarDropTarget::Release() {
  ULONG count = --ref_count_;
  if (count == 0) delete this;
  return count;
}

bool AvatarDropTarget::HasSupportedFormat(IDataObject* pDataObj) {
  FORMATETC fmt_hdrop = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  FORMATETC fmt_text = {CF_UNICODETEXT, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  FORMATETC fmt_dib = {CF_DIB, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};

  return pDataObj->QueryGetData(&fmt_hdrop) == S_OK ||
         pDataObj->QueryGetData(&fmt_text) == S_OK ||
         pDataObj->QueryGetData(&fmt_dib) == S_OK;
}

std::string AvatarDropTarget::ExtractDropType(IDataObject* pDataObj) {
  FORMATETC fmt_hdrop = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  FORMATETC fmt_text = {CF_UNICODETEXT, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  FORMATETC fmt_dib = {CF_DIB, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};

  if (pDataObj->QueryGetData(&fmt_hdrop) == S_OK) return "file";
  if (pDataObj->QueryGetData(&fmt_dib) == S_OK) return "image";
  if (pDataObj->QueryGetData(&fmt_text) == S_OK) return "text";
  return "";
}

HRESULT AvatarDropTarget::DragEnter(IDataObject* pDataObj,
                                    DWORD grfKeyState,
                                    POINTL pt,
                                    DWORD* pdwEffect) {
  has_valid_data_ = HasSupportedFormat(pDataObj);
  *pdwEffect = has_valid_data_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;

  if (has_valid_data_ && channel_) {
    auto type = ExtractDropType(pDataObj);
    flutter::EncodableMap data;
    data[flutter::EncodableValue("type")] = flutter::EncodableValue(type);
    channel_->InvokeMethod(
        "avatarDragEnter",
        std::make_unique<flutter::EncodableValue>(data));
  }

  return S_OK;
}

HRESULT AvatarDropTarget::DragOver(DWORD grfKeyState,
                                   POINTL pt,
                                   DWORD* pdwEffect) {
  *pdwEffect = has_valid_data_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
  return S_OK;
}

HRESULT AvatarDropTarget::DragLeave() {
  has_valid_data_ = false;
  if (channel_) {
    flutter::EncodableMap data;
    channel_->InvokeMethod(
        "avatarDragLeave",
        std::make_unique<flutter::EncodableValue>(data));
  }
  return S_OK;
}

HRESULT AvatarDropTarget::Drop(IDataObject* pDataObj,
                               DWORD grfKeyState,
                               POINTL pt,
                               DWORD* pdwEffect) {
  *pdwEffect = DROPEFFECT_NONE;
  if (!has_valid_data_ || !channel_) return S_OK;

  flutter::EncodableMap data;

  // --- CF_HDROP: file paths ---
  FORMATETC fmt_hdrop = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM stg = {};
  if (pDataObj->GetData(&fmt_hdrop, &stg) == S_OK) {
    HDROP hDrop = static_cast<HDROP>(::GlobalLock(stg.hGlobal));
    if (hDrop) {
      UINT count = ::DragQueryFileW(hDrop, 0xFFFFFFFF, nullptr, 0);
      flutter::EncodableList paths;
      for (UINT i = 0; i < count; i++) {
        UINT len = ::DragQueryFileW(hDrop, i, nullptr, 0);
        std::wstring path(len + 1, 0);
        ::DragQueryFileW(hDrop, i, &path[0], len + 1);
        path.resize(len);
        paths.push_back(flutter::EncodableValue(WideToUtf8(path)));
      }
      data[flutter::EncodableValue("type")] = flutter::EncodableValue("file");
      data[flutter::EncodableValue("paths")] = flutter::EncodableValue(paths);
      ::GlobalUnlock(stg.hGlobal);
    }
    ::ReleaseStgMedium(&stg);

    channel_->InvokeMethod(
        "avatarDrop",
        std::make_unique<flutter::EncodableValue>(data));
    *pdwEffect = DROPEFFECT_COPY;
    has_valid_data_ = false;
    return S_OK;
  }

  // --- CF_DIB: bitmap ---
  FORMATETC fmt_dib = {CF_DIB, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  if (pDataObj->GetData(&fmt_dib, &stg) == S_OK) {
    auto* bmi = static_cast<BITMAPINFO*>(::GlobalLock(stg.hGlobal));
    if (bmi) {
      size_t headerSize = sizeof(BITMAPINFOHEADER);
      size_t totalSize = ::GlobalSize(stg.hGlobal);
      size_t pixelSize = totalSize - headerSize;
      auto* pixels = reinterpret_cast<uint8_t*>(bmi) + headerSize;
      std::string b64 = Base64Encode(pixels, pixelSize);

      data[flutter::EncodableValue("type")] = flutter::EncodableValue("image");
      data[flutter::EncodableValue("base64")] = flutter::EncodableValue(b64);
      data[flutter::EncodableValue("width")] =
          flutter::EncodableValue(static_cast<int>(bmi->bmiHeader.biWidth));
      data[flutter::EncodableValue("height")] =
          flutter::EncodableValue(static_cast<int>(
              bmi->bmiHeader.biHeight < 0 ? -bmi->bmiHeader.biHeight
                                          : bmi->bmiHeader.biHeight));
      ::GlobalUnlock(stg.hGlobal);
    }
    ::ReleaseStgMedium(&stg);

    channel_->InvokeMethod(
        "avatarDrop",
        std::make_unique<flutter::EncodableValue>(data));
    *pdwEffect = DROPEFFECT_COPY;
    has_valid_data_ = false;
    return S_OK;
  }

  // --- CF_UNICODETEXT: text ---
  FORMATETC fmt_text = {CF_UNICODETEXT, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  if (pDataObj->GetData(&fmt_text, &stg) == S_OK) {
    auto* wstr = static_cast<wchar_t*>(::GlobalLock(stg.hGlobal));
    if (wstr) {
      std::wstring wide(wstr);
      data[flutter::EncodableValue("type")] = flutter::EncodableValue("text");
      data[flutter::EncodableValue("text")] =
          flutter::EncodableValue(WideToUtf8(wide));
      ::GlobalUnlock(stg.hGlobal);
    }
    ::ReleaseStgMedium(&stg);

    channel_->InvokeMethod(
        "avatarDrop",
        std::make_unique<flutter::EncodableValue>(data));
    *pdwEffect = DROPEFFECT_COPY;
    has_valid_data_ = false;
    return S_OK;
  }

  has_valid_data_ = false;
  return S_OK;
}
