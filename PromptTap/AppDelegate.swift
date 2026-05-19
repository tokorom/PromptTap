//
//  AppDelegate.swift
//  PromptTap
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyController: HotkeyController?
    private var ipcServer: PromptTapIPCServer?
    private var activationObserver: NSObjectProtocol?
    private var windowCloseObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private weak var model: PromptTapModel?

    func configure(model: PromptTapModel, settings: AppSettings) {
        guard self.model == nil else {
            return
        }

        self.model = model

        let controller = HotkeyController(model: model, settings: settings)
        controller.start()
        hotkeyController = controller

        let server = PromptTapIPCServer(model: model)
        server.start()
        ipcServer = server

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak model] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let model else {
                return
            }

            Task { @MainActor [application, model] in
                model.noteActivatedApplication(application)
            }
        }

        settings.$hotkey
            .sink { [weak controller] _ in
                controller?.reset()
            }
            .store(in: &cancellables)

        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak model] notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier?.rawValue.hasPrefix("main") == true else {
                return
            }
            Task { @MainActor [weak model] in
                model?.cancelActiveExternalEditSession()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppEnvironment.print()
        AppAnalytics.setup()
        AppAnalytics.track(event: .firstLaunch())
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppAnalytics.track(event: .becomeActive())
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyController?.stop()
        model?.cancelActiveExternalEditSession()
        ipcServer?.stop()

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor [weak model] in
                model?.openFromShortcut(isHotkey: false)
            }
            return false
        }
        return true
    }
}
