import CryptoKit
import Foundation

/// Converts a ``NotePayload`` to and from the shapes it travels in.
///
/// Three containers exist and all are accepted on the way in, so notes move freely between the
/// iOS and Android apps:
///
/// 1. **`.pnote` file** - the magic header plus pretty-printed JSON. Written by both apps.
/// 2. **gzipped base64url token** - what Android embeds in a link
///    (`personalnotes://note/d/<token>`).
/// 3. **plain base64url JSON** - a compact link token produced here when a platform's gzip is
///    unavailable to the sender. Receivers detect which form they were given.
///
/// No UIKit is involved, so the whole format is covered by unit tests.
enum NotePayloadCodec {
    /// Prefix that makes a `.pnote` file recognisable on sight.
    static let fileMagic = "PERSONALNOTES-NOTE"

    /// Link path segment: `personalnotes://note/d/<token>`.
    static let linkSegment = "d"

    private static let maxDecompressedBytes = 4 * 1024 * 1024

    // MARK: - Encoding

    static func encodeToFileBytes(_ payload: NotePayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(payload)
        var data = Data((fileMagic + "\n").utf8)
        data.append(json)
        data.append(0x0A)
        return data
    }

    static func encodeToCompactBytes(_ payload: NotePayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    /// Token embedded in a deep link. Base64url of the compact JSON: gzip is supported on input
    /// (for links written by Android) but not required on output.
    static func encodeToLinkToken(_ payload: NotePayload) throws -> String {
        base64UrlEncode(try encodeToCompactBytes(payload))
    }

    // MARK: - Decoding

    /// Accepts a `.pnote` file body or bare JSON.
    static func parse(_ data: Data) throws -> NotePayload {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = bytes.dropFirst(3)
        }
        let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text.hasPrefix(fileMagic)
            ? String(text.dropFirst(fileMagic.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            : text
        return try decodeJSON(Data(body.utf8))
    }

    /// Decodes a link token in either supported container (gzip+base64url, or base64url JSON).
    static func decodeLinkToken(_ token: String) throws -> NotePayload {
        let raw = try base64UrlDecode(token)
        let json: Data
        if raw.prefix(2) == Data([0x1F, 0x8B]) {
            guard let inflated = Gzip.decompress(raw) else {
                throw NoteCodecError.malformed("The compressed note could not be read")
            }
            guard inflated.count <= maxDecompressedBytes else {
                throw NoteCodecError.malformed("This note is too large")
            }
            json = inflated
        } else {
            json = raw
        }
        return try decodeJSON(json)
    }

    private static func decodeJSON(_ data: Data) throws -> NotePayload {
        if let payload = try? JSONDecoder().decode(NotePayload.self, from: data) {
            return payload
        }
        // Android writes camelCase keys and its own omission rules; report a clear error rather
        // than leaking a DecodingError to the UI.
        do {
            return try JSONDecoder().decode(NotePayload.self, from: data)
        } catch {
            throw NoteCodecError.malformed("This file is not a Personal Notes note")
        }
    }

    // MARK: - Identity

    /// Short, stable hash of everything that makes a note *this* note.
    ///
    /// Only content is hashed: transfer details (the sender's local id, the attachment list) are
    /// excluded, so the same note arriving twice - once as a link, once as a file - yields one
    /// fingerprint and therefore one stored note. Identical to Android's algorithm.
    static func fingerprint(_ payload: NotePayload) -> String {
        var material = ""
        material += payload.title.trimmingCharacters(in: .whitespaces) + "\u{0}"
        material += payload.description.trimmingCharacters(in: .whitespaces) + "\u{0}"
        material += String(payload.createdAt) + "\u{0}"
        material += (payload.colorId ?? "") + "\u{0}"
        material += (payload.kindId ?? "") + "\u{0}"
        material += payload.location?.label ?? ""
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - base64url (RFC 4648 section 5, unpadded)

    static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64UrlDecode(_ token: String) throws -> Data {
        var text = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = text.count % 4
        if remainder > 0 {
            text += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: text) else {
            throw NoteCodecError.malformed("This note link is not valid")
        }
        return data
    }
}

enum NoteCodecError: LocalizedError {
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .malformed(let message): return message
        }
    }
}
