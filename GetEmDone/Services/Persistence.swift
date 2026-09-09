import Foundation

protocol HouseholdPersistence: Sendable {
    func load() async throws -> HouseholdSnapshot?
    func save(_ snapshot: HouseholdSnapshot, revision: UInt64) async throws
}

actor LocalHouseholdPersistence: HouseholdPersistence {
    private let fileURL: URL
    private var latestRevision: UInt64 = 0

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = root.appending(path: "GetEmDone/household.json")
        }
    }

    func load() throws -> HouseholdSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(HouseholdSnapshot.self, from: Data(contentsOf: fileURL))
    }

    func save(_ snapshot: HouseholdSnapshot, revision: UInt64) throws {
        guard revision >= latestRevision else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        latestRevision = revision
    }
}

actor MemoryHouseholdPersistence: HouseholdPersistence {
    private(set) var snapshot: HouseholdSnapshot?
    private(set) var latestRevision: UInt64 = 0

    init(snapshot: HouseholdSnapshot? = nil) { self.snapshot = snapshot }
    func load() -> HouseholdSnapshot? { snapshot }
    func save(_ snapshot: HouseholdSnapshot, revision: UInt64) {
        guard revision >= latestRevision else { return }
        self.snapshot = snapshot
        latestRevision = revision
    }
}
