import Foundation

/// Signs of a jailbroken phone, named for the attestation report.
enum JailbreakCheck {
    private static let paths = [
        "/Applications/Cydia.app", "/Applications/Sileo.app", "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/usr/sbin/sshd", "/etc/apt", "/private/var/lib/apt", "/var/jb",
    ]

    static var signals: [String] {
        #if targetEnvironment(simulator)
        []
        #else
        paths.filter { FileManager.default.fileExists(atPath: $0) } + (canWriteOutsideSandbox ? ["sandbox-write"] : [])
        #endif
    }

    private static var canWriteOutsideSandbox: Bool {
        let path = "/private/\(UUID().uuidString)"
        guard (try? Data().write(to: URL(fileURLWithPath: path))) != nil else { return false }
        try? FileManager.default.removeItem(atPath: path)
        return true
    }
}
