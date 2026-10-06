import AppKit
import ApplicationServices
import NotchIntegrationCore

/// The unsandboxed helper both checks permission and intercepts the media keys.
/// Each tap belongs to its XPC connection and is removed when that connection closes.
final class MediaKeyEventTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onKeyDown: ((Int, UInt) -> Void)?

    static var canIntercept: Bool {
        // Probe the operation itself: AX trust can lag behind a changed TCC grant.
        guard let probe = createTap(callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil) else { return false }
        CFMachPortInvalidate(probe)
        return true
    }

    var isActive: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() -> Bool {
        if tap != nil { return true }
        guard let port = Self.createTap(callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<MediaKeyEventTap>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type.rawValue == 14, let native = NSEvent(cgEvent: event),
                  let key = MediaKeyEvent(data1: native.data1, subtype: Int(native.subtype.rawValue)) else {
                return Unmanaged.passUnretained(event)
            }
            guard key.shouldIntercept(commandHeld: native.modifierFlags.contains(.command),
                                      pointerDisplayBrightnessControllable: ScreenBrightness.pointerDisplayIsControllable) else {
                return Unmanaged.passUnretained(event)
            }
            if key.isKeyDown { owner.onKeyDown?(key.keyCode, native.modifierFlags.rawValue) }
            // Consume both halves; forward only key-down/repeat to avoid applying a step twice.
            return nil
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let loopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { return false }
        tap = port
        source = loopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        onKeyDown = nil
    }

    deinit { stop() }

    private static func createTap(callback: CGEventTapCallBack, userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
        CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                          eventsOfInterest: CGEventMask(1 << 14), callback: callback, userInfo: userInfo)
    }
}
