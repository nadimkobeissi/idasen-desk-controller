//
//  DeskPreset.swift
//  Desk Controller
//
//  Data model for a single desk height preset (built-in sit/stand or user-added).
//

import Foundation

struct DeskPreset: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var heightCm: Float
    var isBuiltIn: Bool
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, heightCm: Float, isBuiltIn: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.heightCm = heightCm
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
    }

    static func == (lhs: DeskPreset, rhs: DeskPreset) -> Bool { lhs.id == rhs.id }
}

extension DeskPreset {
    /// Fixed IDs so the built-in "Sitting" / "Standing" presets survive renames/reorders.
    static let sittingPresetId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let standingPresetId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    static func defaultSittingPreset(height: Float = 70) -> DeskPreset {
        DeskPreset(id: sittingPresetId, name: "Sitting", heightCm: height, isBuiltIn: true, sortOrder: 0)
    }

    static func defaultStandingPreset(height: Float = 110) -> DeskPreset {
        DeskPreset(id: standingPresetId, name: "Standing", heightCm: height, isBuiltIn: true, sortOrder: 1)
    }
}
