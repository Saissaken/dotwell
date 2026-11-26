// Verifies a Sparkle EdDSA (Ed25519) signature against a public key.
// Usage: swift scripts/verify-signature.swift <base64-public-key> <base64-signature> <file>
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4,
    let keyData = Data(base64Encoded: args[1]),
    let signature = Data(base64Encoded: args[2]),
    let file = FileManager.default.contents(atPath: args[3])
else {
    FileHandle.standardError.write(Data("usage: verify-signature.swift <public-key> <signature> <file>\n".utf8))
    exit(2)
}

do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    guard key.isValidSignature(signature, for: file) else {
        FileHandle.standardError.write(Data("EdDSA signature does not match SUPublicEDKey\n".utf8))
        exit(1)
    }
    print("EdDSA signature matches SUPublicEDKey")
} catch {
    FileHandle.standardError.write(Data("Invalid public key: \(error)\n".utf8))
    exit(2)
}
