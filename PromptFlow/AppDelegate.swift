//
//  AppDelegate.swift
//  PromptFlow
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyController: HotkeyController?
    private var activationObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private weak var model: PromptFlowModel?

    func configure(model: PromptFlowModel, settings: AppSettings) {
        guard self.model == nil else {
            return
        }

        self.model = model

        let controller = HotkeyController(model: model, settings: settings)
        controller.start()
        hotkeyController = controller

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
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor [weak model] in
            model?.focusEditor()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyController?.stop()

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                if window.title != "Settings" {
                    window.makeKeyAndOrderFront(nil)
                    return false
                }
            }
        }
        return true
    }
}
