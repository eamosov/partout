// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

#if canImport(_PartoutYdtun_C)
internal import _PartoutYdtun_C

/// Swift wrapper around the ydtun C API.
final class YdtunBackend: @unchecked Sendable {

    /// Set up log callback before start. Logs are forwarded to pp_log.
    func installLogCallback() {
        pp_ydtun_set_log_callback { level, message in
            guard let message else { return }
            let str = String(cString: message)
            // Forward to Passepartout logging system via global context
            // Rust levels: 0=error, 1=warn, 2=info, 3=debug, 4=trace
            let ppLevel: DebugLog.Level
            switch level {
            case 0:
                ppLevel = .error
            case 1:
                ppLevel = .notice
            case 2:
                ppLevel = .info
            default:
                ppLevel = .debug
            }
            pp_log_g(.openvpn, ppLevel, str)
        }
    }

    func start(args: String) -> Int32 {
        args.withCString { ptr in
            pp_ydtun_start(ptr)
        }
    }

    func stop() {
        pp_ydtun_stop()
    }

    var isRunning: Bool {
        pp_ydtun_is_running() != 0
    }
}
#endif
