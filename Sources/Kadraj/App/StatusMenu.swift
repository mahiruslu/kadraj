import AppKit
import KadrajCore

/// Menü çubuğundaki Kadraj ikonu ve menüsü.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let permissionItem = NSMenuItem()
    private let onPermissionClick: () -> Void

    init(appInfo: AppInfo, onPermissionClick: @escaping () -> Void) {
        self.onPermissionClick = onPermissionClick
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Kadraj")

        let menu = NSMenu()
        menu.delegate = self
        let versionItem = NSMenuItem(title: appInfo.displayString, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        permissionItem.target = self
        permissionItem.action = #selector(permissionClicked)
        menu.addItem(permissionItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Kadraj'dan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        refreshPermission()
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { refreshPermission() }
    }

    private func refreshPermission() {
        permissionItem.title = ScreenCapturePermission.status.menuTitle
    }

    @objc private func permissionClicked() {
        if ScreenCapturePermission.status == .notGranted { onPermissionClick() }
    }
}
