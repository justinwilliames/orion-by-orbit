import XCTest
import UniformTypeIdentifiers
@testable import LilJustinCore

/// Regression test for v0.5.3: the file picker silently filtered
/// `.image` out of its allowed content types, so users couldn't
/// attach screenshots / photos via the picker at all — drag &
/// paste worked, but the picker UI greyed every image out.
///
/// The fix is one line in `pickerContentTypes`. This test pins
/// it: if anyone re-introduces an image filter on the picker,
/// `swift test` fails before the build ships.
final class AttachmentPickerTypesTests: XCTestCase {

    func testPickerAllowsImages() {
        let types = SessionAttachment.pickerContentTypes
        XCTAssertTrue(
            types.contains(where: { $0.conforms(to: .image) }),
            "Picker must accept images — drag/paste is not the only path"
        )
    }

    func testPickerAllowsCommonDocumentTypes() {
        let types = SessionAttachment.pickerContentTypes
        XCTAssertTrue(types.contains(where: { $0.conforms(to: .pdf) }))
        XCTAssertTrue(types.contains(where: { $0.conforms(to: .plainText) }))
        XCTAssertTrue(types.contains(where: { $0.conforms(to: .json) }))
    }

    func testFromURLClassifiesImageExtension() {
        let url = URL(fileURLWithPath: "/tmp/screenshot.png")
        let attachment = SessionAttachment.from(url: url)
        XCTAssertEqual(attachment?.kind, .image)
        XCTAssertEqual(attachment?.detail, "Image")
    }
}
