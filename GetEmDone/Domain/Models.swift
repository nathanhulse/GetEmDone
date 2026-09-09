import Foundation

enum HouseholdRole: String, CaseIterable, Identifiable, Codable {
    case parent
    case child

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum ChoreEvidence: String, CaseIterable, Identifiable, Codable {
    case checkIn
    case photo
    case timer

    var id: Self { self }

    var title: String {
        switch self {
        case .checkIn: "Check in"
        case .photo: "Photo"
        case .timer: "Timer"
        }
    }

    var symbol: String {
        switch self {
        case .checkIn: "checkmark.circle"
        case .photo: "camera"
        case .timer: "timer"
        }
    }
}

enum ChoreState: String, Codable {
    case waiting
    case submitted
    case approved
}

struct Chore: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var detail: String
    var evidence: ChoreEvidence
    var state: ChoreState

    init(id: UUID = UUID(), title: String, detail: String, evidence: ChoreEvidence, state: ChoreState = .waiting) {
        self.id = id
        self.title = title
        self.detail = detail
        self.evidence = evidence
        self.state = state
    }
}

enum AccessState: Equatable {
    case locked
    case awaitingApproval
    case unlocked(until: Date?)

    var title: String {
        switch self {
        case .locked: "Focus mode is on"
        case .awaitingApproval: "Ready for approval"
        case .unlocked: "Entertainment unlocked"
        }
    }
}

struct ManagedDevice: Identifiable, Hashable {
    enum Kind: String {
        case iPhone = "iPhone"
        case appleTV = "Apple TV"
    }

    let id: UUID
    var name: String
    var kind: Kind
    var isProtected: Bool
    var isReachable: Bool

    init(id: UUID = UUID(), name: String, kind: Kind, isProtected: Bool, isReachable: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isProtected = isProtected
        self.isReachable = isReachable
    }
}

