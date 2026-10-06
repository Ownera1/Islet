import AppKit
import Defaults
import Foundation

@MainActor final class XPCHelperClient {
    static let shared = XPCHelperClient()
    var onMediaKeyDown: ((Int, UInt) -> Void)?
    var onMediaDisconnect: (() -> Void)?
    var result: (Bool, String?) = (true, nil)
    var deferred = false
    var pending: [CheckedContinuation<(Bool, String?), Never>] = []
    var stopCount = 0
    var startCount = 0
    var tapActive = true
    func requestAccessibilityAuthorization() {}
    func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool { result.0 }
    func isMediaKeyTapActive() async -> Bool { tapActive }
    func startMediaKeyEvents() async -> (Bool, String?) {
        startCount += 1
        if deferred { return await withCheckedContinuation { pending.append($0) } }
        return result
    }
    func stopMediaKeyEvents() { stopCount += 1 }
}

enum OptionKeyAction: String, Defaults.Serializable { case openSettings, showHUD, none }
let hudTestPreferences = UserDefaults(suiteName: "Islet.HUDTests.\(UUID().uuidString)")!
extension Defaults.Keys {
    static let hudReplacement = Key<Bool>("hudReplacement", default: false, suite: hudTestPreferences)
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: .none, suite: hudTestPreferences)
}
@MainActor final class VolumeManager {
    static let shared = VolumeManager()
    var rawVolume: Float = 0.5
    var increases: [Float] = []
    func increase(stepDivisor: Float) { increases.append(stepDivisor) }
    func decrease(stepDivisor: Float) {}
    func toggleMuteAction() {}
}
@MainActor final class BrightnessManager {
    static let shared = BrightnessManager()
    var rawBrightness: Float = 0.5
    func setRelative(delta: Float) {}
}
@MainActor final class KeyboardBacklightManager {
    static let shared = KeyboardBacklightManager()
    var rawBrightness: Float = 0.5
    func setRelative(delta: Float) {}
}
@MainActor final class BoringViewCoordinator {
    static let shared = BoringViewCoordinator()
    enum Kind { case volume, backlight, brightness }
    func toggleSneakPeek(status: Bool, type: Kind, value: CGFloat) {}
}
