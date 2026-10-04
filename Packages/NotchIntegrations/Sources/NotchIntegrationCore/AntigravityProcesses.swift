// Adapted from CodexBar's DarwinProcessEnumerator (MIT). See LICENSE-CodexBar.
import Foundation
import Darwin

enum AntigravityProcesses {
    struct Endpoint { let port: Int; let token: String }
    struct Identity: Equatable { let parent: Int32; let started: UInt64 }
    static func endpoints() -> [Endpoint] {
        var result: [Endpoint] = []
        for pid in allPIDs() {
            guard identity(pid) != nil, let path = executablePath(pid) else { continue }
            let name = URL(fileURLWithPath: path.lowercased()).lastPathComponent
            guard name.hasPrefix("language_server") || name.hasPrefix("language-server") || ["agy", "antigravity-cli"].contains(name),
                  let arguments = arguments(pid) else { continue }
            let command = arguments.joined(separator: " ").lowercased()
            let cli = ["agy", "antigravity-cli"].contains(name)
            guard cli || command.contains("antigravity") else { continue }
            let token = flag("--csrf_token", in: arguments)
            guard cli || token != nil else { continue }
            let extensionPort = flag("--extension_server_port", in: arguments).flatMap(Int.init)
            let extensionToken = flag("--extension_server_csrf_token", in: arguments)
            for port in listeningTCPPorts(pid) {
                result.append(Endpoint(port: port, token: port == extensionPort ? extensionToken ?? token ?? "" : token ?? ""))
            }
        }
        return result
    }
    static func flag(_ name: String, in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == name, index + 1 < arguments.count { return arguments[index + 1] }
            if argument.hasPrefix(name + "=") { return String(argument.dropFirst(name.count + 1)) }
        }
        return nil
    }
    static func allPIDs() -> [Int32] {
        let required = proc_listallpids(nil, 0)
        guard required > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(required) + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(max(0, Int(count)))).filter { $0 > 0 }
    }
    static func identity(_ pid: Int32) -> Identity? {
        var info = proc_bsdinfo()
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard count == MemoryLayout<proc_bsdinfo>.size, info.pbi_uid == getuid() else { return nil }
        return Identity(parent: Int32(bitPattern: info.pbi_ppid), started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }
    private static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let count = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard count > 0 else { return nil }
        return String(bytes: buffer.prefix(Int(count)).prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }
    private static func arguments(_ pid: Int32) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]; var count = 0
        guard sysctl(&mib, u_int(mib.count), nil, &count, nil, 0) == 0, (4...1_048_576).contains(count) else { return nil }
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &count, nil, 0) }
        guard status == 0 else { return nil }
        let argc = data.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        let bytes = Array(data.prefix(count)); var offset = 4
        guard argc > 0, argc <= count, let end = bytes[offset...].firstIndex(of: 0) else { return nil }
        offset = end + 1
        while offset < bytes.count, bytes[offset] == 0 { offset += 1 }
        var arguments: [String] = []
        for _ in 0..<argc {
            guard offset < bytes.count, let end = bytes[offset...].firstIndex(of: 0),
                  let value = String(bytes: bytes[offset..<end], encoding: .utf8) else { return nil }
            arguments.append(value); offset = end + 1
        }
        return arguments
    }
    private static func listeningTCPPorts(_ pid: Int32) -> [Int] {
        let required = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard required > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(required) / stride + 8)
        let actual = descriptors.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard actual > 0 else { return [] }
        var ports: Set<Int> = []
        for descriptor in descriptors.prefix(Int(actual) / stride) where descriptor.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let count = proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
            guard count == MemoryLayout<socket_fdinfo>.size, info.psi.soi_kind == SOCKINFO_TCP,
                  info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport))
            if port > 0 { ports.insert(Int(port)) }
        }
        return ports.sorted()
    }
}
