import CryptoKit
import Foundation

// Public data only; this verifier never reads a signing key or Keychain item.
let arguments = CommandLine.arguments
if arguments.count != 4 { fatalError("Usage: verify-update-signature.swift archive signature public-key") }
let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
guard let signature = Data(base64Encoded: arguments[2]),
      let rawKey = Data(base64Encoded: arguments[3]) else { fatalError("Invalid base64 signature/key") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
guard key.isValidSignature(signature, for: archive) else { fatalError("Invalid update signature") }
print("Verified Ed25519: \(URL(fileURLWithPath: arguments[1]).lastPathComponent)")
