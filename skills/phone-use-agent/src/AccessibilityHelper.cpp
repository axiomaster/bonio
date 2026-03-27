#include "AccessibilityHelper.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <memory>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

// Define static constant for UI tree XML path
const char* const AccessibilityHelper::UI_TREE_XML_PATH = "/data/local/tmp/ui.xml";

AccessibilityHelper::AccessibilityHelper()
    : isConnected_(false)
    , accessibility_service_name_("com.example.openclaw/.OpenClawAccessibilityService") {
}

AccessibilityHelper::~AccessibilityHelper() {
}

bool AccessibilityHelper::initialize() {
    // Check if accessibility service is enabled
    //
    // NOTE: This service runs ON the HarmonyOS device, not on a host machine.
    // The spec shows using 'hdc shell' commands, which would only work from a host.
    // When running on-device, we execute commands directly without hdc wrapper.
    //
    // Additionally, 'settings' command may not be available in HarmonyOS shell.
    // We attempt to check but continue with limited functionality if it fails.

    std::string cmd = "settings get secure enabled_accessibility_services";
    std::string output;

    // Use RAII pattern to ensure pipe is always closed
    auto pipe_closer = [](FILE* p) { if (p) pclose(p); };
    std::unique_ptr<FILE, decltype(pipe_closer)> pipe_guard(popen(cmd.c_str(), "r"), pipe_closer);

    if (pipe_guard) {
        char buffer[4096];  // Increased buffer size to prevent overflow
        while (fgets(buffer, sizeof(buffer), pipe_guard.get()) != nullptr) {
            output += buffer;
        }

        // Check if accessibility service is enabled
        if (output.find(accessibility_service_name_) != std::string::npos) {
            isConnected_ = true;
            std::cout << "Accessibility service is connected" << std::endl;
            return true;
        }
    }

    std::cerr << "Accessibility service not enabled" << std::endl;
    std::cerr << "Please enable OpenClaw accessibility service in Settings" << std::endl;
    // Continue without accessibility service - we can still use uitest commands
    std::cerr << "Continuing with limited functionality using uitest commands..." << std::endl;
    isConnected_ = true;  // Set true so basic commands work
    return true;
}

AccessibilityElementInfo AccessibilityHelper::getElementInfo(const std::string& element_id) {
    // STUB: Not yet implemented
    //
    // This function requires HarmonyOS accessibility API integration.
    // Currently returns a placeholder element with the requested ID.
    //
    // TODO: Implement using accessibility service connection
    // - Query element by ID from accessibility service
    // - Populate all AccessibilityElementInfo fields
    // - Return full element information

    AccessibilityElementInfo info;
    info.element_id = element_id;
    return info;
}

AccessibilityElementInfo AccessibilityHelper::getRootElement() {
    // STUB: Not yet implemented
    //
    // This function requires HarmonyOS accessibility API integration.
    // Currently returns an empty root element.
    //
    // TODO: Implement using accessibility service connection
    // - Get root accessibility node from current window
    // - Populate AccessibilityElementInfo with root properties
    // - Return root element

    AccessibilityElementInfo root;
    return root;
}

std::vector<AccessibilityElementInfo> AccessibilityHelper::findElementsByText(
    const std::string& text) {
    // STUB: Not yet implemented
    //
    // This function requires UI tree traversal implementation.
    // Currently returns an empty list.
    //
    // TODO: Implement using accessibility service or UI tree parsing
    // - Traverse UI tree from root
    // - Find all elements containing the specified text
    // - Return vector of matching AccessibilityElementInfo objects

    std::vector<AccessibilityElementInfo> elements;
    return elements;
}

std::string AccessibilityHelper::getUITreeJSON() {
    // Get UI tree using HarmonyOS uitest command
    //
    // NOTE: Spec uses 'uiautomator dump' which is Android-specific.
    // HarmonyOS Next uses 'uitest dumpLayout' instead.
    // Tested on device: 'uiautomator' command not found, 'uitest dumpLayout' works.
    //
    // Since this service runs ON the device, we don't need to pull files via hdc.
    // The dumpLayout command creates the file directly on the device filesystem.

    std::string cmd = "/bin/uitest dumpLayout -p " + std::string(UI_TREE_XML_PATH) + " > /dev/null 2>&1";
    std::string output;

    // Use RAII pattern to ensure pipe is always closed
    auto pipe_closer = [](FILE* p) { if (p) pclose(p); };
    std::unique_ptr<FILE, decltype(pipe_closer)> pipe_guard(popen(cmd.c_str(), "r"), pipe_closer);

    if (pipe_guard) {
        char buffer[4096];  // Increased buffer size to prevent overflow
        while (fgets(buffer, sizeof(buffer), pipe_guard.get()) != nullptr) {
            output += buffer;
        }

        // Check if command succeeded
        FILE* raw_pipe = pipe_guard.release();
        int result = pclose(raw_pipe);
        if (result != 0) {
            std::cerr << "uitest dumpLayout command failed with code: " << result << std::endl;
            return "{}";
        }
    }

    // Read the XML file from device filesystem
    // Since service runs on-device, this path is local to our process
    std::ifstream file(UI_TREE_XML_PATH);
    if (!file.is_open()) {
        std::cerr << "Failed to open UI tree XML file: " << UI_TREE_XML_PATH << std::endl;
        // Return empty JSON object - caller can distinguish error from empty result
        // by checking if returned string is exactly "{}"
        return "{}";
    }

    std::string xml_content((std::istreambuf_iterator<char>(file)),
                           std::istreambuf_iterator<char>());

    // XML to JSON parsing is deferred until needed
    // The uitest dumpLayout command produces XML that needs to be parsed into JSON format.
    // This parsing will be implemented when the UI tree structure is required by AutoGLM.
    // For now, returning empty JSON is safe - the screenshot provides the visual information.
    //
    // TODO: Parse XML and build JSON tree
    // - Use XML parser (e.g., tinyxml2) to parse dumpLayout output
    // - Extract element properties: id, text, bounds, class_name, etc.
    // - Build hierarchical JSON structure matching AccessibilityElementInfo
    // - Return complete UI tree as JSON string

    json ui_tree;
    return ui_tree.dump();
}

bool AccessibilityHelper::takeScreenshot(const std::string& output_path) {
    // Take screenshot using HarmonyOS snapshot_display command
    //
    // NOTE: Previously used 'uitest screenCap' which had compatibility issues.
    // HarmonyOS provides 'snapshot_display' as the recommended screenshot utility.
    //
    // Using 0.5x screen dimensions (660x1424 for typical 1320x2848 screen) to:
    // - Reduce image file size for network transmission
    // - Lower bandwidth usage when sending to AI model
    // - Decrease latency for API requests
    //
    // Since this service runs ON the device, output_path is a device filesystem path.
    // We don't need to pull files via hdc file pull - the screenshot is saved directly
    // to the specified location on the device.

    // snapshot_display writes directly to the output path specified with -f flag
    // Using 0.5x dimensions: 660x1424 (half of typical 1320x2848 screen)
    std::string cmd = "snapshot_display -w 660 -h 1424 -f " + output_path + " 2>&1";

    // Use RAII pattern to ensure pipe is always closed
    auto pipe_closer = [](FILE* p) { if (p) pclose(p); };
    std::unique_ptr<FILE, decltype(pipe_closer)> pipe_guard(popen(cmd.c_str(), "r"), pipe_closer);

    if (!pipe_guard) {
        std::cerr << "Failed to take screenshot: popen failed" << std::endl;
        return false;
    }

    // Consume any output
    std::string output;
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), pipe_guard.get()) != nullptr) {
        output += buffer;
    }

    // Close the pipe
    FILE* raw_pipe = pipe_guard.release();
    pclose(raw_pipe);

    // Verify output file exists and has content
    std::ifstream file(output_path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        std::cerr << "Failed to take screenshot: file not created: " << output_path << std::endl;
        std::cerr << "Command output: " << output << std::endl;
        return false;
    }

    std::streamsize file_size = file.tellg();
    file.close();

    if (file_size < 1000) {
        std::cerr << "Failed to take screenshot: file too small (" << file_size << " bytes)" << std::endl;
        return false;
    }

    std::cout << "Screenshot saved: " << output_path << " (" << file_size << " bytes)" << std::endl;
    return true;
}
