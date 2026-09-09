import Foundation

protocol HouseholdPersistence: Sendable {
    func load() async throws -> HouseholdSnapshot?
    func save(_ snapshot: HouseholdSnapshot) async throws
}

actor LocalHouseholdPersistence: HouseholdPersistence {
    private let fileURL: URL

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

    func save(_ snapshot: HouseholdSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}

actor MemoryHouseholdPersistence: HouseholdPersistence {
    private(set) var snapshot: HouseholdSnapshot?

    init(snapshot: HouseholdSnapshot? = nil) { self.snapshot = snapshot }
    func load() -> HouseholdSnapshot? { snapshot }
    func save(_ snapshot: HouseholdSnapshot) { self.snapshot = snapshot }
}

