// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

extension OpenVPNConnection {
    public init(
        _ ctx: PartoutLoggerContext,
        parameters: ConnectionParameters,
        module: OpenVPNModule,
        cachesURL: URL,
        singBoxRunner: SingBoxRunner? = nil,
        ydtunRunner: YdtunRunner? = nil,
        options: Options = .init()
    ) throws {
        guard let configuration = module.configuration else {
            fatalError("Creating session without OpenVPN configuration?")
        }
        pp_log(ctx, .openvpn, .notice, "OpenVPN: Using cross-platform connection")

        // Set up sing-box sidecar if configured
        let sidecar: SingBoxSidecar?
        if let sbConfig = SingBoxSidecar.Configuration(from: configuration),
           let runner = singBoxRunner {
            sidecar = SingBoxSidecar(ctx, configuration: sbConfig, runner: runner)
        } else {
            sidecar = nil
        }

        // Set up ydtun sidecar if configured (mutually exclusive with sing-box)
        let ydtunSidecar: YdtunSidecar?
        if sidecar == nil,
           let ytConfig = YdtunSidecar.Configuration(from: configuration),
           let runner = ydtunRunner {
            ydtunSidecar = YdtunSidecar(ctx, configuration: ytConfig, runner: runner)
        } else {
            if sidecar != nil && configuration.telemostEnabled == true {
                pp_log(ctx, .openvpn, .notice, "Ydtun: Telemost configured but ignored — sing-box takes precedence")
            }
            ydtunSidecar = nil
        }

        // Hardcode portable implementations
        let prng = PlatformPRNG()
        let dns = SimpleDNSResolver {
            POSIXDNSStrategy(hostname: $0)
        }
        let sessionFactory = {
            try await OpenVPNSession(
                ctx,
                configuration: configuration,
                credentials: module.credentials,
                prng: prng,
                cachesURL: cachesURL,
                options: options,
                tlsFactory: {
                    try TLSWrapper.native(with: $0).tls
                },
                dpFactory: {
                    try DataPathWrapper.native(with: $0, prf: $1, prng: $2).dataPath
                }
            )
        }

        try self.init(
            ctx,
            parameters: parameters,
            module: module,
            prng: prng,
            dns: dns,
            singBoxSidecar: sidecar,
            ydtunSidecar: ydtunSidecar,
            sessionFactory: sessionFactory
        )
    }
}
