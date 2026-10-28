//
//  MediaChecker.swift
//  boringNotch
//
//  Created by Alexander on 2025-07-26.
//

import Foundation

final class MediaChecker: Sendable {

    enum MediaCheckerError: Error {
        case missingResources
        case processExecutionFailed
        case timeout
    }

    /// The adapter's test also exits 1 when its test client is slow to start
    /// (e.g. a busy login), so only a failure that repeats counts.
    func checkDeprecationStatus(attempts: Int = 3) async throws -> Bool {
        for attempt in 1...attempts {
            if try await !runAdapterTest() { return false }
            if attempt < attempts { try await Task.sleep(for: .seconds(2)) }
        }
        return true
    }

    private func runAdapterTest() async throws -> Bool {
        try await Task.detached(priority: .userInitiated) {
            guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
                  let nowPlayingTestClientPath = Bundle.main.url(forResource: "MediaRemoteAdapterTestClient", withExtension: nil)?.path,
                  let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
            else {
                throw MediaCheckerError.missingResources
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [scriptURL.path, frameworkPath, nowPlayingTestClientPath, "test"]

            do {
                try process.run()
            } catch {
                throw MediaCheckerError.processExecutionFailed
            }

            // Timeout after 10 seconds
            let didExit: Bool = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    process.waitUntilExit()
                    return true
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    if process.isRunning {
                        process.terminate()
                    }
                    return false // Timed out
                }
                for try await exited in group {
                    if exited {
                        group.cancelAll()
                        return true
                    }
                }
                throw MediaCheckerError.timeout
            }

            if !didExit {
                throw MediaCheckerError.timeout
            }

            let isDeprecated = process.terminationStatus == 1
            return isDeprecated
        }.value
    }
}
