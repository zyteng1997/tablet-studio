import Foundation
import ApplicationServices
import IOKit.hidsystem

enum Permissions {
    /// Demande l'autorisation Accessibilité. Avec `prompt: true`, macOS ouvre
    /// la fenêtre de demande la première fois ; sinon retourne simplement
    /// l'état courant.
    @discardableResult
    static func requestAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options: NSDictionary = [key: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func inputMonitoringStatus() -> InputMonitoringStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .undetermined
        }
    }

    static func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

}

enum InputMonitoringStatus {
    case granted
    case denied
    case undetermined
    case unknown
}

extension InputMonitoringStatus {
    var humanReadable: String {
        switch self {
        case .granted:      return "accordée"
        case .denied:       return "REFUSÉE — cochez 'wacomd' dans Surveillance des entrées"
        case .undetermined: return "non encore demandée"
        case .unknown:      return "indéterminée"
        }
    }
}
