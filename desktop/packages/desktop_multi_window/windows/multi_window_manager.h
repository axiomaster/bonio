#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_

#include <cstdint>
#include <map>
#include <string>

#include "flutter_plugin_registrar.h"
#include "flutter_window.h"
#include "flutter_window_wrapper.h"

class MultiWindowManager {
 public:
  static MultiWindowManager* Instance();

  MultiWindowManager();

  std::string Create(const flutter::EncodableMap* args);

  void AttachFlutterMainWindow(HWND main_window_handle,
                               FlutterDesktopPluginRegistrarRef registrar);

  FlutterWindowWrapper* GetWindow(const std::string& window_id);

  void RemoveWindow(const std::string& window_id);

  void SetIgnoreDpiChange(const std::string& window_id, bool ignore);

  void RemoveManagedFlutterWindowLater(const std::string& window_id);

  flutter::EncodableList GetAllWindows();

  std::vector<std::string> GetAllWindowIds();

 private:
  void NotifyWindowsChanged();

  void CleanupRemovedWindows();

  std::map<std::string, std::unique_ptr<FlutterWindowWrapper>> windows_;
  std::map<std::string, std::unique_ptr<FlutterWindow>>
      managed_flutter_windows_;
  std::vector<std::string> pending_remove_ids_;

  // HWNDs registered via RegisterDragDrop (may be child Flutter view HWNDs,
  // not necessarily the top-level parent).
  std::map<std::string, HWND> drop_target_hwnds_;
};

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
