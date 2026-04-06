import Cocoa
import FlutterMacOS
import Foundation

typealias WindowId = String

extension WindowId {
    static func generate() -> WindowId {
        return UUID().uuidString
    }
}

class CustomWindow: NSWindow {

    init(configuration: WindowConfiguration) {
        let mask: NSWindow.StyleMask
        if configuration.borderless {
            mask = [.borderless]
        } else {
            mask = [.miniaturizable, .closable, .titled, .resizable]
        }
        let w = configuration.width > 0 ? configuration.width : 96.0
        let h = configuration.height > 0 ? configuration.height : 96.0
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: mask, backing: .buffered,
            defer: false)

        self.isReleasedWhenClosed = false

        if configuration.borderless {
            self.isOpaque = false
            self.backgroundColor = .clear
            self.hasShadow = false
            self.level = .floating
            self.collectionBehavior = [.canJoinAllSpaces, .stationary]
            self.isMovableByWindowBackground = true
        }
    }

    deinit {
        debugPrint("Child window deinit")
    }

}

class FlutterWindow: NSObject {
    let windowId: WindowId
    let windowArgument: String
    private(set) var window: NSWindow
    private var channel: FlutterMethodChannel?

    private var willBecomeActiveObserver: NSObjectProtocol?
    private var didResignActiveObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    init(windowId: WindowId, windowArgument: String, window: NSWindow) {
        self.windowId = windowId
        self.windowArgument = windowArgument
        self.window = window
        super.init()

        willBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.didChangeOcclusionState(notification)
        }

        didResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.didChangeOcclusionState(notification)
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [windowId] _ in
            MultiWindowManager.shared.removeWindow(windowId: windowId)
        }
    }

    deinit {
        if let willBecomeActiveObserver = willBecomeActiveObserver {
            NotificationCenter.default.removeObserver(willBecomeActiveObserver)
        }
        if let didResignActiveObserver = didResignActiveObserver {
            NotificationCenter.default.removeObserver(didResignActiveObserver)
        }
        if let closeObserver = closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
    }

    @objc func didChangeOcclusionState(_ notification: Notification) {
        if let controller = window.contentViewController as? FlutterViewController {
            controller.engine.handleDidChangeOcclusionState(notification)
        }
    }

    func setChannel(_ channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func notifyWindowEvent(_ event: String, data: [String: Any]) {
        if let channel = channel {
            channel.invokeMethod(event, arguments: data)
        } else {
            debugPrint("Channel not set for window \(windowId), cannot notify event \(event)")
        }
    }

    func handleWindowMethod(method: String, arguments: Any?, result: @escaping FlutterResult) {
        let args = arguments as? [String: Any]

        switch method {
        case "window_show":
            window.makeKeyAndOrderFront(nil)
            window.setIsVisible(true)
            NSApp.activate(ignoringOtherApps: true)
            result(nil)
        case "window_hide":
            window.orderOut(nil)
            result(nil)

        // -- Position (Flutter top-left coords ↔ Cocoa bottom-left) --

        case "window_setPosition":
            let x = (args?["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (args?["y"] as? NSNumber)?.doubleValue ?? 0
            let screen = window.screen ?? NSScreen.screens[0]
            let cocoaY = screen.frame.height - y - window.frame.height
            window.setFrameOrigin(NSPoint(x: x, y: cocoaY))
            result(nil)

        case "window_getPosition":
            let screen = window.screen ?? NSScreen.screens[0]
            let f = window.frame
            let flutterY = screen.frame.height - f.origin.y - f.height
            result(["x": f.origin.x, "y": flutterY] as [String: Double])

        case "window_startDragging":
            if let event = window.currentEvent ?? NSApp.currentEvent {
                window.performDrag(with: event)
            }
            result(nil)

        // -- Dock-aware positioning (macOS only) --

        case "window_getDockInfo":
            let screen = window.screen ?? NSScreen.screens[0]
            let sf = screen.frame
            let vf = screen.visibleFrame
            let dockHeight = vf.origin.y - sf.origin.y
            let dockAtBottom = dockHeight > 6
            let menuBarHeight = sf.height - (vf.origin.y + vf.height - sf.origin.y)
            result([
                "screenWidth": sf.width,
                "screenHeight": sf.height,
                "dockAtBottom": dockAtBottom,
                "dockHeight": dockHeight,
                "menuBarHeight": menuBarHeight,
            ] as [String: Any])

        default:
            result(FlutterError(code: "-1", message: "unknown method \(method)", details: nil))
        }
    }

}
