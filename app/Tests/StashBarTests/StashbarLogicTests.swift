import XCTest
@testable import StashBar

final class StashbarLogicTests: XCTestCase {

    func testRemovedParametersListsTrackersOnly() {
        let removed = URLSanitizer.removedParameters(from: "https://youtube.com/watch?v=q8Tx0&utm_source=x&si=abc")
        XCTAssertEqual(removed, ["utm_source", "si"])
    }

    func testCustomParameterListIsRespected() {
        let clean = URLSanitizer.sanitize("https://example.com/a?keep=1&drop=2", stripping: ["drop"])
        XCTAssertEqual(clean, "https://example.com/a?keep=1")
    }

    func testNoStrippingKeepsQuery() {
        let clean = URLSanitizer.sanitize("https://example.com/a?utm_source=x", stripping: [])
        XCTAssertEqual(clean, "https://example.com/a?utm_source=x")
    }

    func testRejectsMultilineText() {
        XCTAssertNil(URLSanitizer.sanitize("github.com\nsomething else"))
    }

    func testParsesNetscapeBookmarks() {
        let html = """
        <DL><p>
        <DT><A HREF="https://github.com/apple/swift" ADD_DATE="1">Swift &amp; friends</A>
        <DT><A HREF="javascript:void(0)">Bookmarklet</A>
        <DT><A HREF='https://figma.com'><b>Figma</b></A>
        </DL>
        """
        let entries = BookmarkIO.parse(html)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].url, "https://github.com/apple/swift")
        XCTAssertEqual(entries[0].title, "Swift & friends")
        XCTAssertEqual(entries[1].title, "Figma")
    }

    func testParsesStashbarJSONExport() {
        let json = #"[{"url":"https://x.com/a","title":"A thread"}]"#
        let entries = BookmarkIO.parse(json)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].title, "A thread")
    }

    func testISODateParsesPostgresMicroseconds() {
        let d = ISODate.parse("2026-10-09T14:04:00.123456+00:00")
        XCTAssertNotNil(d)
        XCTAssertEqual(d!.timeIntervalSince1970, 1791554640.123, accuracy: 0.01)
        XCTAssertNotNil(ISODate.parse("2026-10-09T14:04:00Z"))
        XCTAssertNil(ISODate.parse(nil))
    }

    func testVersionCompare() {
        XCTAssertEqual(UpdateChecker.compare("2.0.10", "2.0.9"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compare("2.0", "2.0.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compare("1.9.9", "2.0.0"), .orderedAscending)
    }

    func testRelativeTimeShortLabels() {
        let now = Date()
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-30), now: now), "now")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-38 * 60), now: now), "38m")
    }

    func testPKCEChallengeIsBase64URL() {
        let verifier = AuthService.randomVerifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        let challenge = AuthService.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        // RFC 7636 appendix B test vector.
        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testSupabaseQueryEncodingEscapesPlusAndColon() {
        XCTAssertEqual(SupabaseClient.encode("gt.2026-10-09T14:04:00+00:00"), "gt.2026-10-09T14%3A04%3A00%2B00%3A00")
    }
}
