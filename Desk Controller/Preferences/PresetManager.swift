//
//  PresetManager.swift
//  Desk Controller
//
//  CRUD + persistence for user-defined desk height presets, with one-time
//  migration from the legacy `sittingPositionValue`/`standingPositionValue`
//  UserDefaults keys.
//

import Foundation

extension Notification.Name {
    static let presetsDidChange = Notification.Name("presetsDidChange")
}

@MainActor
final class PresetManager {

    static let shared = PresetManager()

    private let presetsKey = "deskPresets"
    private let hasMigratedKey = "hasMigratedPresets"

    private let legacySittingKey = "sittingPositionValue"
    private let legacyStandingKey = "standingPositionValue"

    private(set) var presets: [DeskPreset] = []

    private init() {
        loadPresets()
        migrateIfNeeded()
    }

    // MARK: - CRUD

    func addPreset(name: String, heightCm: Float) {
        let maxSortOrder = presets.map(\.sortOrder).max() ?? -1
        presets.append(DeskPreset(name: name, heightCm: heightCm, sortOrder: maxSortOrder + 1))
        savePresets()
        notifyChanged()
    }

    func updatePreset(id: UUID, name: String? = nil, heightCm: Float? = nil) {
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        if let name { presets[idx].name = name }
        if let heightCm { presets[idx].heightCm = heightCm }
        savePresets()
        notifyChanged()

        // Keep the legacy sittingPosition/standingPosition keys in sync so the rest
        // of the app (which still reads `Preferences.shared.sittingPosition` etc.)
        // sees built-in preset edits immediately.
        if id == DeskPreset.sittingPresetId, let heightCm {
            Preferences.shared.sittingPosition = heightCm
        } else if id == DeskPreset.standingPresetId, let heightCm {
            Preferences.shared.standingPosition = heightCm
        }
    }

    func deletePreset(id: UUID) {
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        guard !presets[idx].isBuiltIn else { return }
        presets.remove(at: idx)
        savePresets()
        notifyChanged()
    }

    func preset(for id: UUID) -> DeskPreset? { presets.first { $0.id == id } }

    func reorderPresets(_ newOrder: [DeskPreset]) {
        for (index, preset) in newOrder.enumerated() {
            if let existing = presets.firstIndex(where: { $0.id == preset.id }) {
                presets[existing].sortOrder = index
            }
        }
        presets.sort { $0.sortOrder < $1.sortOrder }
        savePresets()
        notifyChanged()
    }

    /// User-defined presets (excluding the built-in Sitting/Standing), sorted.
    var customPresets: [DeskPreset] {
        presets.filter { !$0.isBuiltIn }.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Persistence

    private func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let saved = try? JSONDecoder().decode([DeskPreset].self, from: data) {
            presets = saved.sorted { $0.sortOrder < $1.sortOrder }
            return
        }
        presets = [.defaultSittingPreset(), .defaultStandingPreset()]
        savePresets()
    }

    private func savePresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: presetsKey)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .presetsDidChange, object: nil)
    }

    // MARK: - Legacy migration

    private func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasMigratedKey) else { return }
        if let sit = UserDefaults.standard.object(forKey: legacySittingKey) as? Float {
            updatePreset(id: DeskPreset.sittingPresetId, heightCm: sit)
        }
        if let stand = UserDefaults.standard.object(forKey: legacyStandingKey) as? Float {
            updatePreset(id: DeskPreset.standingPresetId, heightCm: stand)
        }
        UserDefaults.standard.set(true, forKey: hasMigratedKey)
    }
}
