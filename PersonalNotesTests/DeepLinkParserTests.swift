import XCTest
@testable import PersonalNotes

/// Deep links are the "send a note to another user" entry point, and the iOS app has to accept the
/// same shapes the Android app produces.
final class DeepLinkParserTests: XCTestCase {

    func testEmbeddedTokenLink() {
        let incoming = DeepLinkParser.parse(URL(string: "personalnotes://note/d/ABC-_123")!)
        XCTAssertEqual(incoming, .embeddedNote(token: "ABC-_123"))
    }

    func testNumericStyleLinkIsNotAValidUUID() {
        // Android can address a note by its local database id; iOS notes are keyed by UUID, so
        // such a link is treated as unusable rather than silently opened.
        XCTAssertNil(DeepLinkParser.parse(URL(string: "personalnotes://note/42")!))
    }

    func testLocalUUIDLink() {
        let id = UUID()
        let incoming = DeepLinkParser.parse(URL(string: "personalnotes://note/\(id.uuidString)")!)
        XCTAssertEqual(incoming, .localNote(id))
    }

    func testHttpsLinkCarriesEmbeddedNote() {
        let incoming = DeepLinkParser.parse(URL(string: "https://personalnotes.app/note/d/PAYLOAD")!)
        XCTAssertEqual(incoming, .embeddedNote(token: "PAYLOAD"))
    }

    func testImportQueryParameter() {
        let incoming = DeepLinkParser.parse(URL(string: "personalnotes://import?d=QUERYTOKEN")!)
        XCTAssertEqual(incoming, .embeddedNote(token: "QUERYTOKEN"))
    }

    func testNoteDocumentIsRecognised() {
        let url = URL(fileURLWithPath: "/tmp/groceries.pnote")
        XCTAssertEqual(DeepLinkParser.parse(url), .noteDocument(url))
        XCTAssertTrue(DeepLinkParser.isNoteDocument(url))
    }

    func testUnrelatedLinkIsIgnored() {
        XCTAssertNil(DeepLinkParser.parse(URL(string: "personalnotes://")!))
        XCTAssertNil(DeepLinkParser.parse(URL(string: "https://example.com/hello")!))
    }

    func testLongOpaqueSegmentIsTreatedAsPayload() {
        let token = String(repeating: "A", count: 64)
        let incoming = DeepLinkParser.parse(URL(string: "personalnotes://x/\(token)")!)
        XCTAssertEqual(incoming, .embeddedNote(token: token))
    }
}
