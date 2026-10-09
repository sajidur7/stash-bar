import XCTest
@testable import StashBar

final class URLSanitizerTests: XCTestCase {

    func testStripsUTMParameters() {
        let dirtyUrl = "https://example.com/article?title=test&utm_source=twitter&utm_medium=social&utm_campaign=launch"
        let clean = URLSanitizer.sanitize(dirtyUrl)
        XCTAssertEqual(clean, "https://example.com/article?title=test")
    }

    func testStripsFacebookAndAdClickIds() {
        let dirtyUrl = "https://shop.example.com/product/42?fbclid=IwAR12345&gclid=Cj0KCQiA&ref=homepage"
        let clean = URLSanitizer.sanitize(dirtyUrl)
        XCTAssertEqual(clean, "https://shop.example.com/product/42")
    }

    func testStripsSpotifyAndYouTubeShareTracking() {
        let spotifyUrl = "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=a1b2c3d4e5f6"
        let cleanSpotify = URLSanitizer.sanitize(spotifyUrl)
        XCTAssertEqual(cleanSpotify, "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT")

        let ytUrl = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=xyz123&feature=share"
        let cleanYt = URLSanitizer.sanitize(ytUrl)
        XCTAssertEqual(cleanYt, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testPreservesLegitimateQueryParams() {
        let validUrl = "https://news.ycombinator.com/item?id=38123456"
        let clean = URLSanitizer.sanitize(validUrl)
        XCTAssertEqual(clean, "https://news.ycombinator.com/item?id=38123456")
    }

    func testHandlesMissingScheme() {
        let url = "github.com/apple/swift"
        let clean = URLSanitizer.sanitize(url)
        XCTAssertEqual(clean, "https://github.com/apple/swift")
    }

    func testExtractsCleanHost() {
        let host1 = URLSanitizer.cleanHost(from: "https://www.github.com/apple/swift")
        XCTAssertEqual(host1, "github.com")

        let host2 = URLSanitizer.cleanHost(from: "https://news.ycombinator.com")
        XCTAssertEqual(host2, "news.ycombinator.com")
    }

    func testInvalidUrlReturnsNil() {
        XCTAssertNil(URLSanitizer.sanitize(""))
        XCTAssertNil(URLSanitizer.sanitize("just a random sentence without dots"))
    }
}
