#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_WRAPPER_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_WRAPPER_H_

#include <Windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <memory>
#include <string>

class FlutterWindowWrapper {
 public:
  FlutterWindowWrapper(const std::string& window_id,
                       HWND hwnd,
                       const std::string& window_argument = "")
      : window_id_(window_id), hwnd_(hwnd), window_argument_(window_argument) {}

  ~FlutterWindowWrapper() = default;

  std::string GetWindowId() const { return window_id_; }

  std::string GetWindowArgument() const { return window_argument_; }

  HWND GetWindowHandle() { return hwnd_; }

  void SetChannel(
      std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
          channel) {
    channel_ = channel;
  }

  void NotifyWindowEvent(const std::string& event,
                         const flutter::EncodableMap& data) {
    if (channel_) {
      channel_->InvokeMethod(event,
                             std::make_unique<flutter::EncodableValue>(data));
    }
  }

  void HandleWindowMethod(
      const std::string& method,
      const flutter::EncodableMap* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (method == "window_show") {
      if (hwnd_) {
        ::ShowWindow(hwnd_, SW_SHOW);
      }
      result->Success();
    } else if (method == "window_hide") {
      if (hwnd_) {
        ::ShowWindow(hwnd_, SW_HIDE);
      }
      result->Success();
    } else if (method == "window_setPosition") {
      if (hwnd_ && arguments) {
        auto x_it = arguments->find(flutter::EncodableValue("x"));
        auto y_it = arguments->find(flutter::EncodableValue("y"));
        if (x_it != arguments->end() && y_it != arguments->end()) {
          double x = std::get<double>(x_it->second);
          double y = std::get<double>(y_it->second);
          double dpi = static_cast<double>(::GetDpiForWindow(hwnd_));
          double scale = dpi / 96.0;
          int px = static_cast<int>(x * scale);
          int py = static_cast<int>(y * scale);
          ::SetWindowPos(hwnd_, nullptr, px, py, 0, 0,
                         SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        }
      }
      result->Success();
    } else if (method == "window_setPositionPhysical") {
      if (hwnd_ && arguments) {
        auto x_it = arguments->find(flutter::EncodableValue("x"));
        auto y_it = arguments->find(flutter::EncodableValue("y"));
        if (x_it != arguments->end() && y_it != arguments->end()) {
          int px = static_cast<int>(std::get<double>(x_it->second));
          int py = static_cast<int>(std::get<double>(y_it->second));
          ::SetWindowPos(hwnd_, nullptr, px, py, 0, 0,
                         SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        }
      }
      result->Success();
    } else if (method == "window_getPosition") {
      flutter::EncodableMap pos;
      if (hwnd_) {
        RECT rect;
        ::GetWindowRect(hwnd_, &rect);
        double dpi = static_cast<double>(::GetDpiForWindow(hwnd_));
        double scale = dpi / 96.0;
        pos[flutter::EncodableValue("x")] =
            flutter::EncodableValue(rect.left / scale);
        pos[flutter::EncodableValue("y")] =
            flutter::EncodableValue(rect.top / scale);
      } else {
        pos[flutter::EncodableValue("x")] = flutter::EncodableValue(0.0);
        pos[flutter::EncodableValue("y")] = flutter::EncodableValue(0.0);
      }
      result->Success(flutter::EncodableValue(pos));
    } else if (method == "window_getPositionPhysical") {
      flutter::EncodableMap pos;
      if (hwnd_) {
        RECT rect;
        ::GetWindowRect(hwnd_, &rect);
        pos[flutter::EncodableValue("x")] =
            flutter::EncodableValue(static_cast<double>(rect.left));
        pos[flutter::EncodableValue("y")] =
            flutter::EncodableValue(static_cast<double>(rect.top));
      } else {
        pos[flutter::EncodableValue("x")] = flutter::EncodableValue(0.0);
        pos[flutter::EncodableValue("y")] = flutter::EncodableValue(0.0);
      }
      result->Success(flutter::EncodableValue(pos));
    } else if (method == "window_showPopupMenu") {
      if (!hwnd_ || !arguments) {
        result->Success(flutter::EncodableValue(""));
        return;
      }
      auto items_it = arguments->find(flutter::EncodableValue("items"));
      if (items_it == arguments->end()) {
        result->Success(flutter::EncodableValue(""));
        return;
      }
      const auto& items = std::get<flutter::EncodableList>(items_it->second);
      HMENU hMenu = ::CreatePopupMenu();
      if (!hMenu) {
        result->Success(flutter::EncodableValue(""));
        return;
      }
      // Each item: {"id": int, "label": string, "enabled": bool}
      // id==0 → separator
      for (const auto& item : items) {
        const auto& map = std::get<flutter::EncodableMap>(item);
        int id = std::get<int>(map.at(flutter::EncodableValue("id")));
        if (id == 0) {
          ::AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);
        } else {
          auto label = std::get<std::string>(map.at(flutter::EncodableValue("label")));
          bool enabled = std::get<bool>(map.at(flutter::EncodableValue("enabled")));
          int wLen = ::MultiByteToWideChar(CP_UTF8, 0, label.c_str(), -1, nullptr, 0);
          std::wstring wLabel(wLen, 0);
          ::MultiByteToWideChar(CP_UTF8, 0, label.c_str(), -1, &wLabel[0], wLen);
          UINT flags = MF_STRING | (enabled ? 0 : MF_GRAYED);
          ::AppendMenuW(hMenu, flags, id, wLabel.c_str());
        }
      }
      ::SetForegroundWindow(hwnd_);
      POINT pt;
      ::GetCursorPos(&pt);
      int sel = ::TrackPopupMenuEx(hMenu,
          TPM_RETURNCMD | TPM_NONOTIFY | TPM_LEFTALIGN | TPM_TOPALIGN,
          pt.x, pt.y, hwnd_, nullptr);
      ::DestroyMenu(hMenu);
      // Look up action string by selected id
      std::string action;
      if (sel > 0) {
        auto actions_it = arguments->find(flutter::EncodableValue("actions"));
        if (actions_it != arguments->end()) {
          const auto& actions = std::get<flutter::EncodableMap>(actions_it->second);
          auto act_it = actions.find(flutter::EncodableValue(sel));
          if (act_it != actions.end()) {
            action = std::get<std::string>(act_it->second);
          }
        }
      }
      result->Success(flutter::EncodableValue(action));
    } else {
      result->Error("-1", "unknown method: " + method);
    }
  }

 protected:
  void SetWindowHandle(HWND hwnd) { hwnd_ = hwnd; }

 private:
  std::string window_id_;
  HWND hwnd_;
  std::string window_argument_;
  std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_WRAPPER_H_
