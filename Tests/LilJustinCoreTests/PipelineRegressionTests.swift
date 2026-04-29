import XCTest
@testable import LilJustinCore

/// Pipeline-level regression tests — the "if a real CLI output looks
/// like this, the user-visible behaviour is correct" layer that sits
/// above the per-component unit tests in the same target.
///
/// Why this file exists: the unit tests cover individual converters
/// (MarkdownToSlack, MarkdownToHTML, StructuredJSONParser). Each is
/// correct in isolation, but the bug classes that have actually
/// shipped to users came from converter outputs combining badly when
/// pieces met for the first time. Sir's 2026-04-30 JSON-leak was the
/// latest example — the parser worked in unit tests, but live CLI
/// output the parser couldn't decode bypassed the renderer entirely.
///
/// The assertions here are deliberately structural rather than
/// full-string equality — bullets present, no JSON envelope leakage,
/// expected sections in expected order — so the tests stay stable
/// across reasonable converter tweaks while still catching the bug
/// classes that warrant a release blocker.
///
/// Future expansion: when there's an Xcode-capable test path
/// available, these graduate to snapshot-style golden-file tests via
/// the swift-snapshot-testing dependency that's wired up in
/// Package.swift. For now traditional assertions keep the suite
/// green from first push without a bootstrap roundtrip.
final class PipelineRegressionTests: XCTestCase {

    // MARK: - JSON-leak regression (Sir's 2026-04-30 screenshot)

    func test_brokenJSONFallsBackToReadableProse() {
        // The actual failure shape that produced the leak: unescaped
        // double-quotes inside the markdown body break strict parsing
        // AND survive the newline sanitiser. Without the fallback
        // path, the entire JSON envelope would render to the user.
        let broken = #"""
        {
          "messages": [
            {
              "speaker": "Orion",
              "kind": "orion",
              "markdown": "MPP pre-fetches every image. Apple calls it "privacy" but the metric impact is real.\n\n**Sources**\n\n- [MPP four years in](https://get.yourorbit.team/guides/apple-mpp-four-years)"
            }
          ],
          "suggested_experts": [],
          "suggest_expert_prompt": false
        }
        """#

        // Strict parse must fail — that's the precondition for this
        // regression test. If a future parser change makes strict
        // parsing succeed on this input, the broken-input set needs
        // a more pathological example to keep the fallback exercised.
        XCTAssertNil(StructuredJSONParser.decodeJSONObject(from: broken),
                     "Strict parse should fail on unescaped quotes inside markdown — the precondition for the fallback path.")

        // Fallback must produce something readable.
        let fallback = StructuredJSONParser.extractMessageMarkdownFallback(from: broken)
        XCTAssertNotNil(fallback, "Fallback must produce SOMETHING — not nil — when JSON is broken.")
        guard let extracted = fallback else { return }

        // Must NOT leak the JSON envelope keys to the user.
        XCTAssertFalse(extracted.contains("\"messages\""),
                       "Fallback output leaked the `messages` JSON key to the user.")
        XCTAssertFalse(extracted.contains("\"suggested_experts\""),
                       "Fallback output leaked the `suggested_experts` JSON key to the user.")
        XCTAssertFalse(extracted.contains("\"suggest_expert_prompt\""),
                       "Fallback output leaked the `suggest_expert_prompt` JSON key to the user.")
        XCTAssertFalse(extracted.contains("\"kind\""),
                       "Fallback output leaked the `kind` JSON key to the user.")
        XCTAssertFalse(extracted.contains("\"speaker\""),
                       "Fallback output leaked the `speaker` JSON key to the user.")

        // Must contain the actual prose content (or at least the
        // first portion, before any unescaped quote that truncates
        // the regex capture).
        XCTAssertTrue(extracted.contains("MPP pre-fetches"),
                      "Fallback didn't extract the start of the markdown body.")
    }

    func test_brokenJSONFallback_unescapesEscapesToReadableForm() {
        // When the markdown body is well-escaped but the surrounding
        // JSON envelope is otherwise broken, the fallback should
        // unescape the standard JSON escapes so the user sees real
        // newlines and real quotes, not the \n / \" wire format.
        let raw = #"""
        {"messages":[{"markdown":"Line one.\nLine two with \"quoted\" word.\nLine three."}]}
        """#
        let fallback = StructuredJSONParser.extractMessageMarkdownFallback(from: raw)
        XCTAssertEqual(fallback, "Line one.\nLine two with \"quoted\" word.\nLine three.",
                       "Fallback should unescape standard JSON escapes (\\n and \\\") to literal newline and quote.")
    }

    // MARK: - MarkdownToSlack pipeline behaviour

    func test_slackConverter_preservesAllSectionsOfCompoundDocument() {
        // Sir's compound bug class: a converter regression that
        // breaks one element type can pass per-element unit tests
        // but ship a real document that's missing chunks. This test
        // runs the converter against a realistic Orion answer and
        // asserts every section type is represented in the output.
        let input = """
        # Heading

        **Bold lead** with *italic* mixed in.

        - List item one
        - List item two with [link](https://example.com)

        > Blockquote with a point.

        | Col A | Col B |
        |---|---|
        | r1 | r2 |

        Inline `code reference` and a paragraph.

        ```
        block of code
        ```

        **Sources**

        - [Source one](https://get.yourorbit.team/guides/source-one)
        """
        let slack = MarkdownToSlack.convert(input)

        // Heading should leave a presence (Slack doesn't render
        // markdown headings, but the converter typically converts
        // them to bold or leaves the text).
        XCTAssertTrue(slack.contains("Heading"), "Heading text dropped from Slack output.")

        // Bold + italic emphasis should survive.
        XCTAssertTrue(slack.contains("Bold lead"), "Bold lead text dropped.")

        // List items should be present.
        XCTAssertTrue(slack.contains("List item one"), "First list item dropped.")
        XCTAssertTrue(slack.contains("List item two"), "Second list item dropped.")

        // Inline code should be present.
        XCTAssertTrue(slack.contains("code reference"), "Inline code dropped.")

        // Blockquote text should survive.
        XCTAssertTrue(slack.contains("Blockquote with a point"), "Blockquote text dropped.")

        // Sources block must survive — the most important part of
        // any Orion answer; a converter regression that drops
        // sources is a release blocker.
        XCTAssertTrue(slack.contains("Sources"), "Sources block label dropped.")
        XCTAssertTrue(slack.contains("Source one"), "Source link text dropped.")
        XCTAssertTrue(slack.contains("get.yourorbit.team"), "Source URL dropped.")
    }

    func test_slackConverter_handlesEmphasisVariantsWithoutDropping() {
        // The "stars don't go bold" bug class. Different emphasis
        // syntaxes should all preserve their text content.
        let input = """
        **Asterisk bold** and *asterisk italic*.
        __Underscore bold__ and _underscore italic_.
        ***Both at once*** combined.
        """
        let slack = MarkdownToSlack.convert(input)

        XCTAssertTrue(slack.contains("Asterisk bold"), "Asterisk bold text dropped.")
        XCTAssertTrue(slack.contains("asterisk italic"), "Asterisk italic text dropped.")
        XCTAssertTrue(slack.contains("Underscore bold"), "Underscore bold text dropped.")
        XCTAssertTrue(slack.contains("underscore italic"), "Underscore italic text dropped.")
        XCTAssertTrue(slack.contains("Both at once"), "Triple-asterisk emphasis text dropped.")
    }

    // MARK: - MarkdownToHTML pipeline behaviour

    func test_htmlConverter_paragraphsDoNotCollapse() {
        // The bug class that caused Slack-pasted answers to render
        // as one wall of text in v0.1.49–v0.1.54. The converter
        // must produce HTML where consecutive paragraphs render
        // separated, not merged.
        let input = """
        # Heading

        First paragraph.

        Second paragraph.

        ## Subheading

        Third paragraph.
        """
        let html = MarkdownToHTML.convert(input)

        // Each paragraph should produce its own <p> tag.
        let paragraphCount = html.components(separatedBy: "<p>").count - 1
        XCTAssertGreaterThanOrEqual(paragraphCount, 3,
                                    "HTML output collapsed paragraphs — saw \(paragraphCount) <p> tags, expected at least 3.")
    }

    func test_htmlConverter_preservesLinksAsAnchorTags() {
        let input = "Check the [Apple MPP guide](https://get.yourorbit.team/guides/apple-mpp-four-years)."
        let html = MarkdownToHTML.convert(input)

        XCTAssertTrue(html.contains("<a"), "Link not rendered as an anchor tag.")
        XCTAssertTrue(html.contains("get.yourorbit.team"), "Link URL stripped from HTML output.")
        XCTAssertTrue(html.contains("Apple MPP guide"), "Link text stripped from HTML output.")
    }
}
