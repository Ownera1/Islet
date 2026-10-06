import Foundation

public struct MediaKeyEvent: Equatable, Sendable {
    public let keyCode: Int
    public let isKeyDown: Bool

    /// Only volume, mute, display brightness and keyboard brightness keys belong to our HUD.
    public init?(data1: Int, subtype: Int) {
        let code = (data1 >> 16) & 0xffff
        let state = (data1 >> 8) & 0xff
        guard subtype == 8, [0, 1, 2, 3, 7, 21, 22].contains(code), [0xA, 0xB].contains(state) else { return nil }
        keyCode = code
        isKeyDown = state == 0xA
    }

    /// Display brightness keys (without ⌘, which means keyboard backlight) are only taken
    /// when Islet can drive the display under the pointer; otherwise they go on to the
    /// system or another brightness tool for that display.
    public func shouldIntercept(commandHeld: Bool, pointerDisplayBrightnessControllable: Bool) -> Bool {
        guard [2, 3].contains(keyCode), !commandHeld else { return true }
        return pointerDisplayBrightnessControllable
    }
}
