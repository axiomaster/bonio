#include "UIInspector.h"
#include <iostream>
#include <chrono>
#include <iomanip>
#include <sstream>

UIInspector::UIInspector() {
}

UIInspector::~UIInspector() {
}

bool UIInspector::initialize() {
    accessibility_ = std::make_unique<AccessibilityHelper>();
    return accessibility_->initialize();
}

UIState UIInspector::captureUIState(const std::string& screenshot_dir) {
    UIState state;

    // Generate timestamp for screenshot
    auto now = std::chrono::system_clock::now();
    auto timestamp = std::chrono::system_clock::to_time_t(now);
    std::stringstream ss;
    ss << screenshot_dir << "/screenshot_" << timestamp << ".jpeg";

    std::string screenshot_path = ss.str();

    // Take screenshot
    if (accessibility_->takeScreenshot(screenshot_path)) {
        // Ensure file is readable by other apps (Gallery)
        std::string chmod_cmd = "chmod 644 " + screenshot_path;
        system(chmod_cmd.c_str());

        state.screenshot_path = screenshot_path;
        last_screenshot_path_ = screenshot_path;
        std::cout << "Screenshot saved: " << screenshot_path << std::endl;
    }

    // Get UI tree
    state.ui_tree_json = accessibility_->getUITreeJSON();

    return state;
}

std::vector<std::string> UIInspector::extractText() {
    // STUB: Not yet implemented
    //
    // This function should extract visible text from the current screen.
    // Currently returns an empty list.
    //
    // Two possible implementation approaches:
    // 1. Parse UI tree XML and extract text from all elements
    //    - Requires XML parsing implementation
    //    - More accurate, gets text from non-rendered elements
    // 2. Use OCR on screenshot
    //    - Requires OCR library integration (e.g., Tesseract)
    //    - Works on rendered output only
    //
    // TODO: Implement text extraction
    // - Choose parsing vs OCR approach (or both)
    // - Extract all visible text elements
    // - Return vector of text strings ordered by screen position

    std::vector<std::string> texts;

    // Parse UI tree and extract all text elements
    // For now, use OCR on screenshot as fallback

    return texts;
}

std::vector<std::string> UIInspector::getCangLianMessages() {
    // STUB: Not yet implemented
    //
    // This function should extract messages from CangLian app message list.
    // Currently returns an empty list.
    //
    // Requires:
    // 1. Knowledge of CangLian app UI structure (message list element IDs)
    // 2. UI tree parsing to identify message elements
    // 3. Text extraction from message elements
    //
    // TODO: Implement CangLian-specific message extraction
    // - Analyze CangLian app UI structure using uitest dumpLayout
    // - Identify message list container and individual message elements
    // - Extract message text, sender, timestamp
    // - Return vector of message contents

    std::vector<std::string> messages;

    UIState state = captureUIState();

    // Parse UI tree to find message list
    // CangLian message structure needs to be determined from actual app

    return messages;
}
