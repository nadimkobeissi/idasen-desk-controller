//
//  PositionPreferences.swift
//  Desk Controller
//
//  Created by David Williames on 11/1/21.
//

import Foundation
import LaunchAtLogin

enum Position: Sendable {
    case sit, stand, custom(height: Float)
}

@MainActor
class Preferences {

    static let shared = Preferences()

    private let standingKey = "standingPositionValue"
    private let sittingKey = "sittingPositionValue"

    private let automaticStandKey = "automaticStandValue"
    private let automaticStandInactivityKey = "automaticStandInactivityKey"
    private let automaticStandEnabledKey = "automaticStandEnabledKey"

    private let offsetKey = "positionOffsetValue"

    private let isMetricKey = "isMetric"

    private let hasLaunched = "hasLaunched"

    var standingPosition: Float {
        get { UserDefaults.standard.object(forKey: standingKey) as? Float ?? 110 }
        set { UserDefaults.standard.set(newValue, forKey: standingKey) }
    }

    var sittingPosition: Float {
        get { UserDefaults.standard.object(forKey: sittingKey) as? Float ?? 70 }
        set { UserDefaults.standard.set(newValue, forKey: sittingKey) }
    }

    var automaticStandPerHour: TimeInterval {
        get { UserDefaults.standard.object(forKey: automaticStandKey) as? TimeInterval ?? 10 * 60 }
        set {
            UserDefaults.standard.set(newValue, forKey: automaticStandKey)
            DeskController.shared?.autoStand.update()
        }
    }

    var automaticStandInactivity: TimeInterval {
        get { UserDefaults.standard.object(forKey: automaticStandInactivityKey) as? TimeInterval ?? 5 * 60 }
        set { UserDefaults.standard.set(newValue, forKey: automaticStandInactivityKey) }
    }

    var automaticStandEnabled: Bool {
        get { UserDefaults.standard.object(forKey: automaticStandEnabledKey) as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: automaticStandEnabledKey)
            DeskController.shared?.autoStand.update()
        }
    }

    var positionOffset: Float {
        get { UserDefaults.standard.object(forKey: offsetKey) as? Float ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: offsetKey) }
    }

    var isMetric: Bool {
        get { UserDefaults.standard.object(forKey: isMetricKey) as? Bool ?? (Locale.current.measurementSystem == .metric) }
        set { UserDefaults.standard.set(newValue, forKey: isMetricKey) }
    }

    var openAtLogin: Bool {
        get { LaunchAtLogin.isEnabled }
        set { LaunchAtLogin.isEnabled = newValue }
    }

    var isFirstLaunch: Bool {
        get { !(UserDefaults.standard.object(forKey: hasLaunched) as? Bool ?? false) }
        set { UserDefaults.standard.set(!newValue, forKey: hasLaunched) }
    }

    func forPosition(_ position: Position) -> Float {
        switch position {
        case .sit:
            return sittingPosition - positionOffset
        case .stand:
            return standingPosition - positionOffset
        case .custom(let height):
            return height - positionOffset
        }
    }

    var measurementMetric: Unit {
        return isMetric ? UnitLength.centimeters : UnitLength.inches
    }
}
