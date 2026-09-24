#if canImport(Network)
import Foundation
import Network

/// The phone remote's socket (Phase 8). Serves the embedded web app and hands
/// authenticated API routes to `handler` (the app's AppState). One request per
/// connection (`Connection: close`), which is all the web app needs.
///
/// Binds loopback only unless `allowLAN` (security invariant 6): Tailscale Serve
/// proxies HTTPS to 127.0.0.1, so the phone works from anywhere without opening
/// the port to the Wi-Fi.
public final class RemoteServer: @unchecked Sendable {
    public typealias Handler = @Sendable (RemoteRoute) async -> HTTPResponse

    public let port: UInt16
    public let allowLAN: Bool
    private let code: @Sendable () -> String
    private let handler: Handler
    private let onStatus: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "vox.remote")
    private var listener: NWListener?
    private var lockout = RemoteLockout()   // only touched on `queue`

    public init(port: UInt16 = 7788, allowLAN: Bool = false,
                code: @escaping @Sendable () -> String,
                onStatus: @escaping @Sendable (String) -> Void = { _ in },
                handler: @escaping Handler) {
        self.port = port
        self.allowLAN = allowLAN
        self.code = code
        self.onStatus = onStatus
        self.handler = handler
    }

    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw RemoteServerError.badPort }
        let listener: NWListener
        if allowLAN {
            listener = try NWListener(using: parameters, on: nwPort)
        } else {
            // Bind the socket itself to 127.0.0.1, not just filter by interface (lsof showed *:7788).
            parameters.requiredInterfaceType = .loopback
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
            listener = try NWListener(using: parameters)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.onStatus("Phone remote on port \(self.port)\(self.allowLAN ? " (home Wi-Fi allowed)" : " (this Mac + Tailscale)").")
            case let .failed(error): self.onStatus("Phone remote stopped: \(error)")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        let address: String
        if case let .hostPort(host, _) = connection.endpoint { address = "\(host)" } else { address = "?" }
        receive(connection, address: address, buffer: Data())
        queue.asyncAfter(deadline: .now() + 15) { connection.cancel() }
    }

    private func receive(_ connection: NWConnection, address: String, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequest.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil || buffer.count > 128 * 1024 { connection.cancel() }
                else { self.receive(connection, address: address, buffer: buffer) }
            case let .invalid(reason):
                self.reply(connection, .error(400, reason))
            case let .complete(request):
                self.respond(to: request, from: address, on: connection)
            }
        }
    }

    private func respond(to request: HTTPRequest, from address: String, on connection: NWConnection) {
        guard let route = RemoteRoute.parse(request) else { return reply(connection, .error(404, "No such endpoint.")) }
        switch route {
        case let .asset(name): return reply(connection, RemoteAssets.response(for: name))
        case .ping: return reply(connection, .json(200, ["name": "Vox", "platform": "mac", "version": 1]))
        default: break
        }
        if lockout.isBlocked(address) { return reply(connection, .error(429, "Too many wrong pairing codes. Wait a minute.")) }
        guard RemotePairing.matches(request.bearerToken, code()) else {
            lockout.fail(address)
            return reply(connection, .error(401, "Pairing code required."))
        }
        lockout.succeed(address)
        let handler = self.handler
        Task {
            let response = await handler(route)
            self.queue.async { self.reply(connection, response) }
        }
    }

    private func reply(_ connection: NWConnection, _ response: HTTPResponse) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
    }
}

public enum RemoteServerError: Error { case badPort }
#endif
