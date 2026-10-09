import XCTest
@testable import StashBar

final class MetadataParserTests: XCTestCase {

    func testParseHeadExtractsTitleAndOGMetadata() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Awesome Framework &amp; Tools</title>
            <meta property="og:title" content="Awesome Framework by StashBar" />
            <meta property="og:description" content="A blazing fast tool for developers &amp; designers." />
            <meta property="og:image" content="/assets/cover.png" />
            <link rel="icon" href="/favicon.ico" />
        </head>
        <body>
            <p>Body content</p>
        </body>
        </html>
        """

        let baseURL = URL(string: "https://example.com/blog/article")!
        var result = MetadataResult()
        MetadataParser.parseHead(html: html, baseURL: baseURL, result: &result)

        XCTAssertEqual(result.title, "Awesome Framework & Tools")
        XCTAssertEqual(result.itemDescription, "A blazing fast tool for developers & designers.")
        XCTAssertEqual(result.ogImageUrl, "https://example.com/assets/cover.png")
        XCTAssertEqual(result.faviconUrl, "https://example.com/favicon.ico")
    }

    func testHTMLDecodesEntities() {
        let raw = "StashBar &amp; Friends &#8212; It&#39;s &quot;fast&quot;"
        let decoded = MetadataParser.decodeHTMLEntities(raw)
        XCTAssertEqual(decoded, "StashBar & Friends — It's \"fast\"")
    }

    func testRelativeUrlResolution() {
        let base = URL(string: "https://sub.example.com/path/page.html")!
        
        let rel1 = MetadataParser.resolveRelativeUrl("/static/favicon.png", relativeTo: base)
        XCTAssertEqual(rel1, "https://sub.example.com/static/favicon.png")

        let rel2 = MetadataParser.resolveRelativeUrl("//cdn.example.com/img.jpg", relativeTo: base)
        XCTAssertEqual(rel2, "https://cdn.example.com/img.jpg")

        let abs = MetadataParser.resolveRelativeUrl("https://other.com/icon.ico", relativeTo: base)
        XCTAssertEqual(abs, "https://other.com/icon.ico")
    }
}
