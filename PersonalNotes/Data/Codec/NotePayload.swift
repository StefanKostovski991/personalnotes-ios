import Foundation
import zlib

/// gzip in pure C because iOS has no libcompression gzip wrapper that is available on every
/// supported OS version. Note links from the Android app are gzip-compressed, so inflating is
/// required for cross-platform compatibility.
enum Gzip {
    private static let windowBits: Int32 = 15 + 16  // 16 selects the gzip wrapper

    static func decompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var stream = z_stream()
        var status = inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunkSize = 16 * 1024
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        var mutableInput = [UInt8](data)

        return mutableInput.withUnsafeMutableBufferPointer { inputBuffer -> Data? in
            guard let base = inputBuffer.baseAddress else { return nil }
            stream.next_in = base
            stream.avail_in = uInt(inputBuffer.count)

            repeat {
                let written: Int = chunk.withUnsafeMutableBufferPointer { outBuffer -> Int in
                    stream.next_out = outBuffer.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    return chunkSize - Int(stream.avail_out)
                }
                if written < 0 { return nil }
                output.append(contentsOf: chunk[0..<written])
                if status == Z_STREAM_END { break }
                if status != Z_OK { return nil }
                if written == 0 && stream.avail_in == 0 { break }
            } while true

            return output
        }
    }
}

/// The wire format used when a note travels to another user of the app.
///
/// Field names match the Android implementation exactly, so a `.pnote` file or an embedded link
/// written by either platform opens on the other. `schema` identifies the payload kind and
/// `version` allows a future release to migrate old files.
struct NotePayload: Codable, Equatable, Sendable {
    static let schema = "com.kostovskiapps.personalnotes/note"
    static let version = 1
    static let mimeType = "application/vnd.personalnotes.note+json"

    var schemaValue: String
    var versionValue: Int
    var id: String
    var title: String
    var description: String
    var createdAt: Int64
    var updatedAt: Int64
    var colorId: String?
    var kindId: String?
    var location: NoteLocationPayload?
    var attachments: [NoteAttachmentPayload]

    enum CodingKeys: String, CodingKey {
        case schemaValue = "schema"
        case versionValue = "version"
        case id
        case title
        case description
        case createdAt
        case updatedAt
        case colorId
        case kindId
        case location
        case attachments
    }

    init(
        id: String,
        title: String,
        description: String,
        createdAt: Int64,
        updatedAt: Int64,
        colorId: String?,
        kindId: String?,
        location: NoteLocationPayload?,
        attachments: [NoteAttachmentPayload] = [],
        schemaValue: String = NotePayload.schema,
        versionValue: Int = NotePayload.version
    ) {
        self.schemaValue = schemaValue
        self.versionValue = versionValue
        self.id = id
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.colorId = colorId
        self.kindId = kindId
        self.location = location
        self.attachments = attachments
    }
}

struct NoteLocationPayload: Codable, Equatable, Sendable {
    var label: String
    var latitude: Double?
    var longitude: Double?
}

struct NoteAttachmentPayload: Codable, Equatable, Sendable {
    var name: String
    var mimeType: String
    /// base64url of the raw bytes, so a whole voice note can travel inside one file.
    var data: String?
}
