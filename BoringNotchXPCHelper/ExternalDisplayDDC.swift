import CoreGraphics
import Foundation
import IOKit

// Apple silicon exposes each external display's DDC/CI channel as an IOAVService
// (the approach BetterDisplay and MonitorControl use). These symbols are private.
private typealias IOAVService = CFTypeRef
@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<IOAVService>?
@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(_ service: IOAVService, _ chipAddress: UInt32, _ offset: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(_ service: IOAVService, _ chipAddress: UInt32, _ dataAddress: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn

/// Brightness (VCP 0x10) over DDC/CI for external monitors. All bus traffic runs on one
/// serial queue; writes are coalesced so a burst of key presses sends only the last value.
final class ExternalDisplayDDC {
    static let shared = ExternalDisplayDDC()

    private struct Level { var current: Int; var max: Int }

    private let queue = DispatchQueue(label: "com.ownera1.agentusagenotch.helper.ddc")
    private let lock = NSLock()
    private var services: [CGDirectDisplayID: IOAVService] = [:]
    private var levels: [CGDirectDisplayID: Level] = [:]
    private var unsupported: Set<CGDirectDisplayID> = []
    private var pendingWrites: [CGDirectDisplayID: Int] = [:]
    private var probing: Set<CGDirectDisplayID> = []
    private var discoveredAt: Date = .distantPast

    private init() {
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            guard flags.contains(.addFlag) || flags.contains(.removeFlag) else { return }
            ExternalDisplayDDC.shared.reset()
        }, nil)
    }

    /// Non-blocking: true once a DDC read has succeeded for this display. Unknown displays
    /// are probed in the background, so the first key press on them still passes through.
    func isControllable(_ display: CGDirectDisplayID) -> Bool {
        lock.lock()
        let known = levels[display] != nil
        let skip = known || unsupported.contains(display) || probing.contains(display)
        if !skip { probing.insert(display) }
        lock.unlock()
        if !skip {
            queue.async {
                _ = self.readLevel(display)
                self.lock.lock(); self.probing.remove(display); self.lock.unlock()
            }
        }
        return known
    }

    /// Current brightness as 0...1, from cache when possible.
    func brightness(_ display: CGDirectDisplayID) -> Float? {
        lock.lock()
        let cached = levels[display]
        let skip = unsupported.contains(display)
        lock.unlock()
        if let cached { return Float(cached.current) / Float(max(cached.max, 1)) }
        if skip { return nil }
        guard let level = queue.sync(execute: { readLevel(display) }) else { return nil }
        return Float(level.current) / Float(max(level.max, 1))
    }

    /// Updates the cache at once and writes asynchronously; false if the display has no DDC.
    func setBrightness(_ value: Float, on display: CGDirectDisplayID) -> Bool {
        guard brightness(display) != nil else { return false }
        lock.lock()
        guard var level = levels[display] else { lock.unlock(); return false }
        level.current = Int((max(0, min(1, value)) * Float(level.max)).rounded())
        levels[display] = level
        let alreadyQueued = pendingWrites[display] != nil
        pendingWrites[display] = level.current
        lock.unlock()
        if !alreadyQueued {
            queue.async { self.flushWrite(display) }
        }
        return true
    }

    private func reset() {
        lock.lock()
        services.removeAll()
        levels.removeAll()
        unsupported.removeAll()
        discoveredAt = .distantPast
        lock.unlock()
    }

    // MARK: - Bus (serial queue only)

    private func flushWrite(_ display: CGDirectDisplayID) {
        lock.lock()
        let value = pendingWrites.removeValue(forKey: display)
        lock.unlock()
        guard let value, let service = service(for: display) else { return }
        var send: [UInt8] = [0x10, UInt8(value >> 8), UInt8(value & 0xFF)]
        var reply: [UInt8] = []
        _ = communicate(service, send: &send, reply: &reply)
    }

    private func readLevel(_ display: CGDirectDisplayID) -> Level? {
        guard let service = service(for: display) else {
            markUnsupported(display)
            return nil
        }
        var send: [UInt8] = [0x10]
        var reply = [UInt8](repeating: 0, count: 11)
        guard communicate(service, send: &send, reply: &reply) else {
            markUnsupported(display)
            return nil
        }
        let level = Level(current: Int(reply[8]) << 8 | Int(reply[9]), max: Int(reply[6]) << 8 | Int(reply[7]))
        guard level.max > 0 else {
            markUnsupported(display)
            return nil
        }
        lock.lock(); levels[display] = level; lock.unlock()
        return level
    }

    private func markUnsupported(_ display: CGDirectDisplayID) {
        lock.lock(); unsupported.insert(display); lock.unlock()
    }

    /// One DDC/CI transaction: a Get VCP request (one byte) expects an 11-byte reply,
    /// a Set VCP request (three bytes) expects none.
    private func communicate(_ service: IOAVService, send: inout [UInt8], reply: inout [UInt8]) -> Bool {
        var packet = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        packet[packet.count - 1] = packet.dropLast().reduce(0x6E ^ 0x51, ^)
        for _ in 0..<4 {
            var wrote = false
            for _ in 0..<2 {
                usleep(10_000)
                if IOAVServiceWriteI2C(service, 0x37, 0x51, &packet, UInt32(packet.count)) == kIOReturnSuccess { wrote = true }
            }
            if wrote && reply.isEmpty { return true }
            if wrote {
                usleep(50_000)
                if IOAVServiceReadI2C(service, 0x37, 0x51, &reply, UInt32(reply.count)) == kIOReturnSuccess,
                   reply.dropLast().reduce(0x50, ^) == reply[reply.count - 1] {
                    return true
                }
            }
            usleep(20_000)
        }
        return false
    }

    private func service(for display: CGDirectDisplayID) -> IOAVService? {
        lock.lock()
        if let service = services[display] { lock.unlock(); return service }
        let stale = Date().timeIntervalSince(discoveredAt) > 2
        lock.unlock()
        guard stale else { return nil }
        let found = discoverServices()
        lock.lock()
        services = found
        discoveredAt = Date()
        lock.unlock()
        return found[display]
    }

    /// Walks the IOService plane: each external DCPAVServiceProxy follows the framebuffer
    /// whose ProductAttributes identify the monitor, matched to CoreGraphics by
    /// vendor, model and serial number.
    private func discoverServices() -> [CGDirectDisplayID: IOAVService] {
        var onlineIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var onlineCount: UInt32 = 0
        CGGetOnlineDisplayList(16, &onlineIDs, &onlineCount)
        let externals = onlineIDs.prefix(Int(onlineCount)).filter { CGDisplayIsBuiltin($0) == 0 }

        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(IORegistryGetRootEntry(kIOMainPortDefault), kIOServicePlane,
                                            IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }

        var result: [CGDirectDisplayID: IOAVService] = [:]
        var attributes: [String: Any]?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &nameBuffer)
            let name = String(cString: nameBuffer)
            if name == "AppleCLCD2" || name == "IOMobileFramebufferShim" {
                let display = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
                attributes = display?["ProductAttributes"] as? [String: Any]
                continue
            }
            guard name == "DCPAVServiceProxy",
                  IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String == "External",
                  let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            let vendor = (attributes?["LegacyManufacturerID"] as? NSNumber)?.uint32Value
            let model = (attributes?["ProductID"] as? NSNumber)?.uint32Value
            let serial = (attributes?["SerialNumber"] as? NSNumber)?.uint32Value
            let matches = externals.filter { id in
                result[id] == nil && CGDisplayVendorNumber(id) == vendor && CGDisplayModelNumber(id) == model
            }
            let match = matches.first(where: { serial == nil || CGDisplaySerialNumber($0) == serial }) ?? matches.first
            if let match { result[match] = service }
            attributes = nil
        }
        return result
    }
}
