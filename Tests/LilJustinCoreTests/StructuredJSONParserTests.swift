import XCTest
@testable import LilJustinCore

/// Regression coverage for the structured-JSON parser that lifts
/// Orion's response payload out of raw CLI output. The parser
/// failure on 2026-04-30 dumped raw JSON (`"messages"`,
/// `"suggested_experts"`, `"suggest_expert_prompt"`) directly to
/// the user's chat bubble — once that path leaks, the user sees
/// the wire format instead of the prose. Locking it down here.
final class StructuredJSONParserTests: XCTestCase {

    // MARK: - Happy paths

    func test_decodesMinimalMessagesPayload() {
        let raw = """
        {
          "messages": [
            { "speaker": "Orion", "kind": "orion", "markdown": "Welcome flows are 47 things you didn't need to know yet." }
          ],
          "suggested_experts": [],
          "suggest_expert_prompt": false
        }
        """
        let object = StructuredJSONParser.decodeJSONObject(from: raw)
        XCTAssertNotNil(object)
        XCTAssertNotNil(object?["messages"] as? [[String: Any]])
        XCTAssertEqual(object?["suggest_expert_prompt"] as? Bool, false)
    }

    func test_decodesAnswerMarkdownLegacyShape() {
        // The parser used to be tolerant of an `answer_markdown`
        // top-level key. Old prompts and forks may still emit it.
        let raw = #"""
        { "answer_markdown": "MPP pre-fetches every image regardless of opens.", "suggested_experts": [] }
        """#
        let object = StructuredJSONParser.decodeJSONObject(from: raw)
        XCTAssertNotNil(object)
        XCTAssertEqual(object?["answer_markdown"] as? String, "MPP pre-fetches every image regardless of opens.")
    }

    func test_stripsCodeFenceWrapping() {
        // Some models defy the "no code fences" instruction and
        // wrap the payload in ```json ... ```. Parser strips it.
        let raw = """
        ```json
        {
          "messages": [
            { "speaker": "Orion", "kind": "orion", "markdown": "Open rate is just Apple's image proxy waving hello." }
          ],
          "suggest_expert_prompt": false
        }
        ```
        """
        let object = StructuredJSONParser.decodeJSONObject(from: raw)
        XCTAssertNotNil(object)
    }

    func test_extractsJSONFromSurroundingProse() {
        // Some backends prepend tool-call summaries before the JSON.
        let raw = """
        Here's what I'd do:
        {
          "messages": [
            { "speaker": "Orion", "kind": "orion", "markdown": "Fix the unsubscribe page first." }
          ],
          "suggest_expert_prompt": false
        }
        """
        let object = StructuredJSONParser.decodeJSONObject(from: raw)
        XCTAssertNotNil(object)
    }

    // MARK: - Sanitisation

    func test_sanitisesRawNewlinesInsideStrings() {
        // The system prompt tells the model to emit `\\n` inside the
        // markdown string. In practice it forgets — which used to
        // make strict JSON parsing fail and dump raw output. The
        // sanitiser fixes raw newlines inside string literals.
        let raw = "{\"messages\":[{\"speaker\":\"Orion\",\"kind\":\"orion\",\"markdown\":\"line one\nline two\nline three\"}]}"
        let object = StructuredJSONParser.decodeJSONObject(from: raw)
        XCTAssertNotNil(object)
        let messages = object?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.first?["markdown"] as? String, "line one\nline two\nline three")
    }

    func test_sanitiserPreservesAlreadyEscapedNewlines() {
        // If the model gets it right, sanitiser should be a no-op
        // for that part — escapes pass through unchanged.
        let input = #"{"key": "already\nescaped"}"#
        XCTAssertEqual(StructuredJSONParser.sanitiseJSONStrings(input), input)
    }

    func test_sanitiserDoesNotEscapeNewlinesOutsideStrings() {
        // Outer whitespace + structural newlines stay raw — that's
        // legal JSON. Only string-internal control chars get escaped.
        let input = "{\n  \"key\": \"value\"\n}"
        XCTAssertEqual(StructuredJSONParser.sanitiseJSONStrings(input), input)
    }

    // MARK: - Candidate extraction

    func test_extractCandidateBalancesBracesInsideStrings() {
        // The candidate scanner must not be fooled by `{` or `}`
        // inside string values — a markdown body that mentions JSON
        // braces shouldn't break the depth tracking.
        let raw = #"""
        {"messages": [{"speaker":"Orion","kind":"orion","markdown":"Use {{ liquid }} syntax in Braze."}]}
        """#
        XCTAssertNotNil(StructuredJSONParser.extractCandidate(from: raw))
        XCTAssertNotNil(StructuredJSONParser.decodeJSONObject(from: raw))
    }

    func test_extractCandidateSkipsProseBraceBlocksWithoutSchema() {
        // A `{...}` block in prose that doesn't contain `messages`
        // or `answer_markdown` should be skipped — extractor scans
        // forward to find the real schema-bearing block.
        let raw = """
        Quick aside: {"comment": "ignore me"}.

        {
          "messages": [{ "speaker": "Orion", "kind": "orion", "markdown": "Real answer." }],
          "suggest_expert_prompt": false
        }
        """
        let object = StructuredJSONParser.decodeJSONObject(from: raw)
        XCTAssertNotNil(object)
    }

    // MARK: - Degraded paths — Sir's 2026-04-30 regression

    func test_fallbackExtractsMarkdownWhenJSONIsBroken() {
        // 2026-04-30: Orion's bubble rendered raw JSON instead of
        // the prose. Hypothesis: the markdown body contained
        // characters that broke strict JSON parsing AND survived
        // sanitisation (e.g. an unescaped quote). The fallback
        // should regex out the markdown content so the user at
        // least sees readable prose, not the JSON envelope.
        //
        // Realistic reproduction: an unescaped quote inside the
        // markdown breaks string-state tracking everywhere
        // downstream — strict parse + sanitiser both fail.
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
        // Strict parse fails (unescaped inner quotes break it).
        XCTAssertNil(StructuredJSONParser.decodeJSONObject(from: broken))
        // Fallback should extract SOMETHING readable from the
        // markdown field rather than nothing.
        let extracted = StructuredJSONParser.extractMessageMarkdownFallback(from: broken)
        XCTAssertNotNil(extracted)
        // The user sees prose, not the JSON envelope.
        XCTAssertFalse(extracted?.contains("\"messages\"") ?? true)
        XCTAssertFalse(extracted?.contains("\"suggested_experts\"") ?? true)
    }

    func test_fallbackUnescapesStandardJSONEscapes() {
        let raw = #"""
        {"messages":[{"markdown":"Line one.\nLine two with \"quoted\" word.\nEnd."}]}
        """#
        let extracted = StructuredJSONParser.extractMessageMarkdownFallback(from: raw)
        // Newlines and quotes should be unescaped to their literal
        // characters in the user-facing prose.
        XCTAssertEqual(extracted, "Line one.\nLine two with \"quoted\" word.\nEnd.")
    }

    func test_fallbackReturnsNilWhenNoMarkdownFieldPresent() {
        let raw = "Just a plain string with no JSON at all."
        XCTAssertNil(StructuredJSONParser.extractMessageMarkdownFallback(from: raw))
    }

    // MARK: - Failure modes

    func test_returnsNilForEmptyInput() {
        XCTAssertNil(StructuredJSONParser.decodeJSONObject(from: ""))
        XCTAssertNil(StructuredJSONParser.decodeJSONObject(from: "   \n\n  "))
    }

    func test_returnsNilForCompletelyMalformedInput() {
        XCTAssertNil(StructuredJSONParser.decodeJSONObject(from: "this is not JSON at all"))
        XCTAssertNil(StructuredJSONParser.decodeJSONObject(from: "{ broken"))
    }

    func test_returnsNilForJSONWithoutKnownSchemaKeys() {
        // A valid JSON object that lacks `messages` or
        // `answer_markdown` is not Orion's structured payload — the
        // parser must reject it rather than return an empty hit.
        let raw = #"{"unrelated":"nope","answer":"ignored"}"#
        XCTAssertNil(StructuredJSONParser.decodeJSONObject(from: raw))
    }
}
