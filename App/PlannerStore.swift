import Combine
import Foundation

private actor PlannerFileIO {
    let url: URL
    init(url: URL) { self.url = url }
    func load() throws -> [PlannerTaskRecord] { try PlannerPersistence.load(from: url) }
    func save(_ records: [PlannerTaskRecord], reset: Bool = false) throws {
        try PlannerPersistence.save(records, to: url, replacingInvalidFile: reset)
    }
}

@MainActor
final class PlannerStore: ObservableObject {
    @Published private(set) var records: [PlannerTaskRecord] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var isSaving = false
    @Published private(set) var error: String?
    private let file: PlannerFileIO
    private var attemptedLoad = false

    init(url: URL = PlannerPersistence.defaultURL) { file = PlannerFileIO(url: url) }

    func load() async {
        guard !attemptedLoad else { return }
        attemptedLoad = true
        do {
            var loaded = try await file.load()
            // No execution is controlled by Tallygent. An app restart cannot prove completion.
            for index in loaded.indices where loaded[index].outcome == .running { loaded[index].outcome = .interrupted }
            records = loaded
            isLoaded = true
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func saveTask(profile: PlannerProfile, preference: PlannerPreference, configuration: PlannerConfiguration,
                  title: String?, quota: PlannerQuota, start: Bool) async -> Bool {
        guard isLoaded, !isSaving, records.count < 500, configuration.isValid else { return false }
        let record = PlannerTaskRecord(title: title.map { String($0.prefix(120)) }, profile: profile,
                                       preference: preference, configuration: configuration, createdAt: .now,
                                       startedAt: start ? .now : nil, before: start ? quota : nil,
                                       outcome: start ? .running : .planned)
        return await commit([record] + records)
    }

    func start(_ id: UUID, quota: PlannerQuota) async {
        guard let index = records.firstIndex(where: { $0.id == id }), records[index].configuration.model.provider == quota.provider,
              records[index].outcome == .planned else { return }
        var values = records
        values[index].startedAt = .now; values[index].before = quota; values[index].outcome = .running
        _ = await commit(values)
    }

    func complete(_ id: UUID, outcome: PlannerOutcome, quota: PlannerQuota, retries: Int,
                  quality: Int?, rework: Bool, verification: PlannerVerification, tokens: PlannerTokenUsage?) async {
        guard outcome.isEvaluated || outcome == .notEvaluated,
              let index = records.firstIndex(where: { $0.id == id }),
              [.running, .interrupted].contains(records[index].outcome) else { return }
        var values = records
        values[index].outcome = outcome; values[index].completedAt = .now
        values[index].after = quota.provider == values[index].configuration.model.provider ? quota : nil
        values[index].retries = retries; values[index].quality = quality; values[index].manualRework = rework
        values[index].verification = verification; values[index].tokens = tokens
        _ = await commit(values)
    }

    func delete(_ id: UUID) async { _ = await commit(records.filter { $0.id != id }) }
    func clear() async { _ = await commit([], reset: true) }

    @discardableResult
    private func commit(_ values: [PlannerTaskRecord], reset: Bool = false) async -> Bool {
        guard !isSaving, isLoaded || reset else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await file.save(values, reset: reset)
            records = values; error = nil; isLoaded = true
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
