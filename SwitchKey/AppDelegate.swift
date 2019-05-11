//
//  AppDelegate.swift
//  SwitchKey
//
//  Created by Jinyu Li on 2019/03/16.
//  Copyright © 2019 Jinyu Li. All rights reserved.
//

import Cocoa
import Carbon
import ServiceManagement

extension Notification.Name {
    static let killLauncher = Notification.Name("KillSwitchKeyLauncher")
}

private let itemCellIdentifier = NSUserInterfaceItemIdentifier("item-cell")
private let editCellIdentifier = NSUserInterfaceItemIdentifier("edit-cell")

private func applicationSwitchedCallback(_ axObserver: AXObserver, axElement: AXUIElement, notification: CFString, userData: UnsafeMutableRawPointer?) {
    if let userData = userData {
        let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
        appDelegate.applicationSwitched()
    }
}

private func hasAccessibilityPermission() -> Bool {
    let promptFlag = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
    let myDict: CFDictionary = NSDictionary(dictionary: [promptFlag: false])
    return AXIsProcessTrustedWithOptions(myDict)
}

private func askForAccessibilityPermission() {
    let alert = NSAlert.init()
    alert.messageText = "SwitchKey requires accessibility permissions."
    alert.informativeText = "Please re-launch SwitchKey after you've granted permission in system preferences."
    alert.addButton(withTitle: "Configure Accessibility Settings")
    alert.alertStyle = NSAlert.Style.warning

    if alert.runModal() == .alertFirstButtonReturn {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.activate(options: .activateIgnoringOtherApps)
        NSApplication.shared.terminate(nil)
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    @IBOutlet weak var statusBarMenu: NSMenu!
    @IBOutlet weak var conditionTableView: TableView! {
        didSet {
            conditionTableView.appDelegate = self
            conditionTableView.register(NSNib(nibNamed: "SwitchKey", bundle: nil), forIdentifier: itemCellIdentifier)
            conditionTableView.register(NSNib(nibNamed: "SwitchKey", bundle: nil), forIdentifier: editCellIdentifier)
        }
    }

    private var applicationObservers:[pid_t:AXObserver] = [:]
    private var currentPid:pid_t = getpid()

    private var conditionItems: [ConditionItem] = []

    private var statusBarItem: NSStatusItem!
    private var launchAtStartupItem: NSMenuItem!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if !hasAccessibilityPermission() {
            askForAccessibilityPermission()
        }

        loadConditions()

        conditionTableView.dataSource = self
        conditionTableView.delegate = self

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem.button {
            button.image = NSImage(named: "StatusIcon")
        }
        statusBarItem.menu = statusBarMenu
        let statusBarMenuViewContainer = statusBarMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        statusBarMenuViewContainer.view = conditionTableView

        statusBarMenu.addItem(NSMenuItem.separator())
        launchAtStartupItem = statusBarMenu.addItem(withTitle: "Launch at login", action: #selector(menuDidLaunchAtStartupToggled), keyEquivalent: "")
        launchAtStartupItem.state = LoginServiceKit.isExistLoginItems() ? .on : .off
        launchAtStartupItem.target = self

        statusBarMenu.addItem(withTitle: "Quit", action: #selector(menuDidQuitClicked), keyEquivalent: "").target = self

        NotificationCenter.default.addObserver(self, selector: #selector(menuDidEndTracking(_:)), name: NSMenu.didEndTrackingNotification, object: nil)

        let workspace = NSWorkspace.shared

        workspace.notificationCenter.addObserver(self, selector: #selector(applicationLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: workspace)

        workspace.notificationCenter.addObserver(self, selector: #selector(applicationTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: workspace)

        for application in workspace.runningApplications {
            registerForAppSwitchNotification(application.processIdentifier)
        }

        applicationSwitched()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for (_, observer) in applicationObservers {
            CFRunLoopRemoveSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }

    fileprivate func applicationSwitched() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let application = NSWorkspace.shared.frontmostApplication {
                let switchedPid:pid_t = application.processIdentifier
                if (switchedPid != self.currentPid && switchedPid != getpid()) {
                    for condition in self.conditionItems {
                        if !condition.enabled {
                            continue
                        }
                        if condition.applicationIdentifier == application.bundleIdentifier {
                            if let inputSource = InputSource.with(condition.inputSourceID) {
                                inputSource.activate()
                            }
                            break
                        }
                    }
                    self.currentPid = switchedPid
                }
            }
        }
    }

    @objc private func menuDidEndTracking(_ notification: Notification) {
        conditionTableView.selectRowIndexes([], byExtendingSelection: false)
    }

    @objc private func menuDidLaunchAtStartupToggled() {
        if launchAtStartupItem.state == .on {
            launchAtStartupItem.state = .off
            LoginServiceKit.removeLoginItems()
        } else {
            launchAtStartupItem.state = .on
            LoginServiceKit.addLoginItems()
        }
    }

    @objc private func menuDidQuitClicked() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func applicationLaunched(_ notification: NSNotification) {
        let pid = notification.userInfo!["NSApplicationProcessIdentifier"] as! pid_t
        registerForAppSwitchNotification(pid)
        applicationSwitched()
    }

    @objc private func applicationTerminated(_ notification: NSNotification) {
        let pid = notification.userInfo!["NSApplicationProcessIdentifier"] as! pid_t
        if let observer = applicationObservers[pid] {
            CFRunLoopRemoveSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(observer), .defaultMode)
            applicationObservers.removeValue(forKey: pid)
        }
    }

    private func registerForAppSwitchNotification(_ pid: pid_t) {
        if pid != getpid() {
            if applicationObservers[pid] == nil {
                var observer: AXObserver!
                guard AXObserverCreate(pid, applicationSwitchedCallback, &observer) == .success else {
                    fatalError("")
                }
                CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(observer), .defaultMode)

                let element = AXUIElementCreateApplication(pid)
                let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
                AXObserverAddNotification(observer, element, NSAccessibility.Notification.applicationActivated.rawValue as CFString, selfPtr)
                applicationObservers[pid] = observer
            }
        }
    }

    func loadConditions() {
        if let conditions = UserDefaults.standard.array(forKey: "Conditions") as? [[String:Any]] {
            for c in conditions {
                let conditionItem = ConditionItem()
                if let inputSource = InputSource.with(c["InputSourceID"] as! String) {
                    conditionItem.applicationIdentifier = c["ApplicationIdentifier"] as! String
                    conditionItem.inputSourceID = inputSource.inputSourceID();
                    conditionItem.enabled = c["Enabled"] as! Bool
                    conditionItem.inputSourceIcon = inputSource.icon()
                    conditionItem.applicationName = c["ApplicationName"] as! String
                    conditionItem.applicationIcon = NSImage(data: c["ApplicationIcon"] as! Data)!
                    conditionItems.append(conditionItem)
                }
            }
        }
    }

    func saveConditions() {
        var conditions:[[String:Any]] = []
        for conditionItem in conditionItems {
            var c:[String:Any] = [:]
            c["ApplicationIdentifier"] = conditionItem.applicationIdentifier
            c["InputSourceID"] = conditionItem.inputSourceID
            c["Enabled"] = conditionItem.enabled

            c["ApplicationName"] = conditionItem.applicationName
            let cgRef = conditionItem.applicationIcon.cgImage(forProposedRect: nil, context: nil, hints: nil)
            let pngData = NSBitmapImageRep(cgImage: cgRef!)
            pngData.size = conditionItem.applicationIcon.size
            c["ApplicationIcon"] = pngData.representation(using: .png, properties: [:])

            conditions.append(c)
        }
        UserDefaults.standard.set(conditions, forKey: "Conditions")
    }

    func addCondition() {
        if let currentApplication = NSWorkspace.shared.frontmostApplication {
            var newItemRow = 0;
            defer {
                conditionTableView.reloadData()
                conditionTableView.selectRowIndexes([newItemRow], byExtendingSelection: false)
                saveConditions()
            }
            let inputSource = InputSource.current()

            if conditionItems.count > 0 {
                for row in 1 ... conditionItems.count {
                    let conditionItem = conditionItems[row - 1]
                    if conditionItem.applicationIdentifier == currentApplication.bundleIdentifier {
                        conditionItem.inputSourceID = inputSource.inputSourceID()
                        conditionItem.inputSourceIcon = inputSource.icon()
                        newItemRow = row;
                        return
                    }
                }
            }

            let conditionItem = ConditionItem()

            conditionItem.applicationIdentifier = currentApplication.bundleIdentifier ?? ""
            conditionItem.applicationName = currentApplication.localizedName ?? ""
            conditionItem.applicationIcon = currentApplication.icon ?? NSImage()

            conditionItem.inputSourceID = inputSource.inputSourceID()
            conditionItem.inputSourceIcon = inputSource.icon()

            conditionItem.enabled = true

            conditionItems.insert(conditionItem, at: 0)
            newItemRow = 1;
        }
    }

    func removeCondition(row: Int) {
        if row > 0 {
            conditionItems.remove(at: row - 1)
            conditionTableView.reloadData()
            saveConditions()
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if row > 0 {
            let item = conditionItems[row - 1]
            let itemCell = conditionTableView.makeView(withIdentifier: itemCellIdentifier, owner: nil) as! ConditionCell
            itemCell.appIcon.image = item.applicationIcon
            itemCell.appName.stringValue = item.applicationName
            
            let icon = item.inputSourceIcon
            itemCell.inputSourceButton.image = icon
            itemCell.inputSourceButton.image?.isTemplate = icon.canTemplate()
            
            itemCell.conditionEnabled.state = item.enabled ? .on : .off
            return itemCell
        } else {
            return conditionTableView.makeView(withIdentifier: editCellIdentifier, owner: nil)
        }
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if row > 0 {
            return conditionItems[row - 1]
        } else {
            return self
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if row > 0 {
            return 64
        } else {
            return 19
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = TableRowView()
        view.highlight = row > 0
        return view
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return conditionItems.count + 1
    }
}

class TableView: NSTableView {
    var appDelegate: AppDelegate! = nil

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let rowAtPoint = row(at: point)
        selectRowIndexes([rowAtPoint], byExtendingSelection: false)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.type == NSEvent.EventType.keyDown && event.keyCode == kVK_Delete {
            appDelegate.removeCondition(row: selectedRow)
        } else {
            super.keyDown(with: event)
        }
    }
}

class TableRowView: NSTableRowView {
    var highlight: Bool = true

    override func drawSelection(in dirtyRect: NSRect) {
        if highlight {
            NSColor.labelColor.withAlphaComponent(0.2).setFill()
            self.bounds.fill()
        }
    }
}

class ConditionItem {
    var applicationIdentifier: String = ""
    var applicationName: String = ""
    var applicationIcon: NSImage = NSImage()
    var inputSourceID: String = ""
    var inputSourceIcon: NSImage = NSImage()
    var enabled: Bool = false
}

class ConditionCell: NSTableCellView {
    @IBOutlet weak var appIcon: NSImageView!
    @IBOutlet weak var appName: NSTextField!
    @IBOutlet weak var conditionEnabled: NSButton!
    @IBOutlet weak var inputSourceButton: NSButton!
    @IBAction func inputSourceButtonClicked(_ sender: Any) {
        let item = objectValue as! ConditionItem
        if let inputSource = InputSource.with(item.inputSourceID) {
            inputSource.activate()
        }
    }
    @IBAction func toggleEnabled(_ sender: Any) {
        let item = objectValue as! ConditionItem
        item.enabled = conditionEnabled.state == .on;
    }
}

class EditCell: NSTableCellView {
    @IBAction func addItemClicked(_ sender: Any) {
        let app = objectValue as! AppDelegate
        app.addCondition()
    }
}
