import Combine
import Foundation

final class AppGroupStorageValue<T: Codable & Equatable>: ObservableObject {

    let key: String
    private let defaults: UserDefaults

    @Published var value: T {
        didSet {
            guard value != oldValue else { return }
            save(value)
        }
    }

    var exists: Bool {
        defaults.object(forKey: key) != nil
    }

    init(appGroupID: String, key: String, defaultValue: T) {
        self.key = key
        self.defaults = UserDefaults(suiteName: appGroupID) ?? .standard

        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            self.value = decoded
        } else {
            self.value = defaultValue
        }
    }

    func remove() {
        defaults.removeObject(forKey: key)
    }

    private func save(_ newValue: T) {
        if let data = try? JSONEncoder().encode(newValue) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: - One-time migration helper

    static func migrateFromStandardIfNeeded(appGroupID: String, key: String) {
        let standard = UserDefaults.standard
        guard let legacyData = standard.data(forKey: key) else { return }

        let group = UserDefaults(suiteName: appGroupID) ?? .standard
        if group.object(forKey: key) == nil {
            group.set(legacyData, forKey: key)
        }
    }
}
