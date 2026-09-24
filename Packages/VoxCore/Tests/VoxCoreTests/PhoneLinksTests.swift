import XCTest
@testable import VoxCore

final class PhoneLinksTests: XCTestCase {
    let interfaces: [(name: String, address: String)] = [
        ("lo0", "127.0.0.1"), ("en0", "192.168.100.10"), ("en5", "169.254.3.4"),
        ("utun4", "100.101.102.103"), ("utun7", "10.8.0.2"),
    ]

    func testLoopbackOnlyHasNoWiFiLinks() {
        let links = PhoneLinks.make(code: "abc", port: 7788, allowLAN: false, tailscaleName: nil, tailscaleServing: false,
                                    interfaces: interfaces, localHostName: "Matts-MacBook-Pro")
        XCTAssertEqual(links, [])
    }

    func testTailscaleNeedsServeToBeOn() {
        let off = PhoneLinks.make(code: "abc", port: 7788, allowLAN: false, tailscaleName: "mac.tail1.ts.net.", tailscaleServing: false,
                                  interfaces: interfaces, localHostName: nil)
        XCTAssertEqual(off, [])
        let on = PhoneLinks.make(code: "abc", port: 7788, allowLAN: false, tailscaleName: "mac.tail1.ts.net.", tailscaleServing: true,
                                 interfaces: interfaces, localHostName: nil)
        XCTAssertEqual(on.map(\.url), ["https://mac.tail1.ts.net/#pair=abc"])
        XCTAssertEqual(on.first?.kind, .tailscale)
    }

    func testWiFiOrderSkipsLinkLocalAndOtherVPNs() {
        let links = PhoneLinks.make(code: "abc", port: 7788, allowLAN: true, tailscaleName: "mac.tail1.ts.net", tailscaleServing: true,
                                    interfaces: interfaces, localHostName: "Matts-MacBook-Pro")
        XCTAssertEqual(links.map(\.base), [
            "https://mac.tail1.ts.net/",
            "http://192.168.100.10:7788/",
            "http://Matts-MacBook-Pro.local:7788/",
            "http://100.101.102.103:7788/",
        ])
        XCTAssertEqual(links.map(\.kind), [.tailscale, .wifi, .bonjour, .wifi])
    }

    func testServeStatusParsing() {
        let serving = #"{"TCP":{"443":{"HTTPS":true}},"Web":{"mac.tail1.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:7788"}}}}}"#
        XCTAssertTrue(TailscaleServe.proxies(port: 7788, statusJSON: Data(serving.utf8)))
        let other = #"{"Web":{"mac.tail1.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3000"}}}}}"#
        XCTAssertFalse(TailscaleServe.proxies(port: 7788, statusJSON: Data(other.utf8)))
        XCTAssertTrue(TailscaleServe.proxies(port: 7788, statusJSON: Data(#"{"TCP":{"443":{"TCPForward":"localhost:7788"}}}"#.utf8)))
        XCTAssertFalse(TailscaleServe.proxies(port: 7788, statusJSON: Data("{}".utf8)))
        XCTAssertFalse(TailscaleServe.proxies(port: 7788, statusJSON: Data("No serve config".utf8)))
    }

    func testEnableLinkAndDNSName() {
        let out = "Serve is not enabled on your tailnet.\nTo enable, visit:\n\n         https://login.tailscale.com/f/serve?node=abc123\n"
        XCTAssertEqual(TailscaleServe.enableLink(in: out)?.absoluteString, "https://login.tailscale.com/f/serve?node=abc123")
        XCTAssertNil(TailscaleServe.enableLink(in: "Available within your tailnet: https://mac.tail1.ts.net/"))

        let running = #"{"BackendState":"Running","Self":{"DNSName":"mac.tail1.ts.net."}}"#
        XCTAssertEqual(TailscaleServe.dnsName(statusJSON: Data(running.utf8)), "mac.tail1.ts.net")
        let stopped = #"{"BackendState":"Stopped","Self":{"DNSName":"mac.tail1.ts.net."}}"#
        XCTAssertNil(TailscaleServe.dnsName(statusJSON: Data(stopped.utf8)))
    }
}
