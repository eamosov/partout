// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Manages a sing-box VLESS/Reality sidecar that tunnels OpenVPN traffic
/// through a local TCP listener to bypass censorship.
///
/// The data flow is:
/// ```
/// OpenVPN client → TCP → 127.0.0.1:<localPort> (sing-box direct inbound)
///     → VLESS+REALITY → VLESS server:443
///     → forward → real OpenVPN server
/// ```
public final class SingBoxSidecar: Sendable {

    /// The sing-box configuration parameters parsed from `sb_*` directives.
    public struct Configuration: Sendable {
        /// The VLESS server address (original remote from .ovpn).
        public let serverAddress: String
        public let uuid: String
        public let serverPort: UInt16
        public let tlsServerName: String
        public let tlsPublicKey: String
        public let tlsShortId: String
        /// The real OpenVPN server address that sing-box forwards to.
        public let overrideAddress: String
        public let overridePort: UInt16

        public init(
            serverAddress: String,
            uuid: String,
            serverPort: UInt16 = 443,
            tlsServerName: String,
            tlsPublicKey: String,
            tlsShortId: String,
            overrideAddress: String,
            overridePort: UInt16
        ) {
            self.serverAddress = serverAddress
            self.uuid = uuid
            self.serverPort = serverPort
            self.tlsServerName = tlsServerName
            self.tlsPublicKey = tlsPublicKey
            self.tlsShortId = tlsShortId
            self.overrideAddress = overrideAddress
            self.overridePort = overridePort
        }
    }

    private let ctx: PartoutLoggerContext
    private let configuration: Configuration
    private let runner: SingBoxRunner

    /// Callback to update connection sub-status in UI.
    nonisolated(unsafe) public var onSubStatus: (@Sendable (String) -> Void)?

    nonisolated(unsafe) private var _localPort: UInt16 = 0

    /// The local TCP port that OpenVPN should connect to.
    public var localPort: UInt16 {
        _localPort
    }

    public init(_ ctx: PartoutLoggerContext, configuration: Configuration, runner: SingBoxRunner) {
        self.ctx = ctx
        self.configuration = configuration
        self.runner = runner
    }

    /// Starts the sing-box sidecar and returns the local port for OpenVPN to connect to.
    public func start() async throws -> UInt16 {
        // Stop any existing instance first (matches SingBoxProcess.start in ics-openvpn)
        if runner.isRunning {
            await stop()
        }

        let port = try findFreePort()
        let configJSON = generateConfig(listenPort: port)

        onSubStatus?("SingBox: starting...")
        pp_log(ctx, .openvpn, .notice, "SingBox: Starting sidecar on 127.0.0.1:\(port)")
        pp_log(ctx, .openvpn, .info, "SingBox: Override \(configuration.overrideAddress):\(configuration.overridePort)")
        pp_log(ctx, .openvpn, .debug, "SingBox: Config JSON: \(configJSON)")

        try await runner.start(configJSON: configJSON)

        // Wait for port to become available (matches SingBoxProcess.waitForPort in ics-openvpn)
        try await waitForPort(port, timeout: 10.0)

        _localPort = port
        onSubStatus?("SingBox: ready")
        pp_log(ctx, .openvpn, .notice, "SingBox: Sidecar ready on port \(port)")
        return port
    }

    /// Stops the sing-box sidecar.
    public func stop() async {
        pp_log(ctx, .openvpn, .notice, "SingBox: Stopping sidecar")
        await runner.stop()
        _localPort = 0
    }

    /// Whether the sidecar is currently running.
    public var isRunning: Bool {
        runner.isRunning
    }
}

// MARK: - SingBox Configuration from OpenVPN Configuration

extension SingBoxSidecar.Configuration {

    /// Creates a sing-box configuration from OpenVPN configuration, extracting the `sb_*` fields.
    /// Returns nil if sing-box is not enabled or required fields are missing.
    /// Creates a sing-box configuration from OpenVPN configuration.
    ///
    /// The VLESS server address comes from the original `remote` in .ovpn.
    /// The override address (real OpenVPN server) comes from `sb_override_address`
    /// or falls back to the remote address if not specified.
    ///
    /// Matching ics-openvpn's SingBoxProcess.generateConfig():
    /// - `server` = conn.mServerName (original remote = VLESS proxy)
    /// - `override_address` = conn.mSingBoxOverrideAddress (real OpenVPN behind VLESS)
    /// Note: does NOT check singBoxEnabled — the caller decides whether sing-box should be used.
    public init?(from openvpn: OpenVPN.Configuration) {
        guard let uuid = openvpn.singBoxUUID,
              let tlsServerName = openvpn.singBoxTLSServerName,
              let tlsPublicKey = openvpn.singBoxTLSPublicKey,
              let tlsShortId = openvpn.singBoxTLSShortId else {
            return nil
        }

        // VLESS server = original remote address from .ovpn
        guard let firstRemote = openvpn.remotes?.first else {
            return nil
        }
        let serverAddress = firstRemote.address.rawValue

        // Override = real OpenVPN server (sb_override_address), or same as remote if not set
        let overrideAddress = openvpn.singBoxOverrideAddress ?? serverAddress
        let overridePort = openvpn.singBoxOverridePort ?? firstRemote.proto.port

        self.init(
            serverAddress: serverAddress,
            uuid: uuid,
            serverPort: openvpn.singBoxServerPort ?? 443,
            tlsServerName: tlsServerName,
            tlsPublicKey: tlsPublicKey,
            tlsShortId: tlsShortId,
            overrideAddress: overrideAddress,
            overridePort: overridePort
        )
    }
}

// MARK: - Config Generation

private extension SingBoxSidecar {

    /// Generates the sing-box JSON configuration matching ics-openvpn's SingBoxProcess.generateConfig().
    func generateConfig(listenPort: UInt16) -> String {
        """
        {
          "log": {
            "level": "debug"
          },
          "inbounds": [
            {
              "type": "direct",
              "tag": "direct-in",
              "listen": "127.0.0.1",
              "listen_port": \(listenPort),
              "network": "tcp",
              "override_address": "\(configuration.overrideAddress)",
              "override_port": \(configuration.overridePort)
            }
          ],
          "outbounds": [
            {
              "type": "vless",
              "tag": "vless-out",
              "server": "\(configuration.serverAddress)",
              "server_port": \(configuration.serverPort),
              "uuid": "\(configuration.uuid)",
              "flow": "",
              "tls": {
                "enabled": true,
                "server_name": "\(configuration.tlsServerName)",
                "utls": {
                  "enabled": true,
                  "fingerprint": "chrome"
                },
                "reality": {
                  "enabled": true,
                  "public_key": "\(configuration.tlsPublicKey)",
                  "short_id": "\(configuration.tlsShortId)"
                }
              }
            }
          ]
        }
        """
    }
}

// MARK: - Port Utilities

private extension SingBoxSidecar {

    func findFreePort() throws -> UInt16 {
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketFD >= 0 else {
            throw PartoutError(.OpenVPN.connectionFailure)
        }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // Let the OS pick a free port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw PartoutError(.OpenVPN.connectionFailure)
        }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let gsnResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &len)
            }
        }
        guard gsnResult == 0 else {
            throw PartoutError(.OpenVPN.connectionFailure)
        }

        let port = UInt16(bigEndian: addr.sin_port)
        guard port > 0 else {
            throw PartoutError(.OpenVPN.connectionFailure)
        }
        return port
    }

    func waitForPort(_ port: UInt16, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        let interval: UInt64 = 200_000_000 // 200ms

        while Date() < deadline {
            if canConnect(to: port) {
                return
            }
            try await Task.sleep(nanoseconds: interval)
        }
        throw PartoutError(.OpenVPN.connectionFailure)
    }

    func canConnect(to port: UInt16) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
