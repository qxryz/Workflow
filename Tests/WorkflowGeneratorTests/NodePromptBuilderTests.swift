import XCTest
@testable import WorkflowGenerator

final class NodePromptBuilderTests: XCTestCase {
    private let builder = NodePromptBuilder()

    func testModelNodeIgnoresAttachments() {
        let prompt = builder.prompt(text: "describe scene", attachments: ["/tmp/a.png"], nodeKind: .model)
        XCTAssertEqual(prompt, "describe scene")
    }

    func testAgentNodeAppendsAttachmentList() {
        let prompt = builder.prompt(
            text: "fix bug",
            attachments: ["/tmp/a.swift", "/tmp/b.swift"],
            nodeKind: .agent
        )
        XCTAssertEqual(prompt, "fix bug\n\nAttached files:\n- /tmp/a.swift\n- /tmp/b.swift")
    }

    func testAgentNodeWithoutAttachmentsReturnsPlainText() {
        let prompt = builder.prompt(text: "explain this", attachments: [], nodeKind: .agent)
        XCTAssertEqual(prompt, "explain this")
    }

    func testConsistencyNodeWithAttachmentsStillReturnsPlainText() {
        let prompt = builder.prompt(
            text: "absorb",
            attachments: ["/tmp/a.png"],
            nodeKind: .consistency
        )
        XCTAssertEqual(prompt, "absorb")
    }
}
