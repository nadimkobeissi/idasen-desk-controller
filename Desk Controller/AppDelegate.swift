//
//  AppDelegate.swift
//  Desk Controller
//
//  Created by David Williames on 10/1/21.
//

import Cocoa

@main @MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var eventMonitor: EventMonitor?

    var viewController: ViewController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()

        // If it's the first launch set the value for Open at Login to true
        if Preferences.shared.isFirstLaunch {
            Preferences.shared.openAtLogin = true
            Preferences.shared.isFirstLaunch = false
        }

        // Don't show the icon in the Dock
        NSApp.setActivationPolicy(.accessory)

        // Setup the right click menu
        let statusBarMenu = NSMenu(title: "Desk Controller Menu")
        statusBarMenu.addItem(withTitle: "Move to sit", action: #selector(moveToSit), keyEquivalent: "")
        statusBarMenu.addItem(withTitle: "Move to stand", action: #selector(moveToStand), keyEquivalent: "")
        statusBarMenu.addItem(.separator())
        statusBarMenu.addItem(withTitle: "Preferences", action: #selector(showPreferences), keyEquivalent: "")
        statusBarMenu.addItem(.separator())
        statusBarMenu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "")


        // Set the status bar icon and action
        if let button = statusBarItem.button {

            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            button.image = NSImage(systemSymbolName: "arrow.up.and.down.circle", accessibilityDescription: "Desk Controller")?.withSymbolConfiguration(config)

            button.menu = statusBarMenu
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(AppDelegate.clickedStatusItem(_:))
        }

        if let mainViewController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "ViewControllerId") as? ViewController {
            mainViewController.popover = popover
            viewController = mainViewController
            popover.contentViewController = mainViewController
        }

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self = self, self.popover.isShown {
                    self.closePopover(nil)
                }
            }
        }
        eventMonitor?.start()
    }

    @objc func showPreferences() {
        PreferencesWindowController.sharedInstance.showWindow(nil)
        PreferencesWindowController.sharedInstance.deskController = viewController?.controller
        popover.performClose(self)
    }

    @objc func moveToSit() {
        viewController?.controller?.moveToPosition(.sit)
    }

    @objc func moveToStand() {
        viewController?.controller?.moveToPosition(.stand)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {

    }

    @objc func clickedStatusItem(_ sender: NSStatusItem) {
        guard let event = NSApp.currentEvent else {
            return
        }

        if event.type == .rightMouseUp {
            if let button = statusBarItem.button, let menu = button.menu {
                menu.popUp(positioning: nil, at: CGPoint(x: -15, y: button.bounds.maxY + 6), in: button)
            }
        } else {
            togglePopover(sender)
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }

    func showPopover(_ sender: AnyObject?) {

        guard let button = statusBarItem.button else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        eventMonitor?.start()

        viewController?.reconnect()
    }

    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }

    public static func bringToFront(window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}
