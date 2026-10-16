import Foundation
import CryptoKit

final class EnclosureReader: NSObject, XMLParserDelegate {
    let filename: String
    var signature: String?
    var length: Int?
    init(filename: String) { self.filename = filename }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        guard elementName == "enclosure", let url = attributes["url"],
              URL(string: url)?.lastPathComponent == filename else { return }
        signature = attributes["sparkle:edSignature"]
        length = attributes["length"].flatMap(Int.init)
    }
}

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: verify-appcast.swift APPCAST ARCHIVE PUBLIC_KEY\n", stderr)
    exit(1)
}
let args = CommandLine.arguments
let archiveURL = URL(fileURLWithPath: args[2])
let reader = EnclosureReader(filename: archiveURL.lastPathComponent)
let parser = XMLParser(data: try Data(contentsOf: URL(fileURLWithPath: args[1])))
parser.delegate = reader
guard parser.parse(), let encoded = reader.signature, let signature = Data(base64Encoded: encoded),
      let publicData = Data(base64Encoded: args[3]) else { fatalError("Invalid appcast or public key") }
let archive = try Data(contentsOf: archiveURL)
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
guard reader.length == archive.count, key.isValidSignature(signature, for: archive) else {
    fatalError("Update archive signature or byte length does not match")
}
var tampered = archive
if !tampered.isEmpty { tampered[0] ^= 1 }
guard !key.isValidSignature(signature, for: tampered) else { fatalError("Tampered archive was accepted") }
print("Update archive signature verified; tampered archive rejected.")
