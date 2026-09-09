import Foundation

public enum SharedPolicyMode: String, Codable, Sendable {
    case locked
    case unlocked
    case disabled
}

public struct SharedScreenTimePolicy: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var policyVersion: UInt64
    public var deviceEnrollmentID: UUID
    public var mode: SharedPolicyMode
    public var selectionData: Data?
    public var grantExpiresAt: Date?
    public var safetyReleaseAt: Date

    public init(policyVersion: UInt64, deviceEnrollmentID: UUID, mode: SharedPolicyMode, selectionData: Data?, grantExpiresAt: Date?, safetyReleaseAt: Date) {
        self.schemaVersion = Self.currentSchemaVersion
        self.policyVersion = policyVersion
        self.deviceEnrollmentID = deviceEnrollmentID
        self.mode = mode
        self.selectionData = selectionData
        self.grantExpiresAt = grantExpiresAt
        self.safetyReleaseAt = safetyReleaseAt
    }

    public func shouldShield(at date: Date) -> Bool {
        guard schemaVersion == Self.currentSchemaVersion, mode == .locked, date < safetyReleaseAt else { return false }
        return grantExpiresAt.map { date >= $0 } ?? true
    }
}

public enum SharedPolicyStoreError: Error {
    case unavailableContainer
    case unsupportedSchema
}

public struct SharedPolicyStore: Sendable {
    public static let appGroupIdentifier = "group.com.getemdone.shared"
    private let fileURL: URL

    public init(containerURL: URL) {
        fileURL = containerURL.appending(path: "Library/Application Support/ScreenTime/policy-v1.json")
    }

    public static func appGroup() throws -> SharedPolicyStore {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw SharedPolicyStoreError.unavailableContainer
        }
        return SharedPolicyStore(containerURL: url)
    }

    public func load() throws -> SharedScreenTimePolicy? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let policy = try JSONDecoder().decode(SharedScreenTimePolicy.self, from: Data(contentsOf: fileURL))
        guard policy.schemaVersion == SharedScreenTimePolicy.currentSchemaVersion else { throw SharedPolicyStoreError.unsupportedSchema }
        return policy
    }

    public func save(_ policy: SharedScreenTimePolicy) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(policy)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
