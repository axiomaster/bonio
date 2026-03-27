#pragma once

#include "AccessibilityHelper.h"
#include <string>
#include <memory>

struct UIState {
    std::string screenshot_path;
    std::string ui_tree_json;
    std::vector<AccessibilityElementInfo> clickable_elements;
    std::vector<std::string> visible_texts;
};

class UIInspector {
public:
    UIInspector();
    ~UIInspector();

    bool initialize();

    // Capture current UI state
    UIState captureUIState(const std::string& screenshot_dir = "/data/local/tmp");

    // Extract text from current screen
    std::vector<std::string> extractText();

    // Find message list in CangLian
    std::vector<std::string> getCangLianMessages();

private:
    std::unique_ptr<AccessibilityHelper> accessibility_;
    std::string last_screenshot_path_;
};
