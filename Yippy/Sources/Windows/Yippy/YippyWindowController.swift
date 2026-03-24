//
//  YippyWindowController.swift
//  Yippy
//
//  Created by Matthew Davidson on 25/9/19.
//  Copyright © 2019 MatthewDavidson. All rights reserved.
//

import Foundation
import Cocoa
import RxSwift
import RxRelay

class YippyWindowController: NSWindowController {

    private var oldApp: NSRunningApplication?
    private var toggleRelay: BehaviorRelay<Bool>?
    private var shouldHideOnExternalKeyDown = false
    private var shouldRestorePreviousAppOnClose = true
    private var externalKeyDownMonitor: Any?
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        window?.level = NSWindow.Level(NSWindow.Level.mainMenu.rawValue - 2)
        window?.setAccessibilityIdentifier(Accessibility.identifiers.yippyWindow)
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKeyNotification(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKeyNotification(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        externalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hideOnExternalTypingIfNeeded()
            }
        }
    }
    
    static func createYippyWindowController() -> YippyWindowController {
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let identifier = NSStoryboard.SceneIdentifier(stringLiteral: "YippyWindowController")
        guard let windowController = storyboard.instantiateController(withIdentifier: identifier) as? YippyWindowController else {
            fatalError("Failed to load YippyWindowController of type YippyWindowController from the Main storyboard.")
        }
        
        return windowController
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let externalKeyDownMonitor {
            NSEvent.removeMonitor(externalKeyDownMonitor)
        }
    }
    
    func subscribeTo(toggle: BehaviorRelay<Bool>) -> Disposable {
        toggleRelay = toggle
        return toggle
            .subscribe(onNext: {
                [] in
                if !$0 {
                    self.hideWindow(reactivatePreviousApp: self.shouldRestorePreviousAppOnClose)
                }
                else {
                    self.shouldRestorePreviousAppOnClose = true
                    self.shouldHideOnExternalKeyDown = false
                    self.oldApp = NSWorkspace.shared.frontmostApplication
                    self.showWindow(nil)
                    self.window?.makeKey()
                    NSApp.activate(ignoringOtherApps: true)
                }
            })
    }
    
    func subscribeFrameTo(position: Observable<PanelPosition>, screen: Observable<NSScreen>) -> Disposable {
        Observable.combineLatest(position, screen).subscribe(onNext: {
            (position, screen) in
            self.window?.setFrame(position.getFrame(forScreen: screen), display: true)
        })
    }

    @objc private func windowDidBecomeKeyNotification(_ notification: Notification) {
        shouldHideOnExternalKeyDown = false
    }

    @objc private func windowDidResignKeyNotification(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        shouldHideOnExternalKeyDown = true
    }

    private func hideOnExternalTypingIfNeeded() {
        guard shouldHideOnExternalKeyDown else { return }
        guard window?.isVisible == true else {
            shouldHideOnExternalKeyDown = false
            return
        }
        guard window?.isKeyWindow == false else {
            shouldHideOnExternalKeyDown = false
            return
        }

        shouldRestorePreviousAppOnClose = false
        toggleRelay?.accept(false)
    }

    private func hideWindow(reactivatePreviousApp: Bool) {
        shouldHideOnExternalKeyDown = false
        shouldRestorePreviousAppOnClose = true
        self.close()
        if reactivatePreviousApp {
            self.oldApp?.activate(options: .activateIgnoringOtherApps)
        }
    }
}
