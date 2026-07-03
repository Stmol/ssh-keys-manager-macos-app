import AppKit
import XCTest
@testable import SSH_Keys_Manager

final class SSHKeyFileActionsTests: XCTestCase {
    private var pasteboards: [NSPasteboard] = []

    override func tearDown() {
        for pasteboard in pasteboards {
            pasteboard.clearContents()
        }

        pasteboards.removeAll()
        super.tearDown()
    }

    func testSensitiveCopyClearsPasteboardAfterTimeout() throws {
        let pasteboard = try makePasteboard()
        let actions = SSHKeyFileActions(pasteboard: pasteboard)

        actions.copySensitiveToPasteboard("PRIVATE_KEY", clearAfter: 0.05)

        wait(for: 0.12)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testSensitiveCopyDoesNotClearDifferentClipboardContent() throws {
        let pasteboard = try makePasteboard()
        let actions = SSHKeyFileActions(pasteboard: pasteboard)

        actions.copySensitiveToPasteboard("PRIVATE_KEY", clearAfter: 0.08)
        pasteboard.clearContents()
        pasteboard.setString("new clipboard value", forType: .string)

        wait(for: 0.15)
        XCTAssertEqual(pasteboard.string(forType: .string), "new clipboard value")
    }

    func testConsecutiveSensitiveCopiesCancelFirstClear() throws {
        let pasteboard = try makePasteboard()
        let actions = SSHKeyFileActions(pasteboard: pasteboard)

        actions.copySensitiveToPasteboard("FIRST_PRIVATE_KEY", clearAfter: 0.05)
        wait(for: 0.02)
        actions.copySensitiveToPasteboard("SECOND_PRIVATE_KEY", clearAfter: 0.15)

        wait(for: 0.08)
        XCTAssertEqual(pasteboard.string(forType: .string), "SECOND_PRIVATE_KEY")

        wait(for: 0.12)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testSensitiveCopyWithZeroClearDelayLeavesPasteboardUnchanged() throws {
        let pasteboard = try makePasteboard()
        let actions = SSHKeyFileActions(pasteboard: pasteboard)

        actions.copySensitiveToPasteboard("PRIVATE_KEY", clearAfter: 0)

        wait(for: 0.08)
        XCTAssertEqual(pasteboard.string(forType: .string), "PRIVATE_KEY")
    }

    private func makePasteboard() throws -> NSPasteboard {
        let pasteboard = try XCTUnwrap(
            NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        )
        pasteboards.append(pasteboard)
        return pasteboard
    }

    private func wait(for seconds: TimeInterval) {
        let expectation = expectation(description: "Wait \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: seconds + 1)
    }
}
