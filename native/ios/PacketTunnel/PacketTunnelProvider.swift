import NetworkExtension
import Darwin
import LibXray // LibXray.xcframework built from XTLS/libXray (apple gomobile)

/// iOS packet tunnel. libXray (one Go runtime) lives only in THIS extension process.
/// Config JSON arrives from the app via NETunnelProviderProtocol.providerConfiguration["config"].
/// STATUS: source only - the Xcode extension target still has to be wired (see native/ios/README.md).
class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let json = proto.providerConfiguration?["config"] as? String,
              var cfg = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
            completionHandler(NSError(domain: "io.surprise.vpn", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing config"]))
            return
        }
        let mtu = (proto.providerConfiguration?["mtu"] as? Int) ?? 1500

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.10.14.2")
        let v4 = NEIPv4Settings(addresses: ["10.10.14.1"], subnetMasks: ["255.255.255.252"])
        v4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = v4
        let v6 = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [126])
        v6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = v6
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1"])
        settings.mtu = NSNumber(value: mtu)

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error { completionHandler(error); return }
            guard let self = self, let fd = self.tunFd() else {
                completionHandler(NSError(domain: "io.surprise.vpn", code: 2, userInfo: [NSLocalizedDescriptionKey: "utun fd not found"]))
                return
            }
            var env = (cfg["env"] as? [String: String]) ?? [:]
            env["xray.tun.fd"] = String(fd)
            cfg["env"] = env
            guard let data = try? JSONSerialization.data(withJSONObject: cfg),
                  let xrayJson = String(data: data, encoding: .utf8) else {
                completionHandler(NSError(domain: "io.surprise.vpn", code: 3, userInfo: nil)); return
            }
            let req: [String: Any] = ["apiVersion": 3, "method": "runXray", "payload": ["xrayJson": xrayJson]]
            let reqData = try! JSONSerialization.data(withJSONObject: req)
            // gomobile exposes Go's Invoke(string) string; adjust the symbol if the generated header differs.
            let resp = LibXrayInvoke(String(data: reqData, encoding: .utf8))
            if let d = resp.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               (j["success"] as? Bool) == true {
                completionHandler(nil)
            } else {
                completionHandler(NSError(domain: "io.surprise.vpn", code: 4, userInfo: [NSLocalizedDescriptionKey: resp]))
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        let req = "{\"apiVersion\":3,\"method\":\"stopXray\",\"payload\":{}}"
        _ = LibXrayInvoke(req)
        completionHandler()
    }

    /// Finds the utun file descriptor owned by this extension.
    private func tunFd() -> Int32? {
        var info = ctl_info()
        withUnsafeMutablePointer(to: &info.ctl_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) {
                _ = strcpy($0, "com.apple.net.utun_control")
            }
        }
        for fd: Int32 in 0...1024 {
            var addr = sockaddr_ctl()
            var ret: Int32 = -1
            var len = socklen_t(MemoryLayout.size(ofValue: addr))
            withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ret = getpeername(fd, $0, &len) }
            }
            if ret != 0 || addr.sc_family != AF_SYSTEM { continue }
            if info.ctl_id == 0 {
                ret = ioctl(fd, CTLIOCGINFO, &info)
                if ret != 0 { continue }
            }
            if addr.sc_id == info.ctl_id { return fd }
        }
        return nil
    }
}
