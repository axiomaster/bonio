/**
 * bonio_proxy_ime — Silent text injection tool for OpenHarmony.
 *
 * Uses OpenHarmony Input Method Framework (IMF) ProxyIME capability
 * to inject text into focused edit fields without opening a soft keyboard.
 */

#include <iostream>
#include <variant>
#include <unordered_map>
#include <string>
#include <functional>
#include <memory>
#include <cstdint>
#include <chrono>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <unistd.h>
#include <sys/wait.h>

namespace OHOS {
namespace MiscServices {

struct SubProperty {
    std::string label;
    uint32_t labelId = 0;
    std::string name;
    std::string id;
    std::string mode;
    std::string locale;
    std::string language;
    std::string icon;
    uint32_t iconId = 0;
};

using PrivateDataValue = std::variant<std::string, bool, int32_t>;

class InputMethodEngineListener {
public:
    virtual ~InputMethodEngineListener() = default;
    virtual void OnKeyboardStatus(bool isShow) = 0;
    virtual void OnInputStart() = 0;
    virtual int32_t OnInputStop() = 0;
    virtual int32_t OnDiscardTypingText() { return 0; }
    virtual void OnSecurityChange(int32_t security) {}
    virtual void OnSetCallingWindow(uint32_t windowId) = 0;
    virtual void OnSetSubtype(const SubProperty &property) = 0;
    virtual void ReceivePrivateCommand(const std::unordered_map<std::string, PrivateDataValue> &privateCommand) = 0;
    virtual void OnInputFinish() {}
    virtual bool IsEnable(uint64_t displayId) { return true; }
    virtual bool IsCallbackRegistered(const std::string &type) { return false; }
    virtual bool PostTaskToEventHandler(std::function<void()> task, const std::string &taskName) { return false; }
    virtual void OnCallingDisplayIdChanged(uint64_t callingDisplayId) {}
    virtual void NotifyPreemption() {}
};

class BonioProxyListener : public InputMethodEngineListener {
public:
    std::atomic<bool> inputStarted{false};
    std::mutex mtx;
    std::condition_variable cv;
    bool verbose = false;

    void OnKeyboardStatus(bool isShow) override {
        if (verbose) std::cerr << "[BonioProxyIME] OnKeyboardStatus: " << isShow << std::endl;
    }

    void OnInputStart() override {
        if (verbose) std::cerr << "[BonioProxyIME] OnInputStart triggered" << std::endl;
        inputStarted.store(true);
        cv.notify_all();
    }

    int32_t OnInputStop() override {
        if (verbose) std::cerr << "[BonioProxyIME] OnInputStop triggered" << std::endl;
        inputStarted.store(false);
        return 0;
    }

    void OnInputFinish() override {
        if (verbose) std::cerr << "[BonioProxyIME] OnInputFinish triggered" << std::endl;
        inputStarted.store(false);
    }

    void OnSetCallingWindow(uint32_t windowId) override {}
    void OnSetSubtype(const SubProperty &property) override {}
    void ReceivePrivateCommand(const std::unordered_map<std::string, PrivateDataValue> &privateCommand) override {}

    bool IsEnable(uint64_t displayId) override {
        if (verbose) std::cerr << "[BonioProxyIME] IsEnable(" << displayId << ") -> true" << std::endl;
        return true;
    }
};

} // namespace MiscServices
} // namespace OHOS

typedef void* (*GetInstanceFunc)();
typedef void (*SetImeListenerFunc)(void* self, std::shared_ptr<OHOS::MiscServices::InputMethodEngineListener> listener);
typedef int32_t (*RegisterProxyImeFunc)(void* self, uint64_t displayId);
typedef int32_t (*UnregisterProxyImeFunc)(void* self, uint64_t displayId, int32_t type);
typedef int32_t (*InsertTextFunc)(void* self, const std::string& text);

static void* g_instance = nullptr;
static UnregisterProxyImeFunc g_unregProxy = nullptr;
static uint64_t g_displayId = 0;
static bool g_registered = false;

static void CleanupProxy() {
    if (g_registered && g_instance && g_unregProxy) {
        g_unregProxy(g_instance, g_displayId, 0); // REMOVE_PROXY_IME = 0
        g_registered = false;
    }
}

static void SignalHandler(int signum) {
    CleanupProxy();
    _exit(128 + signum);
}

static bool RunClick(int x, int y) {
    pid_t pid = fork();
    if (pid < 0) return false;
    if (pid == 0) {
        std::string sx = std::to_string(x);
        std::string sy = std::to_string(y);
        char* const args[] = {
            const_cast<char*>("/bin/uitest"),
            const_cast<char*>("uiInput"),
            const_cast<char*>("click"),
            const_cast<char*>(sx.c_str()),
            const_cast<char*>(sy.c_str()),
            nullptr
        };
        execv("/bin/uitest", args);
        _exit(1);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

int main(int argc, char* argv[]) {
    std::string text;
    int inputX = -1, inputY = -1;
    int sendX = -1, sendY = -1;
    int timeoutMs = 2500;
    bool doSend = true;
    bool verbose = false;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--text" && i + 1 < argc) {
            text = argv[++i];
        } else if (arg == "--input" && i + 2 < argc) {
            inputX = std::stoi(argv[++i]);
            inputY = std::stoi(argv[++i]);
        } else if (arg == "--send" && i + 2 < argc) {
            sendX = std::stoi(argv[++i]);
            sendY = std::stoi(argv[++i]);
        } else if (arg == "--no-send") {
            doSend = false;
        } else if (arg == "--timeout" && i + 1 < argc) {
            timeoutMs = std::stoi(argv[++i]);
        } else if (arg == "--display" && i + 1 < argc) {
            g_displayId = std::stoull(argv[++i]);
        } else if (arg == "--verbose" || arg == "-v") {
            verbose = true;
        } else if (arg == "--help" || arg == "-h") {
            std::cout << "Usage: bonio-proxy-ime --text <str> [--input <x> <y>] [--send <x> <y>] [--no-send] [--timeout <ms>] [--verbose]\n";
            return 0;
        }
    }

    if (text.empty() && inputX < 0) {
        std::cerr << "{\"ok\":false,\"error\":\"Nothing to do: --text or --input required\"}\n";
        return 1;
    }

    auto start_time = std::chrono::steady_clock::now();

    // Must be UID 7101 (AI_PROXY_IME) or in proxyImeUidList
    if (getuid() != 7101) {
        if (setuid(7101) != 0) {
            if (verbose) perror("setuid(7101) failed, continuing as current uid");
        }
    }

    signal(SIGINT, SignalHandler);
    signal(SIGTERM, SignalHandler);

    void* handle = dlopen("/system/lib64/platformsdk/libinputmethod_ability.z.so", RTLD_NOW);
    if (!handle) {
        std::cerr << "{\"ok\":false,\"stage\":\"dlopen\",\"error\":\"" << dlerror() << "\"}\n";
        return 1;
    }

    auto getInst = (GetInstanceFunc)dlsym(handle, "_ZN4OHOS12MiscServices27InputMethodAbilityInterface11GetInstanceEv");
    auto setListener = (SetImeListenerFunc)dlsym(handle, "_ZN4OHOS12MiscServices27InputMethodAbilityInterface14SetImeListenerENSt3__h10shared_ptrINS0_25InputMethodEngineListenerEEE");
    auto regProxy = (RegisterProxyImeFunc)dlsym(handle, "_ZN4OHOS12MiscServices27InputMethodAbilityInterface16RegisterProxyImeEm");
    g_unregProxy = (UnregisterProxyImeFunc)dlsym(handle, "_ZN4OHOS12MiscServices27InputMethodAbilityInterface18UnregisterProxyImeEmNS0_16UnRegisteredTypeE");
    auto insertText = (InsertTextFunc)dlsym(handle, "_ZN4OHOS12MiscServices27InputMethodAbilityInterface10InsertTextERKNSt3__h12basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEE");

    if (!getInst || !setListener || !regProxy || !g_unregProxy || !insertText) {
        dlclose(handle);
        std::cerr << "{\"ok\":false,\"stage\":\"dlsym\",\"error\":\"Failed to resolve IMF symbols\"}\n";
        return 1;
    }

    g_instance = getInst();
    auto listener = std::make_shared<OHOS::MiscServices::BonioProxyListener>();
    listener->verbose = verbose;
    setListener(g_instance, listener);

    int32_t regRet = regProxy(g_instance, g_displayId);
    if (regRet != 0) {
        dlclose(handle);
        std::cerr << "{\"ok\":false,\"stage\":\"register\",\"code\":" << regRet << ",\"error\":\"RegisterProxyIme failed\"}\n";
        return 1;
    }
    g_registered = true;

    // Step 1: Click input box if coordinate provided
    if (inputX >= 0 && inputY >= 0) {
        if (verbose) std::cerr << "[BonioProxyIME] Clicking input box (" << inputX << ", " << inputY << ")\n";
        RunClick(inputX, inputY);
    }

    // Step 2: Wait for data channel to connect and insert text
    bool inserted = false;
    auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);

    // First try immediately or wait for listener signal
    {
        std::unique_lock<std::mutex> lk(listener->mtx);
        if (!listener->inputStarted.load()) {
            listener->cv.wait_for(lk, std::chrono::milliseconds(300), [&]() {
                return listener->inputStarted.load();
            });
        }
    }

    // Poll insertText in case channel is already connected
    while (std::chrono::steady_clock::now() < deadline) {
        int32_t insRet = insertText(g_instance, text);
        if (insRet == 0) {
            inserted = true;
            if (verbose) std::cerr << "[BonioProxyIME] InsertText success\n";
            break;
        }
        usleep(25000); // 25ms
    }

    if (!inserted) {
        CleanupProxy();
        dlclose(handle);
        std::cerr << "{\"ok\":false,\"stage\":\"insert\",\"error\":\"InsertText timed out\"}\n";
        return 2;
    }

    // Step 3: Tap send button if requested and coordinates provided
    bool sent = false;
    if (doSend && sendX >= 0 && sendY >= 0) {
        // Allow UI brief frame to show send button
        usleep(120000); // 120ms
        if (verbose) std::cerr << "[BonioProxyIME] Clicking send button (" << sendX << ", " << sendY << ")\n";
        RunClick(sendX, sendY);
        sent = true;
        usleep(80000); // 80ms
    }

    // Step 4: Clean up ProxyIME
    CleanupProxy();
    dlclose(handle);

    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start_time).count();

    std::cout << "{\"ok\":true"
              << ",\"inserted\":true"
              << ",\"sent\":" << (sent ? "true" : "false")
              << ",\"duration_ms\":" << elapsed
              << "}\n";
    return 0;
}
