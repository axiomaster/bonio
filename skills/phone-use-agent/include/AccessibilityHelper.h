#pragma once

#include <string>
#include <vector>

struct AccessibilityElementInfo {
    std::string element_id;
    std::string text;
    std::string content_description;
    std::string class_name;
    bool is_clickable;
    bool is_editable;
    bool is_visible;
    std::vector<std::string> children_ids;
};

class AccessibilityHelper {
public:
    AccessibilityHelper();
    ~AccessibilityHelper();

    // Initialize accessibility service connection
    bool initialize();

    // Get accessibility element info by id
    AccessibilityElementInfo getElementInfo(const std::string& element_id);

    // Get root element of current window
    AccessibilityElementInfo getRootElement();

    // Find element by text
    std::vector<AccessibilityElementInfo> findElementsByText(const std::string& text);

    // Get full UI tree as JSON
    std::string getUITreeJSON();

    // Take screenshot
    bool takeScreenshot(const std::string& output_path);

private:
    bool isConnected_;
    std::string accessibility_service_name_;

    // Constants for file paths
    static const char* const UI_TREE_XML_PATH;  // Path for UI tree dump output
};
