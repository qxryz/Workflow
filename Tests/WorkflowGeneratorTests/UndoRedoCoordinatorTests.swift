import XCTest
@testable import WorkflowGenerator

final class UndoRedoCoordinatorTests: XCTestCase {
    private func makeWorkflow(name: String) -> WorkflowDocument {
        WorkflowDocument(name: name)
    }

    func testInitialStateHasNoUndoOrRedo() {
        let coordinator = UndoRedoCoordinator()
        XCTAssertFalse(coordinator.canUndo)
        XCTAssertFalse(coordinator.canRedo)
        XCTAssertEqual(coordinator.undoCount, 0)
        XCTAssertEqual(coordinator.redoCount, 0)
    }

    func testRecordSnapshotEnablesUndo() {
        var coordinator = UndoRedoCoordinator()
        let workflow = makeWorkflow(name: "v1")
        coordinator.recordSnapshot(workflow)
        XCTAssertTrue(coordinator.canUndo)
        XCTAssertEqual(coordinator.undoCount, 1)
        XCTAssertFalse(coordinator.canRedo)
    }

    func testDuplicateTrailingSnapshotIsIgnored() {
        var coordinator = UndoRedoCoordinator()
        let workflow = makeWorkflow(name: "v1")
        coordinator.recordSnapshot(workflow)
        coordinator.recordSnapshot(workflow)
        XCTAssertEqual(coordinator.undoCount, 1)
    }

    func testUndoReturnsPreviousWorkflowAndPushesCurrentToRedo() {
        var coordinator = UndoRedoCoordinator()
        let v1 = makeWorkflow(name: "v1")
        let v2 = makeWorkflow(name: "v2")
        coordinator.recordSnapshot(v1)
        let restored = coordinator.performUndo(current: v2)
        XCTAssertEqual(restored, v1)
        XCTAssertFalse(coordinator.canUndo)
        XCTAssertTrue(coordinator.canRedo)
        XCTAssertEqual(coordinator.redoCount, 1)
    }

    func testRedoReturnsNextWorkflowAndPushesCurrentToUndo() {
        var coordinator = UndoRedoCoordinator()
        let v1 = makeWorkflow(name: "v1")
        let v2 = makeWorkflow(name: "v2")
        coordinator.recordSnapshot(v1)
        _ = coordinator.performUndo(current: v2)
        let restored = coordinator.performRedo(current: v1)
        XCTAssertEqual(restored, v2)
        XCTAssertTrue(coordinator.canUndo)
        XCTAssertFalse(coordinator.canRedo)
    }

    func testRecordSnapshotClearsRedoStack() {
        var coordinator = UndoRedoCoordinator()
        let v1 = makeWorkflow(name: "v1")
        let v2 = makeWorkflow(name: "v2")
        let v3 = makeWorkflow(name: "v3")
        coordinator.recordSnapshot(v1)
        _ = coordinator.performUndo(current: v2)
        XCTAssertTrue(coordinator.canRedo)
        coordinator.recordSnapshot(v3)
        XCTAssertFalse(coordinator.canRedo)
    }

    func testUndoAtEmptyStackReturnsNil() {
        var coordinator = UndoRedoCoordinator()
        let v1 = makeWorkflow(name: "v1")
        XCTAssertNil(coordinator.performUndo(current: v1))
        XCTAssertEqual(coordinator.undoCount, 0)
    }

    func testStackRespectsMaxCount() {
        var coordinator = UndoRedoCoordinator()
        var previous = makeWorkflow(name: "v0")
        for index in 1...UndoRedoCoordinator.maxCount + 5 {
            let workflow = makeWorkflow(name: "v\(index)")
            coordinator.recordSnapshot(previous)
            previous = workflow
        }
        XCTAssertEqual(coordinator.undoCount, UndoRedoCoordinator.maxCount)
    }

    func testClearDropsBothStacks() {
        var coordinator = UndoRedoCoordinator()
        let v1 = makeWorkflow(name: "v1")
        let v2 = makeWorkflow(name: "v2")
        coordinator.recordSnapshot(v1)
        _ = coordinator.performUndo(current: v2)
        XCTAssertTrue(coordinator.canUndo || coordinator.canRedo)
        coordinator.clear()
        XCTAssertFalse(coordinator.canUndo)
        XCTAssertFalse(coordinator.canRedo)
    }
}
