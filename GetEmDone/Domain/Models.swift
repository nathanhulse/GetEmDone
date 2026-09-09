import Foundation

enum HouseholdRole: String, CaseIterable, Identifiable, Codable, Sendable {
    case parent
    case child

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum ChoreEvidence: String, CaseIterable, Identifiable, Codable, Sendable {
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

enum ChoreState: String, Codable, Sendable {
    case waiting
    case submitted
    case approved
}

enum EvidenceProgress: Hashable, Codable, Sendable {
    case none
    case photoReady
    case timer(seconds: Int)

    var isReady: Bool {
        switch self {
        case .none: false
        case .photoReady: true
        case .timer(let seconds): seconds > 0
        }
    }
}

struct Chore: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var detail: String
    var evidence: ChoreEvidence
    var state: ChoreState
    var activeWeekdays: Set<Int>
    var dueMinutes: Int?
    var isArchived: Bool
    var evidenceProgress: EvidenceProgress
    var minimumTimerSeconds: Int

    init(id: UUID = UUID(), title: String, detail: String, evidence: ChoreEvidence, state: ChoreState = .waiting, activeWeekdays: Set<Int> = Set(1...7), dueMinutes: Int? = nil, isArchived: Bool = false, evidenceProgress: EvidenceProgress = .none, minimumTimerSeconds: Int = 60) {
        self.id = id
        self.title = title
        self.detail = detail
        self.evidence = evidence
        self.state = state
        self.activeWeekdays = activeWeekdays
        self.dueMinutes = dueMinutes
        self.isArchived = isArchived
        self.evidenceProgress = evidenceProgress
        self.minimumTimerSeconds = minimumTimerSeconds
    }


    var canSubmit: Bool {
        switch evidence {
        case .checkIn: return true
        case .photo: return evidenceProgress == .photoReady
        case .timer:
            if case .timer(let seconds) = evidenceProgress { return seconds >= minimumTimerSeconds }
            return false
        }
    }

    var recurrenceLabel: String {
        if activeWeekdays == Set(1...7) { return "Every day" }
        if activeWeekdays == Set(2...6) { return "Weekdays" }
        if activeWeekdays == [1, 7] { return "Weekends" }
        return "\(activeWeekdays.count) days a week"
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

struct ManagedDevice: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
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

struct ActivityEvent: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case submitted
        case approved
        case redoRequested
        case override
        case dailyReset
        case choreCreated
        case choreRemoved
        case choreEdited
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let message: String

    init(id: UUID = UUID(), date: Date = .now, kind: Kind, message: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.message = message
    }
}

struct HouseholdSnapshot: Codable, Sendable {
    var childName: String
    var chores: [Chore]
    var devices: [ManagedDevice]
    var history: [ActivityEvent]
}
