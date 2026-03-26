// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

#if canImport(_PartoutSingBox_C)
internal import _PartoutSingBox_C

/// Swift wrapper around the sing-box C API.
/// Follows the same pattern as WireGuardBackend.
final class SingBoxBackend: @unchecked Sendable {

    func start(configJSON: String) -> Int32 {
        configJSON.withCString { ptr in
            pp_singbox_start(ptr)
        }
    }

    func stop() {
        pp_singbox_stop()
    }

    var isRunning: Bool {
        pp_singbox_is_running() != 0
    }

    func version() -> String {
        guard let ptr = pp_singbox_version() else {
            return "unknown"
        }
        return String(cString: ptr)
    }
}
#endif
