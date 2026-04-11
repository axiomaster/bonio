#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_

#include <Windows.h>
#include <oleidl.h>

#include <flutter/flutter_view_controller.h>

#include <memory>
#include <string>

#include "win32_window.h"
#include "window_configuration.h"

class AvatarDropTarget;

class FlutterWindow : public Win32Window {
 public:
  FlutterWindow(const std::string& id, const WindowConfiguration config);
  ~FlutterWindow() override;

  std::string GetWindowId() const { return id_; }

  std::string GetWindowArgument() const { return window_argument_; }

  flutter::FlutterViewController* GetFlutterViewController() const {
    return flutter_controller_.get();
  }

 protected:
  // Win32Window overrides
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND hwnd,
                         UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  std::string id_;
  std::string window_argument_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // OLE drag-and-drop target (registered after window creation).
  AvatarDropTarget* drop_target_ = nullptr;
};

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_H_
