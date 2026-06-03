import Foundation

/// Pure coordinator for workflow undo / redo stacks.
///
/// Holds the last `maxCount` snapshots of a `WorkflowDocument` and exposes
/// deterministic `undo` / `redo` transitions. All mutating APIs take the
/// current workflow as a parameter so the owner (e.g. `AppStore`) keeps
/// authority over persistence.
struct UndoRedoCoordinator {
    /// Cap on retained snapshots. Older entries are dropped FIFO.
    static let maxCount = 30

    private(set) var undoStack: [WorkflowDocument] = []
    private(set) var redoStack: [WorkflowDocument] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoCount: Int { undoStack.count }
    var redoCount: Int { redoStack.count }

    /// Record a snapshot before a mutating action. Skips duplicate trailing
    /// snapshots and always clears the redo stack.
    mutating func recordSnapshot(_ workflow: WorkflowDocument) {
        if undoStack.last != workflow {
            undoStack.append(workflow)
        }
        if undoStack.count > Self.maxCount {
            undoStack.removeFirst(undoStack.count - Self.maxCount)
        }
        redoStack.removeAll()
    }

    /// Pop the most recent snapshot and return it. The current workflow is
    /// pushed onto the redo stack so it can be re-applied later.
    mutating func performUndo(current: WorkflowDocument) -> WorkflowDocument? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Pop the most recent redo snapshot and return it. The current workflow
    /// is pushed onto the undo stack so further undos remain valid.
    mutating func performRedo(current: WorkflowDocument) -> WorkflowDocument? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    /// Drop both stacks. Call when the workspace or workflow identity changes.
    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
