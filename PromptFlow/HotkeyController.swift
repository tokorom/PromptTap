//
//  HotkeyController.swift
//  PromptFlow
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import AppKit

@MainActor
final class HotkeyController {
    private weak var model: PromptFlowModel?
    private weak var settings: AppSettings?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var lastPressDate: Date?
    private var wasPressed = false

    private let maximumDoubleTapInterval: TimeInterval = 0.45

    init(model: PromptFlowModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
    }

    func start() {
        stop()

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)

        if isTrusted {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                Task { @MainActor in
                    self?.handle(event)
                }
            }

            globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
                Task { @MainActor in
                    self?.reset()
                }
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
            return event
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.reset()
            }
            return event
        }
    }

    func reset() {
        lastPressDate = nil
        wasPressed = false
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
        }

        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
        }

        globalMonitor = nil
        localMonitor = nil
        globalKeyDownMonitor = nil
        localKeyDownMonitor = nil
        reset()
    }

    private func handle(_ event: NSEvent) {
        guard let trigger = settings?.hotkey else {
            return
        }

        let modifierFlag = trigger.modifierFlag
        let isPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(modifierFlag)

        defer {
            wasPressed = isPressed
        }

        guard isPressed, !wasPressed else {
            return
        }

        let now = Date()
        if let lastPressDate, now.timeIntervalSince(lastPressDate) <= maximumDoubleTapInterval {
            self.lastPressDate = nil
            model?.openFromShortcut()
        } else {
            lastPressDate = now
        }
    }
}
