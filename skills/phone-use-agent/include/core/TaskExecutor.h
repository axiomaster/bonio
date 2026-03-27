#pragma once

#include "platform/Platform.h"
#include "AutoGLMClient.h"
#include <string>
#include <memory>
#include <vector>
#include <mutex>
#include <atomic>
#include <functional>

// Global interruption flag - can be set by signal handler
extern std::atomic<bool> g_interrupted;

// Check if execution should be interrupted
inline bool isInterrupted() { return g_interrupted.load(); }

enum class TaskStatus {
    Pending,
    InProgress,
    Completed,
    Failed,
    Interrupted
};

struct Task {
    std::string task_id;
    std::string user_command;
    AutoGLMResponse glm_response;
    TaskStatus status;
    std::string result_screenshot_path;
    std::string error_message;
    std::string timestamp;
    int step_count = 0;
};

using ActionCallback = std::function<void(const std::string& action_json)>;

class TaskExecutor {
public:
    TaskExecutor();
    explicit TaskExecutor(std::unique_ptr<IPlatform> platform);
    ~TaskExecutor();

    // Initialize task executor with required components
    bool initialize();

    // Execute a task: Main Agent Loop
    Task executeTask(const std::string& user_command,
                    const std::string& current_screenshot = "",
                    const std::string& ui_tree = "");

    // Set maximum step limit (default: 20)
    void setMaxStepLimit(int limit) { max_step_limit_ = limit; }
    int getMaxStepLimit() const { return max_step_limit_; }

    // Set callback invoked before each GUI action with JSON: {action, x?, y?, args}
    void setActionCallback(ActionCallback cb) { action_callback_ = std::move(cb); }

    // Get task history
    std::vector<Task> getTaskHistory() const;

    // Get platform instance
    IPlatform* getPlatform() { return platform_.get(); }

    // Parsers (Public for testing)
    struct ParsedAction {
        std::string type;
        std::map<std::string, std::string> args;
    };
    ParsedAction parseActionString(const std::string& action_string);

    // Coordinate conversion (0-1000 -> absolute)
    std::pair<int, int> convertCoordinates(int rel_x, int rel_y);

private:
    std::unique_ptr<IPlatform> platform_;
    std::unique_ptr<AutoGLMClient> glm_client_;
    std::unique_ptr<IHttpClient> http_client_;
    ActionCallback action_callback_;

    std::vector<Task> task_history_;
    mutable std::mutex history_mutex_;

    int max_step_limit_ = 20;
    int screen_width_ = 0;
    int screen_height_ = 0;

    // Helper methods
    std::string generateTaskId();
    std::string getCurrentTimestamp();
    void notifyAction(const ParsedAction& action);

    // Action execution helpers
    bool executeAction(const std::string& action_string, bool& should_finish);

    // Specific action handlers
    bool handleTap(const std::map<std::string, std::string>& args);
    bool handleType(const std::map<std::string, std::string>& args);
    bool handleSwipe(const std::map<std::string, std::string>& args);
    bool handleLaunch(const std::map<std::string, std::string>& args);
    bool handleBack(const std::map<std::string, std::string>& args);
    bool handleHome(const std::map<std::string, std::string>& args);
    bool handleWait(const std::map<std::string, std::string>& args);
    bool handleLongPress(const std::map<std::string, std::string>& args);
    bool handleDoubleTap(const std::map<std::string, std::string>& args);

    // Utility
    bool captureScreenshot(std::string& out_path);
    void initScreenSize();
};
