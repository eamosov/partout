// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import Foundation

/// Manages a ydtun sidecar that tunnels OpenVPN traffic through
/// Telemost WebRTC infrastructure to bypass DPI-based censorship.
///
/// The data flow is:
/// ```
/// OpenVPN client → TCP → 127.0.0.1:<localPort> (ydtun port-forward)
///     → WebRTC/KCP → Telemost TURN → VPN server
/// ```
public final class YdtunSidecar: Sendable {

    /// The ydtun configuration parameters parsed from `telemost_*` directives.
    public struct Configuration: Sendable {
        public let telemostUrls: String
        public let tunnelKey: String?
        public let forceTcpRelay: Bool
        public let logLevel: Int
        public let netGateway: String?

        public init(
            telemostUrls: String,
            tunnelKey: String?,
            forceTcpRelay: Bool = false,
            logLevel: Int = 0,
            netGateway: String? = nil
        ) {
            self.telemostUrls = telemostUrls
            self.tunnelKey = tunnelKey
            self.forceTcpRelay = forceTcpRelay
            self.logLevel = logLevel
            self.netGateway = netGateway
        }
    }

    private let ctx: PartoutLoggerContext
    private let configuration: Configuration
    private let runner: YdtunRunner
    private let lock = NSLock()

    /// Callback to update connection sub-status in UI.
    nonisolated(unsafe) public var onSubStatus: (@Sendable (String) -> Void)?

    /// Callback to report alive/dead status for health badge.
    nonisolated(unsafe) public var onAliveStatus: (@Sendable (Bool) -> Void)?

    /// Callback to report API port for status page.
    nonisolated(unsafe) public var onApiPort: (@Sendable (UInt16) -> Void)?

    private var _localPort: UInt16 = 0
    private var _apiPort: UInt16 = 0
    private var _healthTask: Task<Void, Never>?
    private var _stopped = false

    /// The local TCP port that OpenVPN should connect to.
    public var localPort: UInt16 {
        lock.withLock { _localPort }
    }

    /// The local API port for health checks.
    public var apiPort: UInt16 {
        lock.withLock { _apiPort }
    }

    public init(_ ctx: PartoutLoggerContext, configuration: Configuration, runner: YdtunRunner) {
        self.ctx = ctx
        self.configuration = configuration
        self.runner = runner
    }

    /// Starts the ydtun sidecar and waits for KCP readiness. Returns the local port for OpenVPN to connect to.
    public func start() async throws -> UInt16 {
        if runner.isRunning {
            await stop()
        }

        let port = try findFreePort()
        let api = try findFreePort()
        let args = buildArguments(localPort: port, apiPort: api)
        let env = buildEnvironment()

        pp_log(ctx, .openvpn, .notice, "Ydtun: Starting sidecar on 127.0.0.1:\(port), API on \(api)")
        // Log each arg separately to see exact values
        for (i, arg) in args.enumerated() {
            if i > 0 && args[i - 1] == "--tunnel-key" {
                pp_log(ctx, .openvpn, .notice, "Ydtun: arg[\(i)]=***")
            } else {
                pp_log(ctx, .openvpn, .notice, "Ydtun: arg[\(i)]=\(arg)")
            }
        }

        onSubStatus?("Telemost: starting...")
        do {
            try await runner.start(arguments: args, environment: env)
            pp_log(ctx, .openvpn, .notice, "Ydtun: runner.start() succeeded, isRunning=\(runner.isRunning)")
        } catch {
            pp_log(ctx, .openvpn, .error, "Ydtun: runner.start() failed, errorCode=\(runner.lastErrorCode) (-4=configParse,-5=tunnelCfg,-6=runtime,-7=tunnelStart,-99=panic)")
            onSubStatus?("Telemost: start failed")
            throw error
        }

        // Report API port immediately so status page is available
        lock.withLock {
            _apiPort = api
            _stopped = false
        }
        onApiPort?(api)

        // Start health polling immediately — badge shows [tm:dead] until KCP is ready
        startHealthPolling(apiPort: api)

        // Wait for API port first (available immediately after ydtun_start)
        onSubStatus?("Telemost: waiting API...")
        try await waitForPort(api, timeout: 10.0)

        // Wait for KCP tunnel readiness via REST API (WebRTC + KCP handshake)
        onSubStatus?("Telemost: connecting...")
        try await waitForKcpAlive(apiPort: api)

        // Wait for pf-listen port (opened after KCP ready)
        onSubStatus?("Telemost: waiting port...")
        try await waitForPort(port, timeout: 30.0)
        onSubStatus?("Telemost: ready")

        lock.withLock { _localPort = port }
        pp_log(ctx, .openvpn, .notice, "Ydtun: Sidecar ready on port \(port)")
        return port
    }

    /// Stops the ydtun sidecar.
    public func stop() async {
        pp_log(ctx, .openvpn, .notice, "Ydtun: Stopping sidecar")
        lock.withLock {
            _stopped = true
            _healthTask?.cancel()
            _healthTask = nil
            _localPort = 0
            _apiPort = 0
        }
        // Nil out callbacks to prevent stale env writes after stop
        onSubStatus = nil
        onAliveStatus = nil
        onApiPort = nil
        await runner.stop()
    }

    private func startHealthPolling(apiPort: UInt16) {
        lock.withLock { _healthTask?.cancel() }
        let newTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.lock.withLock({ self._stopped }) else { break }
                let alive = await Self.checkAliveRequest(apiPort: apiPort)
                guard !Task.isCancelled, !self.lock.withLock({ self._stopped }) else { break }
                self.onAliveStatus?(alive)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        lock.withLock { _healthTask = newTask }
    }

    /// Whether the sidecar is currently running.
    public var isRunning: Bool {
        runner.isRunning
    }

    /// Quick health check via /status endpoint (2s timeout).
    public func checkAlive() async -> Bool {
        let port = lock.withLock { _apiPort }
        guard port > 0 else { return false }
        return await Self.checkAliveRequest(apiPort: port)
    }

    /// Static helper — no self capture needed.
    private static func checkAliveRequest(apiPort: UInt16) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(apiPort)/status") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = String(data: data, encoding: .utf8) ?? ""
            return json.contains("\"alive\":true") || json.contains("\"alive\": true")
        } catch {
            return false
        }
    }
}

// MARK: - Ydtun Configuration from OpenVPN Configuration

extension YdtunSidecar.Configuration {

    /// Creates a ydtun configuration from OpenVPN configuration, extracting the `telemost_*` fields.
    /// Returns nil if required fields are missing (telemostUrls).
    /// Note: does NOT check telemostEnabled — the caller decides whether ydtun should be used.
    public init?(from openvpn: OpenVPN.Configuration) {
        guard let urls = openvpn.telemostUrls, !urls.isEmpty else {
            return nil
        }
        self.init(
            telemostUrls: urls,
            tunnelKey: openvpn.telemostTunnelKey,
            forceTcpRelay: openvpn.telemostForceTcpRelay ?? false,
            logLevel: openvpn.telemostLogLevel ?? 0,
            netGateway: openvpn.telemostNetGateway
        )
    }
}

// MARK: - Arguments

private extension YdtunSidecar {

    func buildArguments(localPort: UInt16, apiPort: UInt16) -> [String] {
        var args = [
            "--no-color",
            "--mode", "port-forward",
            "--pf-listen", "127.0.0.1:\(localPort)",
            "--telemost-urls", configuration.telemostUrls,
            "--api-addr", "127.0.0.1:\(apiPort)"
        ]
        if let key = configuration.tunnelKey, !key.isEmpty {
            args += ["--tunnel-key", key]
        }
        // Note: netGateway is handled at route-exclusion level, not passed to ydtun CLI
        if configuration.forceTcpRelay {
            args += ["--force-tcp-relay"]
        }
        switch configuration.logLevel {
        case 0:
            args += ["-v"]  // default: debug level for visibility
        case 1:
            args += ["-v"]
        case 2...:
            args += ["-vv"]
        default:
            args += ["-v"]
        }
        return args
    }

    func buildEnvironment() -> [String: String] {
        ["RUST_LOG": "ydtun=info"]
    }
}

// MARK: - KCP Readiness

private extension YdtunSidecar {

    /// Waits for KCP tunnel readiness via REST API (up to 120 seconds).
    func waitForKcpAlive(apiPort: UInt16) async throws {
        pp_log(ctx, .openvpn, .notice, "Ydtun: Waiting for KCP tunnel readiness...")
        guard let url = URL(string: "http://127.0.0.1:\(apiPort)/alive/kcp") else {
            throw PartoutError(.OpenVPN.connectionFailure)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 130

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                pp_log(ctx, .openvpn, .error, "Ydtun: KCP alive check returned non-200")
                throw PartoutError(.OpenVPN.connectionFailure)
            }
            pp_log(ctx, .openvpn, .notice, "Ydtun: KCP tunnel is alive")
        } catch let error as PartoutError {
            throw error
        } catch {
            pp_log(ctx, .openvpn, .error, "Ydtun: KCP alive check failed: \(error)")
            throw PartoutError(.OpenVPN.connectionFailure)
        }
    }
}

// MARK: - Port Utilities

private extension YdtunSidecar {

    func findFreePort() throws -> UInt16 {
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketFD >= 0 else {
            throw PartoutError(.OpenVPN.connectionFailure)
        }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
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
        let interval: UInt64 = 200_000_000

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
