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
    private(set) var childIdsByParentId: [UUID: [UUID]]
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
        childIdsByParentId = [:]
        rootId = root.id
        currentId = root.id
    }

    var currentNode: LookupNode? {
        nodesById[currentId]
    }

    var rootNode: LookupNode? {
        nodesById[rootId]
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

    mutating func pushPending(term rawTerm: String) -> UUID? {
        pushChild(
            title: rawTerm,
            windowTitlePrefix: "Nested lookup from",
            sourceLabel: "Lexi answer"
        )
    }

    mutating func pushFollowUp(question rawQuestion: String) -> UUID? {
        pushChild(
            title: rawQuestion,
            windowTitlePrefix: "Follow-up from",
            sourceLabel: "Follow-up"
        )
    }

    private mutating func pushChild(title rawTitle: String, windowTitlePrefix: String, sourceLabel: String) -> UUID? {
        guard let parent = currentNode else { return nil }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let child = LookupNode(
            id: UUID(),
            term: title,
            sourceText: parent.answer,
            answer: "",
            parentId: parent.id,
            appName: "Lexi",
            windowTitle: "\(windowTitlePrefix) \(parent.term)",
            sourceLabel: sourceLabel
        )
        nodesById[child.id] = child
        childIdsByParentId[parent.id, default: []].append(child.id)
        currentId = child.id
        return child.id
    }

    mutating func updateAnswer(nodeId: UUID, answer: String) {
        guard var node = nodesById[nodeId] else { return }
        node.answer = answer
        nodesById[nodeId] = node
    }

    mutating func pop() -> Bool {
        guard let parentId = currentNode?.parentId else { return false }
        currentId = parentId
        return true
    }

    mutating func jumpToLatestChild() -> Bool {
        guard let latestChildId = childIdsByParentId[currentId]?.last,
              nodesById[latestChildId] != nil else { return false }
        currentId = latestChildId
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
