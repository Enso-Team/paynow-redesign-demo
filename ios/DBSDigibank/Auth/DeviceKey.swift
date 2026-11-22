import Foundation
import LocalAuthentication
import Security

/// A P-256 key that proves this iPhone to the auth service.
/// - `full` opens full sessions. On a device it lives in the Secure Enclave behind `.biometryCurrentSet`.
/// - `peek` opens Peek passes only. It has no biometry and is usable after first unlock, so Peek never asks Face ID.
/// On the simulator both are software keys in the Keychain.
struct DeviceKey: Sendable {
    let tag: Data
    let biometry: Bool

    static let full = DeviceKey(tag: Data("sg.demo.digibank.devicekey".utf8), biometry: true)
    static let peek = DeviceKey(tag: Data("sg.demo.digibank.peekkey".utf8), biometry: false)

    enum KeyError: Error, LocalizedError {
        case keychain(OSStatus)
        case cf(String)

        var errorDescription: String? {
            switch self {
            case .keychain(let status): "Keychain error \(status)"
            case .cf(let message): message
            }
        }
    }

    var exists: Bool { load(context: nil) != nil }

    func load(context: LAContext?) -> SecKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        if let context { query[kSecUseAuthenticationContext as String] = context }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let item else { return nil }
        return (item as! SecKey)
    }

    /// Creates the key and returns its public half as base64 X9.63.
    func create() throws -> String {
        delete()
        var privateAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: tag,
        ]
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        let accessible = biometry ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #if targetEnvironment(simulator)
        privateAttrs[kSecAttrAccessible as String] = accessible
        #else
        var cfError: Unmanaged<CFError>?
        let flags: SecAccessControlCreateFlags = biometry ? [.privateKeyUsage, .biometryCurrentSet] : [.privateKeyUsage]
        guard let access = SecAccessControlCreateWithFlags(nil, accessible, flags, &cfError)
        else { throw KeyError.cf(cfError?.takeRetainedValue().localizedDescription ?? "access control") }
        privateAttrs[kSecAttrAccessControl as String] = access
        attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        #endif
        attributes[kSecPrivateKeyAttrs as String] = privateAttrs

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeyError.cf(error?.takeRetainedValue().localizedDescription ?? "key generation failed")
        }
        return try Self.publicKeyBase64(key)
    }

    static func publicKeyBase64(_ privateKey: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
        else { throw KeyError.cf(error?.takeRetainedValue().localizedDescription ?? "no public key") }
        return data.base64EncodedString()
    }

    /// Signs with ECDSA SHA-256 and returns the DER signature.
    func sign(_ message: Data, context: LAContext?) throws -> Data {
        guard let key = load(context: context) else { throw KeyError.keychain(errSecItemNotFound) }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, message as CFData, &error)
        else { throw KeyError.cf(error?.takeRetainedValue().localizedDescription ?? "sign failed") }
        return signature as Data
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// The device's binding to the auth service.
/// Both keys are registered: the device key as a full device and the Peek key as a peek-only device.
struct DeviceBinding: Codable, Sendable {
    var deviceId: String
    var peekDeviceId: String
    var userId: String

    private static let key = "deviceBinding"

    static var current: DeviceBinding? {
        guard DeviceKey.full.exists, DeviceKey.peek.exists,
              let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DeviceBinding.self, from: data)
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        DeviceKey.full.delete()
        DeviceKey.peek.delete()
    }
}
