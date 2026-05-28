//
//  PreferencesWindowController.swift
//  Desk Controller
//
//  Created by David Williames on 11/1/21.
//

import Cocoa

class PreferencesWindowController: NSWindowController {
    
    @IBOutlet weak var standingHeightField: NSTextField!
    @IBOutlet weak var sittingHeightField: NSTextField!
    
    @IBOutlet weak var unitsPopUpButton: NSPopUpButton!
    @IBOutlet weak var currentHeightField: NSTextField?

    @IBOutlet weak var doubleTapToSitStandCheckbox: NSButton!
    
    @IBOutlet weak var autoStandEnabledCheckbox: NSButton!
    @IBOutlet weak var autoStandIntervalStepper: NSStepper!
    @IBOutlet weak var autoStandIntervalLabel: NSTextField!
    @IBOutlet weak var autoStandInactiveStepper: NSStepper!
    @IBOutlet weak var autoStandInactiveLabel: NSTextField!
    
    @IBOutlet weak var openAtLoginCheckbox: NSButton!
    
    static let sharedInstance = PreferencesWindowController(windowNibName: "PreferencesWindowController")
    private let contentWidth: CGFloat = 300
    private let formLabelWidth: CGFloat = 120
    
    var deskController: DeskController? {
        didSet {
            deskPosition = deskController?.desk.position
            // Always (re-)register the position observer with the *current*
            // DeskController. The controller is rebuilt on every BT
            // reconnect, so a one-time hookup in windowDidLoad would point
            // at a stale instance after a reconnect.
            deskController?.onPositionChange({ [weak self] position in
                self?.deskPosition = position
            })
        }
    }

    var deskPosition: Float? {
        didSet {
            currentHeightField?.isEnabled = (deskPosition != nil)

            var offsetPosition = Preferences.shared.positionOffset + (deskPosition ?? 0)
            if !Preferences.shared.isMetric {
                offsetPosition = offsetPosition.convertToInches()
            }
            currentHeightField?.stringValue = String(format: "%.1f", offsetPosition)

            // Move the marker on the position bar to track the desk.
            schedulePreview?.currentPosition = deskPosition
        }
    }
    
    private var notifyInsteadCheckbox: NSButton?
    private var schedulePreview: SchedulePreviewView?

    override func windowDidLoad() {
        super.windowDidLoad()

        rebuildContentView()

        updateLabels()

        // The first-load registration is a no-op when deskController is set
        // via the property setter (didSet handles re-registration there);
        // this covers the legacy code path where deskController existed
        // before the property setter fired.
        deskController?.onPositionChange({ [weak self] position in
            self?.deskPosition = position
        })
    }

    private func rebuildContentView() {
        guard let content = window?.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }

        let standingField = makeTextField(action: #selector(changeStandingHeightField(_:)))
        standingHeightField = standingField

        let sittingField = makeTextField(action: #selector(changedSittingHeightField(_:)))
        sittingHeightField = sittingField

        let unitsButton = NSPopUpButton()
        unitsButton.addItems(withTitles: ["cm", "inches"])
        unitsButton.target = self
        unitsButton.action = #selector(changedUnitsPopUpButton(_:))
        unitsButton.translatesAutoresizingMaskIntoConstraints = false
        unitsButton.widthAnchor.constraint(equalToConstant: 120).isActive = true
        unitsPopUpButton = unitsButton

        let currentField = makeTextField(action: #selector(changedCurrentHeightField(_:)))
        currentHeightField = currentField

        let calibrationText = makeHelpText(
            "To calibrate the correct height of the desk, measure the current distance from floor to the desktop and enter the value."
        )

        let doubleTapCheckbox = NSButton(
            checkboxWithTitle: "Double tap handle to sit and stand",
            target: self,
            action: #selector(toggledDoubleTaptoSitStandCheckbox(_:))
        )
        doubleTapToSitStandCheckbox = doubleTapCheckbox

        let doubleTapText = makeHelpText(
            "Double tap on the desk control handle to automatically move to your sit and stand presets. Double tap up to stand and down to sit."
        )

        let autoStandCheckbox = NSButton(
            checkboxWithTitle: "Automatically stand",
            target: self,
            action: #selector(toggledAutoStandCheckbox(_:))
        )
        autoStandEnabledCheckbox = autoStandCheckbox
        masterAutoStandCheckbox = autoStandCheckbox

        let standEveryRow = makeMinutesRow(label: "Stand every:",
                                            value: Preferences.shared.standEveryMinutes,
                                            min: 1, max: 240,
                                            action: #selector(changedAutoStandStepper(_:)),
                                            stepperOut: &programmaticStandEveryStepper,
                                            labelOut: &programmaticStandEveryLabel)
        autoStandIntervalStepper = programmaticStandEveryStepper
        autoStandIntervalLabel = programmaticStandEveryLabel

        let standForRow = makeMinutesRow(label: "Stand for:",
                                         value: Preferences.shared.standForMinutes,
                                         min: 5, max: 60,
                                         action: #selector(changedStandForStepper(_:)),
                                         stepperOut: &programmaticStandForStepper,
                                         labelOut: &programmaticStandForLabel)

        let timeoutRow = makeMinutesRow(label: "Activity timeout:",
                                        value: Int(Preferences.shared.automaticStandInactivity / 60),
                                        min: 1, max: 60,
                                        action: #selector(changedAutoStandInactiveStepper(_:)),
                                        stepperOut: &programmaticActivityStepper,
                                        labelOut: &programmaticActivityLabel)
        autoStandInactiveStepper = programmaticActivityStepper
        autoStandInactiveLabel = programmaticActivityLabel

        let autoStandText = makeHelpText(
            "Sit for the first interval, then stand for the second, then repeat. Skipped if you've been idle longer than the activity timeout."
        )

        let preview = SchedulePreviewView(frame: .zero)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 210).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 8).isActive = true
        schedulePreview = preview

        let previewContainer = NSView()
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(preview)
        NSLayoutConstraint.activate([
            previewContainer.widthAnchor.constraint(equalToConstant: contentWidth - 36),
            previewContainer.heightAnchor.constraint(equalToConstant: 12),
            preview.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            preview.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor)
        ])

        let loginCheckbox = NSButton(
            checkboxWithTitle: "Open Desk Controller at login",
            target: self,
            action: #selector(toggledOpenAtLoginCheckbox(_:))
        )
        openAtLoginCheckbox = loginCheckbox

        let notifyToggle = NSButton(
            checkboxWithTitle: "Notify instead of moving the desk",
            target: self,
            action: #selector(toggledNotifyInstead(_:))
        )
        notifyInsteadCheckbox = notifyToggle

        let stack = NSStackView(views: [
            makeFormRow(label: "Standing height:", control: standingField),
            makeFormRow(label: "Sitting height:", control: sittingField),
            makeFormRow(label: "Units:", control: unitsButton),
            makeFormRow(label: "Current height:", control: currentField),
            calibrationText,
            makeSeparator(),
            doubleTapCheckbox,
            doubleTapText,
            makeSeparator(),
            autoStandCheckbox,
            standEveryRow,
            standForRow,
            timeoutRow,
            autoStandText,
            previewContainer,
            makeSeparator(),
            loginCheckbox,
            notifyToggle
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: contentWidth),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])

        if let win = window {
            content.layoutSubtreeIfNeeded()
            let fittingSize = stack.fittingSize
            win.setContentSize(NSSize(width: contentWidth, height: fittingSize.height + 36))
            win.minSize = NSSize(width: contentWidth, height: fittingSize.height + 36)
        }
    }

    // MARK: programmatic-stack helpers

    private var masterAutoStandCheckbox: NSButton?
    private var programmaticStandEveryStepper: NSStepper?
    private var programmaticStandEveryLabel: NSTextField?
    private var programmaticStandForStepper: NSStepper?
    private var programmaticStandForLabel: NSTextField?
    private var programmaticActivityStepper: NSStepper?
    private var programmaticActivityLabel: NSTextField?

    private func makeTextField(action: Selector) -> NSTextField {
        let field = NSTextField()
        field.target = self
        field.action = action
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 118).isActive = true
        return field
    }

    private func makeFormRow(label: String, control: NSView) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.alignment = .right
        title.translatesAutoresizingMaskIntoConstraints = false
        title.widthAnchor.constraint(equalToConstant: formLabelWidth).isActive = true

        let row = NSStackView(views: [title, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeHelpText(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabelColor
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = contentWidth - 36
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: contentWidth - 36).isActive = true
        return label
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: contentWidth - 36).isActive = true
        return separator
    }

    private func makeMinutesRow(label: String, value: Int, min: Double, max: Double,
                                 action: Selector,
                                 stepperOut: inout NSStepper?,
                                 labelOut: inout NSTextField?) -> NSView {
        // Right-align titles in a 120 pt column so the value sits at the same
        // x as the XIB rows above (Standing height / Sitting height / etc.).
        let title = NSTextField(labelWithString: label)
        title.alignment = .right
        title.translatesAutoresizingMaskIntoConstraints = false
        title.widthAnchor.constraint(equalToConstant: formLabelWidth).isActive = true

        let valueLabel = NSTextField(labelWithString: String(value))
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: 28).isActive = true
        labelOut = valueLabel

        let stepper = NSStepper()
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = 1
        stepper.intValue = Int32(value)
        stepper.autorepeat = true           // hold-to-spin
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = action
        stepperOut = stepper

        let unit = NSTextField(labelWithString: "min")
        unit.textColor = .secondaryLabelColor

        let row = NSStackView(views: [title, valueLabel, stepper, unit])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        return row
    }

    private func refreshSchedulePreview() {
        // Bar now visualises the desk's physical height between sit and
        // stand presets. Gray left half = sit region, green right half =
        // stand region, vertical marker = current desk height.
        let sit = Preferences.shared.sittingPosition
        let stand = Preferences.shared.standingPosition
        let enabled = Preferences.shared.automaticStandEnabled
        schedulePreview?.sittingPosition = sit
        schedulePreview?.standingPosition = stand
        schedulePreview?.currentPosition = deskPosition
        // Bar stays visible even when auto-stand is off — it's a passive
        // position indicator, not an auto-stand-only widget.
        schedulePreview?.enabled = enabled
        schedulePreview?.isHidden = false

        let standForMins = Preferences.shared.standForMinutes
        let standEveryMins = Preferences.shared.standEveryMinutes
        if enabled {
            schedulePreview?.toolTip = "Sit \(standEveryMins) min · Stand \(standForMins) min · repeat"
        } else {
            schedulePreview?.toolTip = "Sit / Stand range. Auto-stand is off."
        }
    }

    @objc private func toggledNotifyInstead(_ sender: NSButton) {
        Preferences.shared.notifyInsteadOfAutoMove = sender.state == .on
        if sender.state == .on {
            NotificationManager.shared.requestAuthorizationIfNeeded()
        }
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        AppDelegate.bringToFront(window: self.window!)
    }
    
    func updateLabels() {
        
        var standingPosition = Preferences.shared.standingPosition
        var sittingPosition = Preferences.shared.sittingPosition
        
        if !Preferences.shared.isMetric {
            standingPosition = standingPosition.convertToInches()
            sittingPosition = sittingPosition.convertToInches()
        }
        
        standingHeightField.stringValue = String(format: "%.1f", standingPosition)
        sittingHeightField.stringValue = String(format: "%.1f", sittingPosition)
        unitsPopUpButton.selectItem(at: Preferences.shared.isMetric ? 0 : 1)
        openAtLoginCheckbox.state = Preferences.shared.openAtLogin ? .on : .off
        doubleTapToSitStandCheckbox.state = Preferences.shared.doubleTapToSitStand ? .on : .off
        notifyInsteadCheckbox?.state = Preferences.shared.notifyInsteadOfAutoMove ? .on : .off
        
        // Programmatic autostand controls
        let autoEnabled = Preferences.shared.automaticStandEnabled
        autoStandEnabledCheckbox.state = autoEnabled ? .on : .off
        masterAutoStandCheckbox?.state = autoEnabled ? .on : .off
        programmaticStandEveryLabel?.stringValue = String(Preferences.shared.standEveryMinutes)
        programmaticStandEveryStepper?.intValue = Int32(Preferences.shared.standEveryMinutes)
        programmaticStandForLabel?.stringValue = String(Preferences.shared.standForMinutes)
        programmaticStandForStepper?.intValue = Int32(Preferences.shared.standForMinutes)
        let timeoutMin = Int(Preferences.shared.automaticStandInactivity / 60)
        programmaticActivityLabel?.stringValue = String(timeoutMin)
        programmaticActivityStepper?.intValue = Int32(timeoutMin)
        programmaticStandEveryStepper?.isEnabled = autoEnabled
        programmaticStandForStepper?.isEnabled = autoEnabled
        programmaticActivityStepper?.isEnabled = autoEnabled
        let stateColor: NSColor = autoEnabled ? .labelColor : .disabledControlTextColor
        programmaticStandEveryLabel?.textColor = stateColor
        programmaticStandForLabel?.textColor = stateColor
        programmaticActivityLabel?.textColor = stateColor
        
        var offsetPosition = Preferences.shared.positionOffset + (deskPosition ?? 0)
        if !Preferences.shared.isMetric {
            offsetPosition = offsetPosition.convertToInches()
        }

        currentHeightField?.stringValue = String(format: "%.1f", offsetPosition)

        refreshSchedulePreview()
    }
    
    @IBAction func changeStandingHeightField(_ sender: NSTextField) {
        
        if var newPosition = Float(standingHeightField.stringValue) {
            if !Preferences.shared.isMetric {
                newPosition = newPosition.convertToCentimeters()
            }
            Preferences.shared.standingPosition = newPosition
        }
        
    }
    
    @IBAction func changedSittingHeightField(_ sender: NSTextField) {
        
        if var newPosition = Float(sittingHeightField.stringValue) {
            if !Preferences.shared.isMetric {
                newPosition = newPosition.convertToCentimeters()
            }
            Preferences.shared.sittingPosition = newPosition
        }
    }
    
    @IBAction func changedCurrentHeightField(_ sender: NSTextField) {
        
        if var newPosition = Float(sender.stringValue), let deskPosition = deskPosition {
            if !Preferences.shared.isMetric {
                newPosition = newPosition.convertToCentimeters()
            }
            let offset = newPosition - deskPosition
            Preferences.shared.positionOffset = offset
        }
    }

    @IBAction func toggledDoubleTaptoSitStandCheckbox(_ sender: NSButton) {
        Preferences.shared.doubleTapToSitStand = sender.state == .on
    }
    
    @IBAction func toggledAutoStandCheckbox(_ sender: NSButton) {
        Preferences.shared.automaticStandEnabled = sender.state == .on
        updateLabels()
        (NSApp.delegate as? AppDelegate)?.refreshAutoStandIcon()
    }
    
    @objc private func changedStandForStepper(_ sender: NSStepper) {
        Preferences.shared.standForMinutes = Int(sender.intValue)
        updateLabels()
    }

    @IBAction func changedAutoStandStepper(_ sender: NSStepper) {
        Preferences.shared.standEveryMinutes = Int(sender.intValue)
        updateLabels()
    }
    
    @IBAction func changedAutoStandInactiveStepper(_ sender: NSStepper) {
        let newInactive = Double(sender.intValue)
        Preferences.shared.automaticStandInactivity = newInactive * 60
        updateLabels()
    }
    
    @IBAction func changedUnitsPopUpButton(_ sender: NSPopUpButton) {
        Preferences.shared.isMetric = sender.titleOfSelectedItem == "cm"
        updateLabels()
    }
    
    @IBAction func toggledOpenAtLoginCheckbox(_ sender: NSButton) {
        Preferences.shared.openAtLogin = sender.state == .on
    }


}


// MARK: - Desk position bar

/// Visual indicator of the desk's *physical* position between the sit and
/// stand presets. The bar's left edge = `sittingPosition`, right edge =
/// `standingPosition`. Left half is gray (sit region), right half is green
/// (stand region), split at the midpoint. A vertical marker shows where the
/// desk currently sits within that range.
final class SchedulePreviewView: NSView {

    /// Lower-bound cm (the sit preset).
    var sittingPosition: Float = 70 {
        didSet { if oldValue != sittingPosition { needsDisplay = true } }
    }
    /// Upper-bound cm (the stand preset).
    var standingPosition: Float = 110 {
        didSet { if oldValue != standingPosition { needsDisplay = true } }
    }
    /// Current desk height in cm, or `nil` if not connected yet.
    var currentPosition: Float? {
        didSet { if oldValue != currentPosition { needsDisplay = true } }
    }
    var enabled: Bool = true {
        didSet { if oldValue != enabled { needsDisplay = true } }
    }

    override var wantsDefaultClipping: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius: CGFloat = rect.height / 2

        let sit = sittingPosition
        let stand = standingPosition
        guard stand > sit else {
            // Degenerate: presets misconfigured. Just draw an empty track.
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return
        }

        // Left half (gray = sit region).
        let trackFill: NSColor = enabled ? .quaternaryLabelColor : .quaternaryLabelColor.withAlphaComponent(0.5)
        trackFill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        // Right half (green = stand region) clipped to rounded outline.
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        let standFill: NSColor = enabled
            ? .systemGreen
            : NSColor.systemGreen.withAlphaComponent(0.4)
        standFill.setFill()
        let rightHalf = NSRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
        rightHalf.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        // Current-position marker.
        if let current = currentPosition {
            let clamped = max(sit, min(stand, current))
            let t = CGFloat((clamped - sit) / (stand - sit))   // 0…1
            let x = rect.minX + rect.width * t
            let markerWidth: CGFloat = 2
            let markerRect = NSRect(x: x - markerWidth / 2,
                                    y: rect.minY - 2,
                                    width: markerWidth,
                                    height: rect.height + 4)
            let markerColor: NSColor = enabled ? .labelColor : .labelColor.withAlphaComponent(0.5)
            markerColor.setFill()
            markerRect.fill()
        }

        // Outer border.
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()
    }
}
