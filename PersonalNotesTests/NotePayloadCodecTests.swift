import XCTest
@testable import PersonalNotes

/// The wire format is the contract between the iOS app, the Android app and other users, so it is
/// pinned here: field names, containers, and the cross-platform edge cases.
final class NotePayloadCodecTests: XCTestCase {

    private let sample = NotePayload(
        id: "local-42",
        title: "Groceries",
        description: "Milk, eggs and a really long line of text that must survive the round trip incl. unicode: äöü, 日本語, 🍋",
        createdAt: 1_700_000_000_000,
        updatedAt: 1_700_000_500_000,
        colorId: "amber",
        kindId: "mixed",
        location: NoteLocationPayload(label: "Vienna, Austria", latitude: 48.2082, longitude: 16.3738),
        attachments: [
            NoteAttachmentPayload(
                name: "voice-1700000000000.m4a",
                mimeType: "audio/mp4",
                data: NotePayloadCodec.base64UrlEncode(Data([1, 2, 3, 4, 5]))
            )
        ]
    )

    func testFileFormatRoundTripsEveryField() throws {
        let data = try NotePayloadCodec.encodeToFileBytes(sample)
        XCTAssertEqual(try NotePayloadCodec.parse(data), sample)
    }

    func testFileStartsWithMagicHeader() throws {
        let text = String(decoding: try NotePayloadCodec.encodeToFileBytes(sample), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix(NotePayloadCodec.fileMagic))
        XCTAssertTrue(text.contains("\"schema\""))
        XCTAssertTrue(text.contains(NotePayload.schema))
    }

    /// If the encoder writes a key the payload does not declare, decoding silently drops it. This
    /// pins the exact keys shared with Android.
    func testJsonKeysMatchTheDocumentedWireFormat() throws {
        let text = String(decoding: try NotePayloadCodec.encodeToFileBytes(sample), as: UTF8.self)
        for key in [
            "\"schema\"", "\"version\"", "\"id\"", "\"title\"", "\"description\"",
            "\"createdAt\"", "\"updatedAt\"", "\"colorId\"", "\"kindId\"",
            "\"location\"", "\"latitude\"", "\"attachments\"", "\"mimeType\"", "\"data\"",
        ] {
            XCTAssertTrue(text.contains(key), "expected the payload to contain \(key)")
        }
    }

    /// A payload written by the Android app must decode without losing colour or kind.
    func testPayloadFromAndroidDecodesColourAndKind() throws {
        let external = """
        PERSONALNOTES-NOTE
        {
          "schema": "com.kostovskiapps.personalnotes/note",
          "version": 1,
          "id": "other-device-1",
          "title": "Amber spoken note",
          "description": "dictated elsewhere",
          "createdAt": 1750000000000,
          "updatedAt": 1750000500000,
          "colorId": "amber",
          "kindId": "spoken",
          "location": { "label": "Graz", "latitude": 47.07, "longitude": 15.43 },
          "attachments": []
        }
        """
        let payload = try NotePayloadCodec.parse(Data(external.utf8))
        XCTAssertEqual(payload.colorId, "amber")
        XCTAssertEqual(payload.kindId, "spoken")
        XCTAssertEqual(payload.location?.label, "Graz")
    }

    func testLinkTokenRoundTrips() throws {
        let token = try NotePayloadCodec.encodeToLinkToken(sample)
        XCTAssertEqual(try NotePayloadCodec.decodeLinkToken(token), sample)
        XCTAssertTrue(token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    /// A link token produced by a genuine gzip writer outside Swift - i.e. exactly what the
    /// Android app puts inside `personalnotes://note/d/<token>`. The iOS reader must inflate it.
    func testGzippedLinkTokenFromAndroidDecodes() throws {
        let token = "H4sIAAAAAAAC_12OMW7DMAxFr2Jwdt3ESRrDm8deoEvRgZGIRrBMChKTJcjdSzlBhmrQ8B4_P29Q3JkWhBGcLN0sReVa5oAplS5RLsIYWZTKe_2hhavBIAzjtoXgLYfsswT_tu_NatBIBqflRLkpSWZiw56KyyHpGgQfnKKSb4Sb6ZG2GZepwklt9fGweb0WLsn_M4encRIlf65X1ELbMgf2K3h1R3H4KL5BxBNFk1-BmLFKU3rxdvJ-6PrN0Nd5_n2y7Ue3O-6Gewuoiu68EGuB8fvn_gdY4VflOAEAAA"
        let payload = try NotePayloadCodec.decodeLinkToken(token)
        XCTAssertEqual(payload.colorId, "amber")
        XCTAssertEqual(payload.kindId, "spoken")
        XCTAssertEqual(payload.title, "Amber spoken")
        XCTAssertEqual(payload.location?.label, "Vienna")
    }

    func testFingerprintIsStableAndIgnoresTransportFields() {
        let reimported = NotePayload(
            id: "local-99",
            title: sample.title,
            description: sample.description,
            createdAt: sample.createdAt,
            updatedAt: sample.updatedAt,
            colorId: sample.colorId,
            kindId: sample.kindId,
            location: sample.location,
            attachments: []
        )
        XCTAssertEqual(NotePayloadCodec.fingerprint(sample), NotePayloadCodec.fingerprint(reimported))
    }

    func testFingerprintDistinguishesContent() {
        var changed = sample
        changed.title = "Groceries 2"
        XCTAssertNotEqual(NotePayloadCodec.fingerprint(sample), NotePayloadCodec.fingerprint(changed))

        var recoloured = sample
        recoloured.colorId = "lemon"
        XCTAssertNotEqual(NotePayloadCodec.fingerprint(sample), NotePayloadCodec.fingerprint(recoloured))
    }

    func testBase64UrlHandlesEveryLength() throws {
        for size in 0...64 {
            let original = Data((0..<size).map { UInt8(($0 * 7 + 3) & 0xFF) })
            let encoded = NotePayloadCodec.base64UrlEncode(original)
            XCTAssertTrue(encoded.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
            XCTAssertEqual(try NotePayloadCodec.base64UrlDecode(encoded), original)
        }
    }

    func testRejectsNonNotePayload() {
        XCTAssertThrowsError(try NotePayloadCodec.parse(Data("{\"unrelated\":true}".utf8)))
    }
}
