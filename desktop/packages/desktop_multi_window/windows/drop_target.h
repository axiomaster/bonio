#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_DROP_TARGET_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_DROP_TARGET_H_

#include <Windows.h>
#include <oleidl.h>
#include <shellapi.h>
#include <shlobj.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

/// COM IDropTarget that accepts file, text, and bitmap drops on the avatar
/// window and forwards them to the Dart side via a dedicated MethodChannel
/// (`boji/avatar_drop`) on the sub-window's Flutter engine.
class AvatarDropTarget : public IDropTarget {
 public:
  AvatarDropTarget(
      HWND hwnd,
      std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);
  virtual ~AvatarDropTarget();

  // IUnknown
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                           void** ppvObject) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  // IDropTarget
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* pDataObj,
                                      DWORD grfKeyState,
                                      POINTL pt,
                                      DWORD* pdwEffect) override;
  HRESULT STDMETHODCALLTYPE DragOver(DWORD grfKeyState,
                                     POINTL pt,
                                     DWORD* pdwEffect) override;
  HRESULT STDMETHODCALLTYPE DragLeave() override;
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* pDataObj,
                                 DWORD grfKeyState,
                                 POINTL pt,
                                 DWORD* pdwEffect) override;

 private:
  bool HasSupportedFormat(IDataObject* pDataObj);
  std::string ExtractDropType(IDataObject* pDataObj);

  ULONG ref_count_ = 1;
  HWND hwnd_;
  std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool has_valid_data_ = false;
};

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_DROP_TARGET_H_
