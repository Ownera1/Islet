//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {
    let mediaKeys = MediaKeyEventTap()
    weak var connection: NSXPCConnection?
    @MainActor lazy var integration = IntegrationHost()
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { reply(MediaKeyEventTap.canIntercept) }
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            if MediaKeyEventTap.canIntercept { reply(true); return }
            if promptIfNeeded { self.requestAccessibilityAuthorization() }
            reply(false)
        }
    }

    @objc func startMediaKeyEvents(with reply: @escaping (Bool, String?) -> Void) {
        DispatchQueue.main.async {
            guard let connection = self.connection else {
                reply(false, "HUD Helper 连接已中断，请重试。")
                return
            }
            connection.remoteObjectInterface = NSXPCInterface(with: NotchMediaKeyCallbacks.self)
            self.mediaKeys.onKeyDown = { [weak connection, weak self] code, modifiers in
                guard let client = connection?.remoteObjectProxyWithErrorHandler({ _ in
                    DispatchQueue.main.async { self?.mediaKeys.stop() }
                }) as? NotchMediaKeyCallbacks else { return }
                client.mediaKeyDown(code, modifiers: modifiers)
            }
            let started = self.mediaKeys.start()
            reply(started, started ? nil : "无法拦截媒体键。请在系统设置 → 隐私与安全性 → 辅助功能中重新启用 Islet，然后重试。")
        }
    }

    @objc func stopMediaKeyEvents() {
        DispatchQueue.main.async { self.mediaKeys.stop() }
    }

    @objc func isMediaKeyTapActive(with reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { reply(self.mediaKeys.isActive) }
    }

    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(ScreenBrightness.get(ScreenBrightness.targetDisplay()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(ScreenBrightness.get(ScreenBrightness.targetDisplay()).map { NSNumber(value: $0) })
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(ScreenBrightness.set(max(0, min(1, value)), on: ScreenBrightness.targetDisplay()))
    }
}

/// Brightness through DisplayServices (Apple panels), IOKit, or DDC/CI for external
/// monitors. Displays none of these can drive are left to the system.
enum ScreenBrightness {
    /// The display under the pointer when its brightness can be controlled, else the built-in panel.
    static func targetDisplay() -> CGDirectDisplayID {
        if let pointer = pointerDisplay(), isControllable(pointer) { return pointer }
        return onlineDisplays().first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()
    }

    /// Cheap enough for the event tap: DDC answers from cache and probes unknown monitors in the background.
    static var pointerDisplayIsControllable: Bool {
        guard let pointer = pointerDisplay() else { return true }
        return isControllable(pointer)
    }

    private static func isControllable(_ displayID: CGDirectDisplayID) -> Bool {
        if CGDisplayIsBuiltin(displayID) == 0, ExternalDisplayDDC.shared.isControllable(displayID) { return true }
        return nativeGet(displayID) != nil
    }

    static func get(_ displayID: CGDirectDisplayID) -> Float? {
        if let value = nativeGet(displayID) { return value }
        return CGDisplayIsBuiltin(displayID) == 0 ? ExternalDisplayDDC.shared.brightness(displayID) : nil
    }

    private static func nativeGet(_ displayID: CGDirectDisplayID) -> Float? {
        if let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") {
            typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
            var value: Float = 0
            if unsafeBitCast(sym, to: Fn.self)(displayID, &value) == 0 { return value }
        }
        guard let io = ioServiceFor(displayID: displayID) else { return nil }
        defer { IOObjectRelease(io) }
        var level: Float = 0
        return IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess ? level : nil
    }

    static func set(_ value: Float, on displayID: CGDirectDisplayID) -> Bool {
        // DisplayServices reports success even for monitors it cannot drive (a DDC monitor
        // returns 0 on set but fails get), so only trust native control where it can read.
        guard nativeGet(displayID) != nil else {
            return CGDisplayIsBuiltin(displayID) == 0 && ExternalDisplayDDC.shared.setBrightness(value, on: displayID)
        }
        if let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") {
            typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
            if unsafeBitCast(sym, to: Fn.self)(displayID, value) == 0 { return true }
        }
        if let io = ioServiceFor(displayID: displayID) {
            defer { IOObjectRelease(io) }
            if IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, value) == kIOReturnSuccess { return true }
        }
        return false
    }

    private static func pointerDisplay() -> CGDirectDisplayID? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(location, 1, &display, &count) == .success, count > 0 else { return nil }
        return display
    }

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private static func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}
