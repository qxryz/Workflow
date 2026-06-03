import XCTest
@testable import WorkflowGenerator

final class ConsistencyContextCompilerTests: XCTestCase {
    private let compiler = ConsistencyContextCompiler()

    func testDisabledProfileYieldsEmptyContext() {
        var profile = MediaConsistencyProfile()
        profile.enabled = false
        let context = compiler.compile(
            profile: profile,
            snapshot: [],
            delta: [],
            node: sampleImageNode()
        )
        XCTAssertEqual(context.globalPrompt, "")
        XCTAssertTrue(context.categoryPrompts.isEmpty)
        XCTAssertTrue(context.referenceArtifacts.isEmpty)
        XCTAssertTrue(context.lockedConstraints.isEmpty)
    }

    func testGlobalPromptAndSeedArePropagated() {
        var profile = MediaConsistencyProfile()
        profile.enabled = true
        profile.stylePrompt = "cinematic warm tones"
        profile.seed = "fixed-seed-42"
        let context = compiler.compile(
            profile: profile,
            snapshot: [],
            delta: [],
            node: sampleImageNode()
        )
        XCTAssertEqual(context.globalPrompt, "cinematic warm tones")
        XCTAssertTrue(context.lockedConstraints.contains("Seed: fixed-seed-42"))
    }

    func testImageNodeFiltersToRelevantCategories() {
        var profile = MediaConsistencyProfile()
        profile.enabled = true
        let character = makeAsset(name: "hero", category: .character, strength: 0.9)
        let voice = makeAsset(name: "narrator", category: .voice, strength: 0.95)
        let context = compiler.compile(
            profile: profile,
            snapshot: [character, voice],
            delta: [],
            node: sampleImageNode()
        )
        XCTAssertEqual(context.referenceArtifacts, ["/assets/hero.png"])
        XCTAssertFalse(context.referenceArtifacts.contains("/assets/narrator.png"))
    }

    func testRenderIncludesGlobalAndReferences() {
        var profile = MediaConsistencyProfile()
        profile.enabled = true
        profile.stylePrompt = "noir"
        let asset = makeAsset(name: "hero", category: .character, strength: 0.9)
        let context = compiler.compile(
            profile: profile,
            snapshot: [asset],
            delta: [],
            node: sampleImageNode()
        )
        let rendered = compiler.render(context)
        XCTAssertTrue(rendered.contains("Global: noir"))
        XCTAssertTrue(rendered.contains("- /assets/hero.png"))
    }

    // MARK: - Helpers

    private func makeAsset(name: String, category: ConsistencyCategoryKind, strength: Double) -> ConsistencyAsset {
        var asset = ConsistencyAsset(
            category: category,
            displayCategory: category.title,
            name: name,
            assetType: .image,
            artifactPath: "/assets/\(name).png",
            sourceNodeId: nil,
            sourceRunId: nil,
            sourceRouteId: nil
        )
        asset.description = "desc-\(name)"
        asset.promptSnippets = ConsistencyPromptSnippets(positive: ["p-\(name)"], negative: [])
        asset.strength = strength
        return asset
    }

    private func sampleImageNode() -> WorkflowNode {
        WorkflowNode(
            title: "image-gen",
            description: "generate",
            kind: .model,
            modelId: nil,
            agentExecutable: nil,
            position: CanvasPoint(x: 0, y: 0),
            inputModalities: [.text],
            outputModalities: [.image],
            chat: [],
            draftMessage: ""
        )
    }
}
