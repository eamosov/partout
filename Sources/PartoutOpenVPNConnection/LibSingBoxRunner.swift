// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

#if canImport(_PartoutSingBox_C)
import Foundation

/// SingBoxRunner implementation that uses the sing-box Go library
/// compiled as a static C library (xcframework).
///
/// This follows the same pattern as WireGuardBackend:
/// Go library -> C API (sing_box.h) -> C bridging (pp_singbox_*) -> Swift wrapper.
public final class LibSingBoxRunner: SingBoxRunner, @unchecked Sendable {
    private let backend = SingBoxBackend()
    private let lock = NSLock()
    private var _isRunning = false

    public init() {}

    public func start(configJSON: String) async throws {
        lock.lock()
        defer { lock.unlock() }

        guard !_isRunning else {
            throw PartoutError(.OpenVPN.connectionFailure)
        }

        let result = backend.start(configJSON: configJSON)
        guard result == 0 else {
            throw PartoutError(.OpenVPN.connectionFailure)
        }
        _isRunning = true
    }

    public func stop() async {
        lock.lock()
        defer { lock.unlock() }

        guard _isRunning else { return }
        backend.stop()
        _isRunning = false
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }
}
#endif
