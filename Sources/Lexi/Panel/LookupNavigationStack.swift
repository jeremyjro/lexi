import Foundation

struct LookupNode: Identifiable, Equatable {
    let id: UUID
    let term: String
    let sourceText: String
    var answer: String
    let parentId: UUID?
    let appName: String
    let windowTitle: String
    let sourceLabel: String
}

struct LookupNavigationStack: Equatable {
    private(set) var nodesById: [UUID: LookupNode]
    let rootId: UUID
    private(set) var currentId: UUID

    init(rootTerm: String, sourceText: String, answer: String, appName: String, windowTitle: String, sourceLabel: String) {
        let root = LookupNode(
            id: UUID(),
            term: rootTerm,
            sourceText: sourceText,
            answer: answer,
            parentId: nil,
            appName: appName,
            windowTitle: windowTitle,
            sourceLabel: sourceLabel
        )
        nodesById = [root.id: root]
        rootId = root.id
        currentId = root.id
    }

    var currentNode: LookupNode? {
        nodesById[currentId]
    }

    var depth: Int {
        max(0, activePath.count - 1)
    }

    var activePath: [LookupNode] {
        var path: [LookupNode] = []
        var nextId: UUID? = currentId
        while let id = nextId, let node = nodesById[id] {
            path.append(node)
            nextId = node.parentId
        }
        return path.reversed()
    }

    mutating func pushDummy(term rawTerm: String) {
        guard let parent = currentNode else { return }
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        let child = LookupNode(
            id: UUID(),
            term: term,
            sourceText: parent.answer,
            answer: "Nested lookup placeholder for \"\(term)\".\n\nPhase 1 proves the navigation stack, breadcrumb, selection, back, root jump, and cached parent restore. Phase 2 will replace this dummy answer with a real streamed lineage-aware explanation.",
            parentId: parent.id,
            appName: "Lexi",
            windowTitle: "Nested lookup from \(parent.term)",
            sourceLabel: "Lexi answer"
        )
        nodesById[child.id] = child
        currentId = child.id
    }

    mutating func pop() -> Bool {
        guard let parentId = currentNode?.parentId else { return false }
        currentId = parentId
        return true
    }

    mutating func jumpToRoot() {
        currentId = rootId
    }

    mutating func jump(to nodeId: UUID) {
        guard nodesById[nodeId] != nil else { return }
        currentId = nodeId
    }
}
