import Foundation
import Network
import Darwin

/// User-private Unix socket. Status messages are bounded; approvals retain their connection.
@MainActor
final class AgentHookServer {
    static var socketPath: String { "/tmp/boringnotch-\(getuid())/agent.sock" }
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    var onEvent: ((Data, @escaping (Data) -> Void, UUID) -> Void)?
    var onDisconnect: ((UUID) -> Void)?
    var onStatus: ((String) -> Void)?
    private var ownsSocket = false

    func start() throws {
        guard listener == nil else { return }
        let directory = (Self.socketPath as NSString).deletingLastPathComponent
        var info = stat()
        if lstat(directory, &info) == 0 {
            guard info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFDIR else {
                throw NSError(domain: "NotchHook", code: 1, userInfo: [NSLocalizedDescriptionKey: "Agent 通信目录不属于当前用户。"])
            }
        } else { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        chmod(directory, 0o700)
        // A second instance must not steal a running server's socket.
        if FileManager.default.fileExists(atPath: Self.socketPath) {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            defer { if fd >= 0 { close(fd) } }
            var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(Self.socketPath.utf8CString)
            withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
            let alive = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 } }
            guard !alive else { throw NSError(domain: "NotchHook", code: 2, userInfo: [NSLocalizedDescriptionKey: "已有另一个 Boring Notch 正在接收 Agent 事件。"]) }
            guard lstat(Self.socketPath, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFSOCK else {
                throw NSError(domain: "NotchHook", code: 3, userInfo: [NSLocalizedDescriptionKey: "Agent 通信路径被其他文件占用。"])
            }
            unlink(Self.socketPath)
        }
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        parameters.requiredLocalEndpoint = .unix(path: Self.socketPath)
        let listener = try NWListener(using: parameters)
        self.listener = listener; ownsSocket = true
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: chmod(Self.socketPath, 0o600); self?.onStatus?("Agent 服务已就绪")
                case .failed: self?.onStatus?("Agent 通信服务启动失败"); self?.stop()
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.start(queue: .main)
    }
    func stop() {
        listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        if ownsSocket { unlink(Self.socketPath); ownsSocket = false }
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 64 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { @MainActor in self?.finish(id) } }
            if case .cancelled = state { Task { @MainActor in self?.finish(id) } }
        }
        connection.start(queue: .main)
        receive(connection, id: id, accumulated: Data())
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard let self, self.connections[id] != nil else { return }
            self.reply(Data("{}".utf8), id: id)
        }
    }
    private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var buffer = accumulated; if let data { buffer.append(data) }
                guard buffer.count <= 4 * 1024 * 1024, error == nil else { self.finish(id); return }
                if complete {
                    self.onEvent?(buffer, { [weak self] response in self?.reply(response, id: id) }, id)
                } else { self.receive(connection, id: id, accumulated: buffer) }
            }
        }
    }
    private func reply(_ data: Data, id: UUID) {
        guard let connection = connections[id] else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.finish(id) }
        })
    }
    private func finish(_ id: UUID) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.cancel(); onDisconnect?(id)
    }
}
