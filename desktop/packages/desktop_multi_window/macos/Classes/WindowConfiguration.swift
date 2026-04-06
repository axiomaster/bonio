import Foundation
import Cocoa


struct WindowConfiguration: Codable {
 
    let arguments: String
    let hiddenAtLaunch: Bool
    let borderless: Bool
    let width: Double
    let height: Double
    
    enum CodingKeys: String, CodingKey {
        case arguments
        case hiddenAtLaunch
        case borderless
        case width
        case height
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        hiddenAtLaunch = try container.decodeIfPresent(Bool.self, forKey: .hiddenAtLaunch) ?? false
        borderless = try container.decodeIfPresent(Bool.self, forKey: .borderless) ?? false
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 0
        height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 0
    }
    
    init(arguments: String, hiddenAtLaunch: Bool, borderless: Bool = false, width: Double = 0, height: Double = 0) {
        self.arguments = arguments
        self.hiddenAtLaunch = hiddenAtLaunch
        self.borderless = borderless
        self.width = width
        self.height = height
    }

    static let defaultConfiguration = WindowConfiguration(
        arguments: "",
        hiddenAtLaunch: false,
        borderless: false
    )

    static func fromJson(_ json: [String: Any?]) -> WindowConfiguration {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json, options: []) else {
            debugPrint("invalid json object: \(json)")
            return defaultConfiguration
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(WindowConfiguration.self, from: jsonData)
        } catch {
            debugPrint("Failed to parse window configuration: \(error)")
            return defaultConfiguration
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(hiddenAtLaunch, forKey: .hiddenAtLaunch)
    }
}
