import Foundation

/// One address a phone can open to reach Vox (Phase 8).
public struct PhoneLink: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case tailscale   // https://<mac>.<tailnet>.ts.net: HTTPS (voice on iPhone), works away from home
        case wifi        // http://192.168.x.y:7788: home Wi-Fi only, no voice button on iPhone
        case bonjour     // http://<mac>.local:7788: same as wifi, but survives the router handing out a new IP
    }
    public let kind: Kind
    /// Address without the pairing fragment (for reachability checks and for showing on screen).
    public let base: String
    /// What goes in the QR code: `base` + `#pair=<code>` (fragments are never sent to a server).
    public let url: String
    public var id: String { base }
}

public enum PhoneLinks {
    /// Links in the order the QR code should prefer them.
    /// - interfaces: (BSD name, IPv4) pairs, e.g. ("en0", "192.168.1.20").
    /// - Wi-Fi links only appear when `allowLAN` is on, because otherwise the server only listens on 127.0.0.1.
    public static func make(code: String, port: UInt16, allowLAN: Bool,
                            tailscaleName: String?, tailscaleServing: Bool,
                            interfaces: [(name: String, address: String)],
                            localHostName: String?) -> [PhoneLink] {
        var links: [PhoneLink] = []
        func add(_ kind: PhoneLink.Kind, _ base: String) {
            guard !links.contains(where: { $0.base == base }) else { return }
            links.append(PhoneLink(kind: kind, base: base, url: base + "#pair=" + code))
        }
        if let name = tailscaleName?.trimmingCharacters(in: CharacterSet(charactersIn: ". ")), !name.isEmpty, tailscaleServing {
            add(.tailscale, "https://\(name)/")
        }
        guard allowLAN else { return links }
        let usable = interfaces.filter { isUsableLAN($0.address) }
        // Ethernet/Wi-Fi (en*) first; utun only when it's Tailscale's own 100.64.0.0/10 address (other utuns are VPNs).
        for item in usable where item.name.hasPrefix("en") { add(.wifi, "http://\(item.address):\(port)/") }
        if let host = localHostName?.trimmingCharacters(in: .whitespaces), !host.isEmpty, !usable.isEmpty {
            let label = host.hasSuffix(".local") ? host : host + ".local"
            add(.bonjour, "http://\(label):\(port)/")
        }
        for item in usable where item.name.hasPrefix("utun") && isTailscaleIP(item.address) {
            add(.wifi, "http://\(item.address):\(port)/")
        }
        return links
    }

    static func octets(_ ip: String) -> [Int]? {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts.allSatisfy({ (0...255).contains($0) }) ? parts : nil
    }

    static func isUsableLAN(_ ip: String) -> Bool {
        guard let o = octets(ip) else { return false }
        return o[0] != 127 && !(o[0] == 169 && o[1] == 254) && o[0] != 0
    }

    static func isTailscaleIP(_ ip: String) -> Bool {
        guard let o = octets(ip) else { return false }
        return o[0] == 100 && (64...127).contains(o[1])
    }
}

/// Reading `tailscale` output. The app runs the CLI with fixed arguments only.
public enum TailscaleServe {
    /// True when `tailscale serve status --json` shows a handler proxying to Vox's local port.
    public static func proxies(port: UInt16, statusJSON: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: statusJSON) else { return false }
        let targets = ["127.0.0.1:\(port)", "localhost:\(port)"]
        func walk(_ value: Any) -> Bool {
            if let text = value as? String {
                var t = text.lowercased()
                for prefix in ["http://", "https+insecure://", "https://", "tcp://"] where t.hasPrefix(prefix) { t.removeFirst(prefix.count) }
                while t.hasSuffix("/") { t.removeLast() }
                return targets.contains(t)
            }
            if let dict = value as? [String: Any] { return dict.values.contains(where: walk) }
            if let list = value as? [Any] { return list.contains(where: walk) }
            return false
        }
        return walk(json)
    }

    /// `tailscale serve` prints a login.tailscale.com link and waits when HTTPS isn't enabled for the tailnet yet.
    public static func enableLink(in output: String) -> URL? {
        for word in output.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }) {
            let text = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'()<>.,"))
            if text.hasPrefix("https://login.tailscale.com/"), let url = URL(string: text) { return url }
        }
        return nil
    }

    /// DNSName of this machine from `tailscale status --json`, without the trailing dot. Nil when logged out/stopped.
    public static func dnsName(statusJSON: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: statusJSON) as? [String: Any] else { return nil }
        if let state = json["BackendState"] as? String, state != "Running" { return nil }
        guard let me = json["Self"] as? [String: Any], let name = me["DNSName"] as? String else { return nil }
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        return trimmed.isEmpty ? nil : trimmed
    }
}
