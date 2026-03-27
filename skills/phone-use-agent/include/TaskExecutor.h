#pragma once

#include "AutoGLMClient.h"
#include "UIInspector.h"
#include "AppManager.h"
#include <string>
#include <memory>
#include <vector>
#include <mutex>
#include <atomic>

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
    int step_count = 0;  // Number of steps executed
};

class TaskExecutor {
public:
    TaskExecutor();
    TaskExecutor(std::shared_ptr<UIInspector> ui_inspector,
                 std::shared_ptr<AppManager> app_manager);
    ~TaskExecutor();

    // Initialize task executor with required components
    bool initialize();

    // Execute a task: Main Agent Loop
    Task executeTask(const std::string& user_command,
                    const std::string& current_screenshot,
                    const std::string& ui_tree);

    // Set maximum step limit (default: 20)
    void setMaxStepLimit(int limit) { max_step_limit_ = limit; }
    int getMaxStepLimit() const { return max_step_limit_; }

    // Get task history
    std::vector<Task> getTaskHistory() const;
    
    // Provide access to UIInspector for message handler
    std::shared_ptr<UIInspector>& getUIInspector() { return ui_inspector_; }

    // Parsers (Public for testing)
    struct ParsedAction {
        std::string type;
        std::map<std::string, std::string> args;
    };
    ParsedAction parseActionString(const std::string& action_string);
    // Coordinate conversion (0-1000 -> absolute)
    std::pair<int, int> convertCoordinates(int rel_x, int rel_y);
    
    // Legacy method - remove later
    bool executeActionPlan(const std::string& action_plan);

private:
    std::shared_ptr<UIInspector> ui_inspector_;
    std::shared_ptr<AppManager> app_manager_;
    std::unique_ptr<AutoGLMClient> glm_client_;

    std::vector<Task> task_history_;
    mutable std::mutex history_mutex_;

    int max_step_limit_ = 20;  // Default max steps

    // Helper methods
    std::string generateTaskId();
    std::string getCurrentTimestamp();

    // Action execution helpers
    // Returns true if action succeeded, false otherwise
    // 'should_finish' is set to true if the task is complete
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
    
    // Low level primitives
    bool tapElement(const std::string& element_id);
    bool tapCoordinates(int x, int y);
    bool inputText(const std::string& text);
    bool swipe(int x1, int y1, int x2, int y2, int duration_ms);
    bool waitForElement(const std::string& element_id, int timeout_ms);
    bool launchApp(const std::string& bundle_name);
    bool isValidElementId(const std::string& element_id);
};
